import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
extension ProfilesViewModel {
    func dialerProxyGraph(for profile: Profile) async -> ProfileDialerProxyGraph? {
        let latest = profiles.first(where: { $0.id == profile.id }) ?? profile
        guard let raw = runtimeSourceYAML(for: latest) else { return nil }
        var bare = latest
        bare.dialerProxies = nil
        let building = bare
        return await Task.detached(priority: .userInitiated) { () -> ProfileDialerProxyGraph? in
            guard let built = try? ProfileRuntimeConfigBuilder.buildProductionStages(
                    raw: raw, profile: building
                  ).afterClientTransforms,
                  let root = (try? ConfigTransforms.foundationRoot(ofYAML: built)) ?? nil else { return nil }
            return ProfileDialerProxyGraph(root: root)
        }.value
    }

     
     
    func setDialerProxy(_ target: String?, for node: String, profileID: String) async throws {
        try await saveValidated(profileID: profileID,
                                gone: PipelineError.sourceUnavailable("the profile is no longer available")) { latest in
            var updated = latest
            let next = ProfileDialerProxies.setting(latest.dialerProxies ?? [], target: target, for: node)
            updated.dialerProxies = next.isEmpty ? nil : next
            return updated
        }
    }

    func clearDialerProxies(profileID: String) async throws {
        try await saveValidated(profileID: profileID,
                                gone: PipelineError.sourceUnavailable("the profile is no longer available")) { latest in
            var updated = latest
            updated.dialerProxies = nil
            return updated
        }
    }
}

struct DialerProxyRequest: Identifiable, Equatable {
    let node: String
    var id: String { node }
}

enum DialerProxyCopy {
    static func issue(_ issue: ProfileDialerProxyIssue) -> String {
        switch issue {
        case .missingNode: return "node gone, skipped"
        case .missingTarget: return "dialer proxy gone, skipped"
        case .cycle: return "would loop, skipped"
        }
    }
}

 
 
 
struct DialerProxyPickerSheet: View {
    @ObservedObject var profiles: ProfilesViewModel
    let profile: Profile
    let node: String
    let close: () -> Void

    @State private var graph: ProfileDialerProxyGraph?
    @State private var loaded = false
    @State private var query = ""
    @State private var saving = false
    @State private var failure: String?

    private var latest: Profile { profiles.profiles.first { $0.id == profile.id } ?? profile }
    private var settings: [ProfileDialerProxy] { latest.dialerProxies ?? [] }

