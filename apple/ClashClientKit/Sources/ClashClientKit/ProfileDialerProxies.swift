import Foundation

 
 
 
 
 
public struct ProfileDialerProxy: Codable, Equatable, Hashable, Sendable {
    public var node: String
    public var target: String
    public init(node: String, target: String) { self.node = node; self.target = target }
}

public enum ProfileDialerProxyIssue: String, Codable, Equatable, Sendable {
    case missingNode
    case missingTarget
    case cycle
}

 
 
 
public struct ProfileDialerProxyGraph: Equatable, Sendable {
    public var proxies: [String] = []
    public var groups: [String] = []
    public var members: [String: [String]] = [:]
    public var existing: [String: String] = [:]

    public init(proxies: [String] = [], groups: [String] = [], members: [String: [String]] = [:],
                existing: [String: String] = [:]) {
        self.proxies = proxies; self.groups = groups; self.members = members; self.existing = existing
    }

     
     
     
     
    public init(root: [String: Any]) {
        var seen = Set<String>()
        for case let row as [String: Any] in (root["proxies"] as? [Any]) ?? [] {
            guard let name = row["name"] as? String, !name.isEmpty, seen.insert(name).inserted else { continue }
            proxies.append(name)
            if let via = row["dialer-proxy"] as? String, !via.isEmpty { existing[name] = via }
        }
        var includesAll: [String] = []
        for case let row as [String: Any] in (root["proxy-groups"] as? [Any]) ?? [] {
            guard let name = row["name"] as? String, !name.isEmpty, seen.insert(name).inserted else { continue }
            groups.append(name)
            members[name] = ((row["proxies"] as? [Any]) ?? []).compactMap { $0 as? String }
            if Self.flag(row["include-all"]) || Self.flag(row["include-all-proxies"]) { includesAll.append(name) }
        }
         
         
        for name in includesAll { members[name, default: []].append(contentsOf: proxies) }
    }

    private static func flag(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return value.lowercased() == "true" }
        return false
    }

    public var proxySet: Set<String> { Set(proxies) }

    public func hasTarget(_ name: String) -> Bool { proxies.contains(name) || members[name] != nil }
}

public enum ProfileDialerProxies {
     
     
    public static let direct = "DIRECT"

     
    public static let builtinPolicies: Set<String> = [
        "DIRECT", "REJECT", "REJECT-DROP", "PASS", "PASS-RULE", "COMPATIBLE", "GLOBAL",
    ]

    public static func setting(_ settings: [ProfileDialerProxy], for node: String) -> String? {
        settings.first { $0.node == node }?.target
    }

     
    public static func setting(_ settings: [ProfileDialerProxy], target: String?, for node: String) -> [ProfileDialerProxy] {
        var result = settings
        if let target {
            if let index = result.firstIndex(where: { $0.node == node }) {
                result[index].target = target
            } else {
                result.append(.init(node: node, target: target))
            }
        } else {
            result.removeAll { $0.node == node }
        }
        return result
    }

     
     
    public static func effective(_ graph: ProfileDialerProxyGraph, _ settings: [ProfileDialerProxy]) -> [String: String] {
        var result = graph.existing
        for entry in settings { result[entry.node] = entry.target }
        return result
    }

     
     
     
    public static func createsCycle(_ graph: ProfileDialerProxyGraph, dialers: [String: String],
                                    node: String, target: String) -> Bool {
        var visited = Set<String>()
        var pending = [target]
        while let name = pending.popLast() {
            if name == node { return true }
            guard visited.insert(name).inserted else { continue }
            if let members = graph.members[name] { pending.append(contentsOf: members) }
            if let via = dialers[name], via != direct { pending.append(via) }
        }
        return false
    }

    private static func others(_ graph: ProfileDialerProxyGraph, _ settings: [ProfileDialerProxy],
                               except node: String) -> [String: String] {
        var result = effective(graph, settings)
        result.removeValue(forKey: node)
        return result.filter { $0.value != direct }
    }

    public static func issue(_ graph: ProfileDialerProxyGraph, _ settings: [ProfileDialerProxy],
                             node: String) -> ProfileDialerProxyIssue? {
        guard let target = setting(settings, for: node) else { return nil }
        guard graph.proxySet.contains(node) else { return .missingNode }
        if target == direct { return nil }
        guard target != node, graph.hasTarget(target) else { return .missingTarget }
        if createsCycle(graph, dialers: others(graph, settings, except: node), node: node, target: target) {
            return .cycle
        }
        return nil
    }

     
     
     
    public static func issues(_ graph: ProfileDialerProxyGraph,
                              _ settings: [ProfileDialerProxy]) -> [String: ProfileDialerProxyIssue] {
        var applied: [ProfileDialerProxy] = []
        var skipped: [String: ProfileDialerProxyIssue] = [:]
        for entry in settings {
            if let issue = issue(graph, applied + [entry], node: entry.node) {
                skipped[entry.node] = issue
            } else {
                applied.append(entry)
            }
        }
        return skipped
    }

    public static func isCandidate(_ name: String, for node: String) -> Bool {
        name != node && !builtinPolicies.contains(name)
    }

     
     
    public static func candidates(_ graph: ProfileDialerProxyGraph, _ settings: [ProfileDialerProxy],
                                  node: String) -> [String] {
        let dialers = others(graph, settings, except: node)
        return (graph.groups + graph.proxies).filter {
            isCandidate($0, for: node) && !createsCycle(graph, dialers: dialers, node: node, target: $0)
        }
    }

    public struct Report: Equatable, Sendable {
        public var applied: [String: String] = [:]
        public var skipped: [String: ProfileDialerProxyIssue] = [:]
        public init() {}
    }

     
     
     
     
    @discardableResult
    public static func inject(into root: inout [String: Any], _ settings: [ProfileDialerProxy]) -> Report {
        var report = Report()
        guard !settings.isEmpty, let rows = root["proxies"] as? [Any] else {
            for entry in settings { report.skipped[entry.node] = .missingNode }
            return report
        }
        let graph = ProfileDialerProxyGraph(root: root)
        report.skipped = issues(graph, settings)
        for entry in settings where report.skipped[entry.node] == nil {
            report.applied[entry.node] = entry.target
        }
        guard !report.applied.isEmpty else { return report }
        root["proxies"] = rows.map { item -> Any in
            guard var row = item as? [String: Any], let name = row["name"] as? String,
                  let target = report.applied[name] else { return item }
            if target == direct {
                row.removeValue(forKey: "dialer-proxy")
            } else {
                row["dialer-proxy"] = target
            }
            return row
        }
        return report
    }
}
