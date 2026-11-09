import Foundation

public struct ClashUtilitiesSnapshot: Codable, Equatable, Sendable {
    public let nativeAPIConnected: Bool
    public let activeConnectionCount: Int
    public let requestCount: Int
    public let logCount: Int
     
     
     
     
    public let isRecordingLogs: Bool
    public let logRetentionTitle: String?
    public let providerCount: Int?
    public let networkQualitySummary: String
    public let stunSummary: String
    public let proxyShareStatus: String
    public let proxyShareEnabled: Bool

    public init(
        nativeAPIConnected: Bool = false,
        activeConnectionCount: Int = 0,
        requestCount: Int = 0,
        logCount: Int = 0,
        isRecordingLogs: Bool = false,
        logRetentionTitle: String? = nil,
        providerCount: Int? = nil,
        networkQualitySummary: String =
            "Upload, download, and responsiveness",
        stunSummary: String =
            "UDP reachability and NAT behavior",
        proxyShareStatus: String = "Off",
        proxyShareEnabled: Bool = false
    ) {
        self.nativeAPIConnected = nativeAPIConnected
        self.activeConnectionCount = max(0, activeConnectionCount)
        self.requestCount = max(0, requestCount)
        self.logCount = max(0, logCount)
        self.isRecordingLogs = isRecordingLogs
        self.logRetentionTitle = logRetentionTitle.map(Self.bounded)
        self.providerCount = providerCount.map { max(0, $0) }
        self.networkQualitySummary = Self.bounded(networkQualitySummary)
        self.stunSummary = Self.bounded(stunSummary)
        self.proxyShareStatus = Self.bounded(proxyShareStatus)
        self.proxyShareEnabled = proxyShareEnabled
    }

    public func presentation(
        for destination: ClashUtilitiesDestination
    ) -> ClashProductDestinationPresentation {
        let liveBadge: ClashDisplayText =
            nativeAPIConnected ? "Live" : "Offline"
        switch destination {
        case .root:
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle: "Session details, network tests, and local reports"
            )
        case .activity:
             
             
             
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle: nativeAPIConnected
                    ? count(
                        activeConnectionCount,
                        singular: "%@ active session",
                        plural: "%@ active sessions"
                    )
                    : "Live sessions, requests, and logs",
                badge: liveBadge
            )
        case .connections:
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle: nativeAPIConnected
                    ? count(
                        activeConnectionCount,
                        singular: "%@ active session",
                        plural: "%@ active sessions"
                    )
                    : "Live sessions and their routes",
                badge: liveBadge
            )
        case .requests:
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle: nativeAPIConnected
                    ? count(
                        requestCount,
                        singular: "%@ request in this session",
                        plural: "%@ requests in this session"
                    )
                    : "Recent requests, kept after disconnect",
                badge: liveBadge
            )
        case .logs:
             
             
             
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle: isRecordingLogs
                    ? logRetentionTitle.map {
                         
                         
                         
                        ClashDisplayText.format("Recording · keeping %@", [$0])
                    } ?? "Recording"
                    : "Not recording · earlier logs kept",
                badge: liveBadge
            )
        case .networkQuality:
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle: diagnosticSummary(
                    networkQualitySummary,
                    fallback:
                        "Upload, download, and responsiveness"
                ),
                badge: liveBadge
            )
        case .stun:
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle: diagnosticSummary(
                    stunSummary,
                    fallback:
                        "UDP reachability and NAT behavior"
                ),
                badge: liveBadge
            )
        case .dnsQuery:
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle: "Look up a name and clear the DNS cache",
                badge: liveBadge
            )
        case .proxyShare:
            let badge: ClashDisplayText? =
                proxyShareEnabled || proxyShareStatus != "Off"
                    ? .copy(proxyShareStatus)
                    : nil
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle: "LAN HTTP and SOCKS proxy",
                badge: badge
            )
        case .tailscale:
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle: "Tailnet nodes, peers, and relay paths",
                badge: liveBadge
            )
        case .runtime:
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle: "Routes, memory pressure, and core health",
                badge: liveBadge
            )
        case .providers:
            let subtitle: ClashDisplayText = providerCount.map {
                count(
                    $0,
                    singular: "%@ active proxy and rule source",
                    plural: "%@ active proxy and rule sources"
                )
            } ?? "Runtime health for this profile’s proxy sources and rule sets"
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle: subtitle,
                badge: liveBadge
            )
        case .diagnosticsInbox:
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle:
                    "Crash, hang, CPU, disk, and energy reports"
            )
        }
    }

    public static let empty = ClashUtilitiesSnapshot()

    private static func bounded(_ value: String) -> String {
        String(value.prefix(256))
    }

     
     
     
     
     
     
     
     
     
     
     
    private func count(
        _ value: Int,
        singular: String,
        plural: String
    ) -> ClashDisplayText {
        .format(value == 1 ? singular : plural, ["\(value)"])
    }

     
     
     
     
     
     
    private func diagnosticSummary(
        _ value: String,
        fallback: ClashDisplayText
    ) -> ClashDisplayText {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
         
         
         
         
         
         
        return trimmed.isEmpty || trimmed == "—" ? fallback : .copy(trimmed)
    }
}
