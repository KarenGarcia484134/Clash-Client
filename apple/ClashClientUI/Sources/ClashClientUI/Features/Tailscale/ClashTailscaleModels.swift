import Foundation

// The shapes the kernel's tailscale exports return (the same JSON fields as
// FlClash's tailscale.status and tailscale.ping), decoded once here so the
// app and every platform's page read them the same way.

public struct ClashTailscaleNode: Codable, Hashable, Identifiable, Sendable {
    public let name: String
    /// The proxy provider the node came from; nil for one in `proxies`.
    public let provider: String?
    public let started: Bool

    public var id: String { "\(provider ?? "")\u{0}\(name)" }

    public init(name: String, provider: String? = nil, started: Bool) {
        self.name = name
        self.provider = provider
        self.started = started
    }
}

public struct ClashTailscaleNodeList: Codable, Sendable {
    public var nodes: [ClashTailscaleNode]
    public var error: String?

    public init(nodes: [ClashTailscaleNode] = [], error: String? = nil) {
        self.nodes = nodes
        self.error = error
    }
}

public struct ClashTailscalePeer: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let hostName: String
    public let dnsName: String
    public let os: String
    public let ips: [String]
    public let online: Bool
    public let exitNode: Bool
    public let exitNodeOption: Bool
    public let lastSeen: String?

    public init(
        id: String, hostName: String, dnsName: String = "", os: String = "",
        ips: [String] = [], online: Bool, exitNode: Bool = false,
        exitNodeOption: Bool = false, lastSeen: String? = nil
    ) {
        self.id = id
        self.hostName = hostName
        self.dnsName = dnsName
        self.os = os
        self.ips = ips
        self.online = online
        self.exitNode = exitNode
        self.exitNodeOption = exitNodeOption
        self.lastSeen = lastSeen
    }

    enum CodingKeys: String, CodingKey {
        case id, hostName, dnsName, os, ips, online, exitNode, exitNodeOption, lastSeen
    }

    // Every field is optional on the wire: Go writes a nil slice as null.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        hostName = try c.decodeIfPresent(String.self, forKey: .hostName) ?? ""
        dnsName = try c.decodeIfPresent(String.self, forKey: .dnsName) ?? ""
        os = try c.decodeIfPresent(String.self, forKey: .os) ?? ""
        ips = try c.decodeIfPresent([String].self, forKey: .ips) ?? []
        online = try c.decodeIfPresent(Bool.self, forKey: .online) ?? false
        exitNode = try c.decodeIfPresent(Bool.self, forKey: .exitNode) ?? false
        exitNodeOption = try c.decodeIfPresent(Bool.self, forKey: .exitNodeOption) ?? false
        lastSeen = try c.decodeIfPresent(String.self, forKey: .lastSeen)
    }

    /// The name to show: the MagicDNS label when the host name is empty.
    public var displayName: String {
        if !hostName.isEmpty { return hostName }
        return dnsName.split(separator: ".").first.map(String.init) ?? id
    }
}

public struct ClashTailscaleStatus: Codable, Sendable {
    public var started: Bool
    public var backendState: String
    public var authUrl: String?
    public var health: [String]?
    public var magicDnsSuffix: String
    /// This device, as the tailnet sees it (`self` in the JSON).
    public var selfPeer: ClashTailscalePeer?
    public var peers: [ClashTailscalePeer]
    public var error: String?
    /// What the node's own control, DERP and UDP traffic goes through;
    /// nil or empty means directly.
    public var dialerProxy: String?
    /// DERP region code to "direct" or "proxy".
    public var derpRoutes: [String: String]?
    public var exitNodeError: String?

    public init(
        started: Bool = false, backendState: String = "", authUrl: String? = nil,
        health: [String]? = nil, magicDnsSuffix: String = "", selfPeer: ClashTailscalePeer? = nil,
        peers: [ClashTailscalePeer] = [], error: String? = nil, dialerProxy: String? = nil,
        derpRoutes: [String: String]? = nil, exitNodeError: String? = nil
    ) {
        self.started = started
        self.backendState = backendState
        self.authUrl = authUrl
        self.health = health
        self.magicDnsSuffix = magicDnsSuffix
        self.selfPeer = selfPeer
        self.peers = peers
        self.error = error
        self.dialerProxy = dialerProxy
        self.derpRoutes = derpRoutes
        self.exitNodeError = exitNodeError
    }

