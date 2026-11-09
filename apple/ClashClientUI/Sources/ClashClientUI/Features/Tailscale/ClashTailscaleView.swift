import SwiftUI

/// What the Tailscale page can ask of the running core. Each call goes to
/// the VPN extension and can take seconds, so they are async; the app
/// supplies them, as it does for DNS Query.
public struct ClashTailscaleCapabilities {
    public typealias Nodes = @MainActor () async -> ClashTailscaleNodeList
    /// Reads a node's status; `start` brings a node that has not started up
    /// first and waits for it to settle.
    public typealias Status = @MainActor (_ node: String, _ start: Bool) async -> ClashTailscaleStatus
    public typealias Ping = @MainActor (_ node: String, _ targets: [String]) async -> [ClashTailscalePing]
    /// Returns nil when it worked, or why it did not.
    public typealias Action = @MainActor (_ node: String) async -> String?

    public let nodes: Nodes
    public let status: Status
    public let ping: Ping
    public let reconnect: Action
    /// Signs the node out, deletes its saved login and reloads the profile.
    public let resetLogin: Action

    public init(
        nodes: @escaping Nodes,
        status: @escaping Status,
        ping: @escaping Ping,
        reconnect: @escaping Action,
        resetLogin: @escaping Action
    ) {
        self.nodes = nodes
        self.status = status
        self.ping = ping
        self.reconnect = reconnect
        self.resetLogin = resetLogin
    }
}

/// Tailscale nodes of the running profile: each node's state, its peers
/// with a ping that tells a direct path from a relayed one, how it reaches
/// each DERP relay, an exit node that could not be set, and Reconnect and
/// Reset Login.
public struct ClashTailscaleView: View {
    private let isConnected: Bool
    private let capabilities: ClashTailscaleCapabilities

    @State private var nodes: [ClashTailscaleNode] = []
    @State private var nodesError: String?
    @State private var selectedNodeID: String?
    @State private var status: ClashTailscaleStatus?
    @State private var pings: [String: ClashTailscalePing] = [:]
    @State private var pinging: Set<String> = []
    @State private var isLoading = false
    @State private var isActing = false
    @State private var actionMessage: String?
    @State private var confirmsReset = false

    public init(isConnected: Bool, capabilities: ClashTailscaleCapabilities) {
        self.isConnected = isConnected
        self.capabilities = capabilities
    }

    private var selectedNode: ClashTailscaleNode? {
        nodes.first { $0.id == selectedNodeID } ?? nodes.first
    }

    public var body: some View {
        List {
            nodesSection
            if let node = selectedNode, isConnected {
                statusSection(node)
                if let error = status?.exitNodeError, !error.isEmpty {
                    exitNodeSection(error)
                }
                derpSection
                peersSection(node)
                actionsSection(node)
            }
        }
        .clashRuntimeGroupedFormStyle()
        .clashPageTitle("Tailscale")
        .refreshable { await reload() }
        .task(id: isConnected) { await reload() }
        .confirmationDialog(
            "Reset Tailscale login?",
            isPresented: $confirmsReset,
            titleVisibility: .visible
        ) {
            if let node = selectedNode {
                Button("Reset Login", role: .destructive) {
                    Task { await perform(node, capabilities.resetLogin, reloadsAfter: true) }
                }
                .accessibilityIdentifier("tailscale.reset.confirm")
            }
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("tailscale.reset.cancel")
        } message: {
            Text("This signs the node out and deletes its saved login on this device, then reloads the profile. The node logs in again with its auth key, or shows a new login link.")
        }
        .accessibilityIdentifier("tailscale.page")
    }

    // MARK: Sections

