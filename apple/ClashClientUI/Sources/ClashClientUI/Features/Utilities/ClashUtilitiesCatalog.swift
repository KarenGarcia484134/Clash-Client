public enum ClashUtilitiesSectionID: String, CaseIterable, Hashable, Sendable {
    case currentSession
    case networkTools
    case runtimeAndReports

    public var title: String {
        switch self {
        case .currentSession: "Current Session"
        case .networkTools: "Network Tools"
        case .runtimeAndReports: "Runtime & Reports"
        }
    }
}

public enum ClashUtilitiesDestination:
    String,
    CaseIterable,
    Codable,
    Hashable,
    Identifiable,
    Sendable
{
    case root
     
     
     
     
    case activity
    case connections
    case requests
    case logs
    case networkQuality
    case stun
     
     
     
    case dnsQuery
    case proxyShare
    case tailscale
    case runtime
    case providers
    case diagnosticsInbox

    public var id: Self { self }

    public var title: String {
        switch self {
        case .root: "Utilities"
        case .activity: "Activity"
        case .connections: "Connections"
        case .requests: "Requests"
        case .logs: "Logs"
        case .networkQuality: "Network Quality"
        case .stun: "STUN & NAT"
        case .dnsQuery: "DNS Query"
        case .proxyShare: "LAN Proxy Share"
        case .tailscale: "Tailscale"
        case .runtime: "Core Runtime"
        case .providers: "Providers"
        case .diagnosticsInbox: "Diagnostics Inbox"
        }
    }

    public var symbol: ClashSymbol {
        switch self {
        case .root: .wrenchAndScrewdriver
        case .activity: .waveformPathEcg
        case .connections: .listTriangle
        case .requests: .listBulletRectanglePortrait
        case .logs: .textAlignleft
        case .networkQuality: .speedometer
        case .stun: .arrowTriangleSwap
        case .dnsQuery: .magnifyingglass
        case .proxyShare: .network
        case .tailscale: .point3ConnectedTrianglepathDotted
        case .runtime: .cpu
        case .providers: .shippingbox
        case .diagnosticsInbox: .docTextMagnifyingglass
        }
    }

    public var accent: ClashAccentRole {
        switch self {
        case .root: .blue
        case .activity: .cyan
        case .connections: .cyan
        case .requests: .pink
        case .logs: .purple
        case .networkQuality: .orange
        case .stun: .green
        case .dnsQuery: .teal
        case .proxyShare: .orange
        case .tailscale: .teal
        case .runtime: .indigo
        case .providers: .orange
        case .diagnosticsInbox: .purple
        }
    }
}

public struct ClashUtilitiesSectionDescriptor: Equatable, Sendable {
    public let id: ClashUtilitiesSectionID
    public let destinations: [ClashUtilitiesDestination]

    public init(
        id: ClashUtilitiesSectionID,
        destinations: [ClashUtilitiesDestination]
    ) {
        self.id = id
        self.destinations = destinations
    }
}

public enum ClashUtilitiesCatalog {
     
     
     
    public static let regularHubExcludes: Set<ClashUtilitiesDestination> = [
        .activity,
    ]

    public static let sections = [
        ClashUtilitiesSectionDescriptor(
            id: .currentSession,
            destinations: [.activity]
        ),
        ClashUtilitiesSectionDescriptor(
            id: .networkTools,
            destinations: [.networkQuality, .stun, .dnsQuery, .proxyShare, .tailscale]
        ),
        ClashUtilitiesSectionDescriptor(
            id: .runtimeAndReports,
            destinations: [.runtime, .providers, .diagnosticsInbox]
        ),
    ]
}