    enum CodingKeys: String, CodingKey {
        case started, backendState, authUrl, health, magicDnsSuffix
        case selfPeer = "self"
        case peers, error, dialerProxy, derpRoutes, exitNodeError
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        started = try c.decodeIfPresent(Bool.self, forKey: .started) ?? false
        backendState = try c.decodeIfPresent(String.self, forKey: .backendState) ?? ""
        authUrl = try c.decodeIfPresent(String.self, forKey: .authUrl)
        health = try c.decodeIfPresent([String].self, forKey: .health)
        magicDnsSuffix = try c.decodeIfPresent(String.self, forKey: .magicDnsSuffix) ?? ""
        selfPeer = try c.decodeIfPresent(ClashTailscalePeer.self, forKey: .selfPeer)
        peers = try c.decodeIfPresent([ClashTailscalePeer].self, forKey: .peers) ?? []
        error = try c.decodeIfPresent(String.self, forKey: .error)
        dialerProxy = try c.decodeIfPresent(String.self, forKey: .dialerProxy)
        derpRoutes = try c.decodeIfPresent([String: String].self, forKey: .derpRoutes)
        exitNodeError = try c.decodeIfPresent(String.self, forKey: .exitNodeError)
    }

    /// A status that only carries an error, for a request that never got
    /// an answer.
    public static func failure(_ message: String) -> Self {
        Self(error: message)
    }
}

public struct ClashTailscalePing: Codable, Hashable, Sendable {
    public enum Path: Hashable, Sendable {
        case direct(endpoint: String)
        case derp(region: String)
        case peerRelay(String)
        case unknown
    }

    public let target: String
    /// -1 when the ping failed.
    public let latencyMs: Int
    public let endpoint: String?
    public let derpRegionId: Int?
    public let derpRegionCode: String?
    public let peerRelay: String?
    public let error: String?

    public init(
        target: String, latencyMs: Int, endpoint: String? = nil, derpRegionId: Int? = nil,
        derpRegionCode: String? = nil, peerRelay: String? = nil, error: String? = nil
    ) {
        self.target = target
        self.latencyMs = latencyMs
        self.endpoint = endpoint
        self.derpRegionId = derpRegionId
        self.derpRegionCode = derpRegionCode
        self.peerRelay = peerRelay
        self.error = error
    }

    public var succeeded: Bool { latencyMs >= 0 && (error ?? "").isEmpty }

    /// How the ping went: straight to the peer, through a DERP relay, or
    /// through a peer relay. A TSMP ping, the fallback when disco cannot
    /// get through, reports neither.
    public var path: Path {
        if let endpoint, !endpoint.isEmpty { return .direct(endpoint: endpoint) }
        if let peerRelay, !peerRelay.isEmpty { return .peerRelay(peerRelay) }
        if let derpRegionCode, !derpRegionCode.isEmpty { return .derp(region: derpRegionCode) }
        return .unknown
    }
}

public enum ClashTailscaleDecoding {
    public static func nodes(_ data: Data?) -> ClashTailscaleNodeList {
        guard let data else { return ClashTailscaleNodeList(error: "No answer from the VPN extension") }
        return (try? JSONDecoder().decode(ClashTailscaleNodeList.self, from: data))
            ?? ClashTailscaleNodeList(error: errorText(data) ?? "Unreadable answer")
    }

    public static func status(_ data: Data?) -> ClashTailscaleStatus {
        guard let data else { return .failure("No answer from the VPN extension") }
        return (try? JSONDecoder().decode(ClashTailscaleStatus.self, from: data))
            ?? .failure(errorText(data) ?? "Unreadable answer")
    }

    public static func pings(_ data: Data?, targets: [String]) -> [ClashTailscalePing] {
        if let data, let pings = try? JSONDecoder().decode([ClashTailscalePing].self, from: data) {
            return pings
        }
        let message = data.flatMap(errorText) ?? "No answer from the VPN extension"
        return targets.map { ClashTailscalePing(target: $0, latencyMs: -1, error: message) }
    }

    /// The `"error"` of an action's answer, or nil when it succeeded.
    public static func actionError(_ data: Data?) -> String? {
        guard let data else { return "No answer from the VPN extension" }
        return errorText(data)
    }

    private static func errorText(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["error"] as? String, !message.isEmpty
        else { return nil }
        return message
    }
}