    @ViewBuilder
    private var nodesSection: some View {
        Section {
            if !isConnected {
                Text("Connect the VPN to see the Tailscale nodes.")
                    .foregroundStyle(.secondary)
            } else if let nodesError {
                Text(LocalizedStringKey(nodesError))
                    .foregroundStyle(.red)
            } else if nodes.isEmpty {
                HStack {
                    Text(isLoading ? LocalizedStringKey("Loading…") : LocalizedStringKey("This profile has no Tailscale nodes."))
                        .foregroundStyle(.secondary)
                    if isLoading {
                        Spacer()
                        ProgressView()
                    }
                }
            } else {
                ForEach(nodes) { node in
                    Button {
                        guard node.id != selectedNode?.id else { return }
                        selectedNodeID = node.id
                        Task { await loadStatus(start: false) }
                    } label: {
                        nodeRow(node)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tailscale.node.\(node.name)")
                }
            }
        } header: {
            Text("Nodes")
        } footer: {
            if isConnected && !nodes.isEmpty {
                Text("A node starts the first time traffic goes through it. Tap a node to see its peers.")
            }
        }
    }

    private func nodeRow(_ node: ClashTailscaleNode) -> some View {
        HStack(spacing: 12) {
            Image(systemName: node.id == selectedNode?.id
                ? ClashSymbol.checkmarkCircleFill.rawValue
                : ClashSymbol.circle.rawValue)
                .foregroundStyle(node.id == selectedNode?.id ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: node.name)
                if let provider = node.provider, !provider.isEmpty {
                    Text("From \(provider)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            stateBadge(started: node.started)
        }
        .contentShape(Rectangle())
    }

    private func stateBadge(started: Bool) -> some View {
        Text(started ? LocalizedStringKey("Running") : LocalizedStringKey("Not started"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(started ? Color.green : .secondary)
    }

    @ViewBuilder
    private func statusSection(_ node: ClashTailscaleNode) -> some View {
        Section {
            if let status {
                if let error = status.error, !error.isEmpty {
                    Text(LocalizedStringKey(error))
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("tailscale.status.error")
                }
                row("State") {
                    Text(Self.stateTitle(status))
                        .foregroundStyle(status.backendState == "Running" ? Color.green : .secondary)
                }
                if let me = status.selfPeer {
                    row("This Device") { Text(verbatim: me.displayName) }
                    if !me.ips.isEmpty {
                        row("Addresses") {
                            Text(verbatim: me.ips.joined(separator: "\n"))
                                .multilineTextAlignment(.trailing)
                                .textSelectionIfAvailable()
                        }
                    }
                }
                if !status.magicDnsSuffix.isEmpty {
                    row("MagicDNS") { Text(verbatim: status.magicDnsSuffix) }
                }
                row("Node Traffic") {
                    if let proxy = status.dialerProxy, !proxy.isEmpty {
                        Text("Through \(proxy)")
                    } else {
                        Text("Direct")
                    }
                }
                if let url = status.authUrl, let link = URL(string: url) {
                    Link(destination: link) {
                        Label("Log In", systemImage: ClashSymbol.key.rawValue)
                    }
                }
                ForEach(status.health ?? [], id: \.self) { warning in
                    Label {
                        Text(verbatim: warning).font(.footnote)
                    } icon: {
                        Image(systemName: ClashSymbol.exclamationmarkTriangle.rawValue)
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                HStack {
                    Text("Loading…").foregroundStyle(.secondary)
                    Spacer()
                    ProgressView()
                }
            }
        } header: {
            Text("Status")
        }
    }

    private func exitNodeSection(_ error: String) -> some View {
        Section {
            Label {
                Text(verbatim: error)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("tailscale.exit-node.error")
            } icon: {
                Image(systemName: ClashSymbol.exclamationmarkOctagon.rawValue)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Exit Node")
        } footer: {
            Text("The exit node in the profile could not be set. Check that it is online and offered as an exit node.")
        }
    }

    @ViewBuilder
    private var derpSection: some View {
        if let status, status.started {
            Section {
                let routes = status.derpRoutes ?? [:]
                if routes.isEmpty {
                    Text("No DERP relay used yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(routes.keys.sorted(), id: \.self) { region in
                        let viaProxy = routes[region] == "proxy"
                        row(verbatim: region) {
                            Text(viaProxy ? LocalizedStringKey("Through proxy") : LocalizedStringKey("Direct"))
                                .foregroundStyle(viaProxy ? Color.orange : .green)
                        }
                    }
                }
            } header: {
                Text("DERP Relays")
            } footer: {
                Text("How this device reaches each relay: directly, or through the node's dialer proxy.")
            }
        }
    }

    @ViewBuilder
    private func peersSection(_ node: ClashTailscaleNode) -> some View {
        if let status, status.started {
            Section {
                if status.peers.isEmpty {
                    Text("No peers yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(status.peers) { peer in
                        peerRow(peer, node: node)
                    }
                }
            } header: {
                HStack {
                    Text("Peers")
                    Spacer()
                    if !status.peers.isEmpty {
                        Button("Ping All") {
                            Task { await ping(status.peers, node: node) }
                        }
                        .font(.footnote)
                        .disabled(!pinging.isEmpty)
                        .accessibilityIdentifier("tailscale.peers.ping-all")
                    }
                }
            } footer: {
                Text("Ping shows whether a peer is reached directly or through a relay, and how long it takes.")
            }
        }
    }

    private func peerRow(_ peer: ClashTailscalePeer, node: ClashTailscaleNode) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(peer.online ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .accessibilityLabel(Text(peer.online ? LocalizedStringKey("Online") : LocalizedStringKey("Offline")))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: peer.displayName)
                    if peer.exitNode {
                        Text("Exit Node")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                }
                Text(verbatim: Self.peerDetail(peer))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let target = peer.ips.first, let result = pings[target] {
                    pingResult(result)
                }
            }
            Spacer()
            if let target = peer.ips.first {
                if pinging.contains(target) {
                    ProgressView()
                } else {
                    Button("Ping") {
                        Task { await ping([peer], node: node) }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("tailscale.peer.ping.\(peer.displayName)")
                }
            }
        }
    }

    @ViewBuilder
    private func pingResult(_ result: ClashTailscalePing) -> some View {
        if result.succeeded {
            Group {
                switch result.path {
                case .direct:
                    Text("Direct · \(result.latencyMs) ms").foregroundStyle(.green)
                case let .derp(region):
                    Text("Relay \(region) · \(result.latencyMs) ms").foregroundStyle(.orange)
                case .peerRelay:
                    Text("Peer relay · \(result.latencyMs) ms").foregroundStyle(.orange)
                case .unknown:
                    Text(verbatim: "\(result.latencyMs) ms")
                }
            }
            .font(.footnote.weight(.medium))
        } else {
            Text(LocalizedStringKey(result.error ?? "Failed"))
                .font(.footnote)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private func actionsSection(_ node: ClashTailscaleNode) -> some View {
        Section {
            Button {
                Task { await perform(node, capabilities.reconnect, reloadsAfter: false) }
            } label: {
                HStack {
                    Label(
                        status?.started == false ? LocalizedStringKey("Start Node") : LocalizedStringKey("Reconnect"),
                        systemImage: ClashSymbol.arrowClockwise.rawValue
                    )
                    if isActing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isActing)
            .accessibilityIdentifier("tailscale.reconnect")

            Button(role: .destructive) {
                confirmsReset = true
            } label: {
                Label {
                    Text("Reset Login…")
                } icon: {
                    Image(systemName: ClashSymbol.trash.rawValue)
                }
                .foregroundStyle(.red)
            }
            .disabled(isActing)
            .accessibilityIdentifier("tailscale.reset")

            if let actionMessage {
                Text(LocalizedStringKey(actionMessage))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("tailscale.action.result")
            }
        } header: {
            Text("Actions")
        } footer: {
            Text("Reconnect retries the login now when the node is stuck logged out; the saved login is kept.")
        }
    }

    private func row<Value: View>(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 16)
            value().foregroundStyle(.secondary)
        }
    }

    private func row<Value: View>(verbatim title: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: title)
            Spacer(minLength: 16)
            value()
        }
    }

    static func peerDetail(_ peer: ClashTailscalePeer) -> String {
        var parts: [String] = []
        if let address = peer.ips.first { parts.append(address) }
        if !peer.os.isEmpty { parts.append(peer.os) }
        return parts.joined(separator: " · ")
    }

    static func stateTitle(_ status: ClashTailscaleStatus) -> LocalizedStringKey {
        guard status.started else { return "Not started" }
        switch status.backendState {
        case "Running": return "Connected"
        case "NeedsLogin": return "Needs login"
        case "NeedsMachineAuth": return "Waiting for approval"
        case "Starting": return "Starting"
        case "Stopped": return "Stopped"
        case "NoState", "": return "Not started"
        default: return LocalizedStringKey(status.backendState)
        }
    }

    // MARK: Loading

    private func reload() async {
        guard isConnected else {
            nodes = []
            status = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        let list = await capabilities.nodes()
        nodes = list.nodes
        nodesError = list.error
        if let selectedNodeID, !nodes.contains(where: { $0.id == selectedNodeID }) {
            self.selectedNodeID = nil
        }
        await loadStatus(start: false)
    }

    private func loadStatus(start: Bool) async {
        guard let node = selectedNode else {
            status = nil
            return
        }
        let name = node.name
        let result = await capabilities.status(name, start)
        guard selectedNode?.name == name else { return }
        status = result
        let known = Set(result.peers.flatMap(\.ips))
        pings = pings.filter { known.contains($0.key) }
    }

    private func ping(_ peers: [ClashTailscalePeer], node: ClashTailscaleNode) async {
        let targets = peers.compactMap(\.ips.first).filter { !pinging.contains($0) }
        guard !targets.isEmpty else { return }
        pinging.formUnion(targets)
        defer { pinging.subtract(targets) }
        for result in await capabilities.ping(node.name, targets) {
            pings[result.target] = result
        }
    }

    private func perform(
        _ node: ClashTailscaleNode,
        _ action: ClashTailscaleCapabilities.Action,
        reloadsAfter: Bool
    ) async {
        isActing = true
        defer { isActing = false }
        actionMessage = nil
        if !reloadsAfter, status?.started == false {
            // Start rather than reconnect a node no traffic has started yet.
            status = await capabilities.status(node.name, true)
            await reload()
            return
        }
        if let error = await action(node.name) {
            actionMessage = error
        } else if reloadsAfter {
            actionMessage = "The login was reset and the profile reloaded."
            pings = [:]
        }
        await reload()
    }
}

private extension View {
    @ViewBuilder
    func textSelectionIfAvailable() -> some View {
        #if os(tvOS)
        self
        #else
        textSelection(.enabled)
        #endif
    }
}