    var body: some View {
        ClashFeatureNavigationContainer {
            content
                .clashPageTitle("Set Dialer Proxy")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        ClashSheetCloseButton { close() }
                    }
                }
        }
        .task(id: profile.id) {
            graph = await profiles.dialerProxyGraph(for: latest)
            loaded = true
        }
        .alert(
            "Could not save the dialer proxy",
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(verbatim: failure ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if !loaded {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let graph, graph.proxySet.contains(node) {
            picker(graph)
        } else if graph != nil {
            ClashEmptyState(
                title: "Set Dialer Proxy",
                message: "This node comes from a proxy provider and cannot take its own dialer proxy",
                symbol: .link
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("dialer-proxy.provider-node")
        } else {
            ClashEmptyState(
                title: "Set Dialer Proxy",
                message: "The configuration can't be read right now.",
                symbol: .exclamationmarkTriangle
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func picker(_ graph: ProfileDialerProxyGraph) -> some View {
        let candidates = ProfileDialerProxies.candidates(graph, settings, node: node)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = needle.isEmpty ? candidates : candidates.filter { $0.localizedCaseInsensitiveContains(needle) }
        let groups = Set(graph.groups)
        let own = ProfileDialerProxies.setting(settings, for: node)
        let current = own ?? graph.existing[node]
        return List {
            Section {
                Text(verbatim: node)
                    .font(.headline)
                if let current, current != ProfileDialerProxies.direct {
                    Text(clash: .format("via %@", [current]))
                        .foregroundStyle(.secondary)
                }
                if own == nil, graph.existing[node] != nil {
                    Text(ClashCopy.key("from profile"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if needle.isEmpty {
                Section {
                    row(title: Text(ClashCopy.key("No Dialer Proxy")),
                        selected: current == nil || current == ProfileDialerProxies.direct) {
                        pick(nil, graph: graph)
                    }
                    .accessibilityIdentifier("dialer-proxy.none")
                }
            }
            let shownGroups = shown.filter { groups.contains($0) }
            if !shownGroups.isEmpty {
                Section(ClashCopy.key("Proxy Groups")) {
                    ForEach(shownGroups, id: \.self) { name in
                        row(title: Text(verbatim: name), selected: current == name) { pick(name, graph: graph) }
                    }
                }
            }
            let shownNodes = shown.filter { !groups.contains($0) }
            if !shownNodes.isEmpty {
                Section(ClashCopy.key("Nodes")) {
                    ForEach(shownNodes, id: \.self) { name in
                        row(title: Text(verbatim: name), selected: current == name) { pick(name, graph: graph) }
                    }
                }
            }
            Section {
                NavigationLink {
                    DialerProxyListView(profiles: profiles, profile: profile)
                } label: {
                    Label {
                        Text(ClashCopy.key("All Dialer Proxies"))
                    } icon: {
                        Image(systemName: ClashSymbol.link.rawValue)
                    }
                }
                .accessibilityIdentifier("dialer-proxy.all")
            }
        }
        .searchable(text: $query, prompt: Text(ClashCopy.key("Search")))
        .disabled(saving)
    }

    private func row(title: Text, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                title
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: ClashSymbol.checkmark.rawValue)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pick(_ name: String?, graph: ProfileDialerProxyGraph) {
        let target: String?
        if let name {
            target = name
        } else {
            target = graph.existing[node] != nil ? ProfileDialerProxies.direct : nil
        }
        saving = true
        Task { @MainActor in
            defer { saving = false }
            do {
                try await profiles.setDialerProxy(target, for: node, profileID: profile.id)
                close()
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

 
 
 
struct DialerProxyListView: View {
    @ObservedObject var profiles: ProfilesViewModel
    let profile: Profile

    @State private var graph: ProfileDialerProxyGraph?
    @State private var loaded = false
    @State private var confirmsClear = false
    @State private var failure: String?

    private var latest: Profile { profiles.profiles.first { $0.id == profile.id } ?? profile }
    private var settings: [ProfileDialerProxy] { latest.dialerProxies ?? [] }

    var body: some View {
        let known = graph ?? ProfileDialerProxyGraph()
        let current = settings
        let issues = loaded && graph != nil ? ProfileDialerProxies.issues(known, current) : [:]
        let fromProfile = known.proxies.compactMap { name -> ProfileDialerProxy? in
            guard current.first(where: { $0.node == name }) == nil, let via = known.existing[name] else { return nil }
            return ProfileDialerProxy(node: name, target: via)
        }
        return Group {
            if !loaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if current.isEmpty && fromProfile.isEmpty {
                ClashEmptyState(
                    title: "Dialer Proxy",
                    message: "No dialer proxies in this profile",
                    symbol: .link
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("dialer-proxy.empty")
            } else {
                List {
                    if !current.isEmpty {
                        Section {
                            ForEach(current, id: \.node) { entry in
                                row(entry, issue: issues[entry.node], external: false)
                            }
                        } footer: {
                            if !issues.isEmpty {
                                Text(clash: .format("%@ dialer proxy settings were skipped", ["\(issues.count)"]))
                            }
                        }
                    }
                    if !fromProfile.isEmpty {
                        Section(ClashCopy.key("from profile")) {
                            ForEach(fromProfile, id: \.node) { entry in
                                row(entry, issue: nil, external: true)
                            }
                        }
                    }
                }
            }
        }
        .clashPageTitle("Dialer Proxy")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !current.isEmpty {
                    Button(role: .destructive) {
                        confirmsClear = true
                    } label: {
                        Text(ClashCopy.key("Clear All"))
                    }
                    .accessibilityIdentifier("dialer-proxy.clear-all")
                }
            }
        }
        .confirmationDialog(
            "Clear all dialer proxies set for this profile?",
            isPresented: $confirmsClear,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                run { try await profiles.clearDialerProxies(profileID: profile.id) }
            } label: {
                Text(ClashCopy.key("Clear All"))
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Could not save the dialer proxy",
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(verbatim: failure ?? "")
        }
        .task(id: profile.id) {
            graph = await profiles.dialerProxyGraph(for: latest)
            loaded = true
        }
    }

    private func row(_ entry: ProfileDialerProxy, issue: ProfileDialerProxyIssue?, external: Bool) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.node)
                if entry.target == ProfileDialerProxies.direct {
                    Text(ClashCopy.key("No Dialer Proxy"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text(clash: .format("via %@", [entry.target]))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let issue {
                    Text(ClashCopy.key(DialerProxyCopy.issue(issue)))
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            Spacer(minLength: 8)
            if !external {
                Button {
                    run { try await profiles.setDialerProxy(nil, for: entry.node, profileID: profile.id) }
                } label: {
                    Image(systemName: ClashSymbol.trash.rawValue)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .accessibilityLabel(Text(ClashCopy.key("Delete")))
                .accessibilityIdentifier("dialer-proxy.delete.\(entry.node)")
            }
        }
    }

    private func run(_ body: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do { try await body() } catch { failure = error.localizedDescription }
        }
    }
}
