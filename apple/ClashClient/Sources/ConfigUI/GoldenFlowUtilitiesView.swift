import SwiftUI
import ClashClientUI

 
 
 
 
 
struct GoldenFlowUtilitiesAdapter: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.clashShellLayout) private var shellLayout
     
     
     
     
     
    @Environment(\.locale) private var locale

    @ObservedObject var vpn: VPNController
    @ObservedObject var command: ClashCommandClient
    @ObservedObject var connections: ConnectionsModel
    @ObservedObject var networkQuality: NetworkQualityModel
    @ObservedObject var stun: STUNTestModel
    @ObservedObject var proxyShare: ProxyShareModel
    @Binding var destination:
        AppNavigationDestination.UtilitiesDestination
     
     
     
     
    @Binding var activityLens: ClashActivityLens
    var ownsNavigationContainer = true


    var body: some View {
        Group {
            if ownsNavigationContainer {
                ClashFeatureNavigationContainer {
                    sharedRoot
                        .clashPageTitle("Utilities")
                }
                .clashStackNavigationViewStyle()
            } else {
                sharedRoot
            }
        }
        .environment(
            \.clashUsesRegularDetailLayout,
            !ownsNavigationContainer
        )
    }

    private var sharedRoot: some View {
        ClashClientUI.ClashUtilitiesView(
            snapshot: sharedSnapshot,
            destination: $destination,
            presentationClass:
                shellLayout == .regularSidebar
                    ? .regularTouch
                    : .compactTouch,
            palette: productPalette,
             
             
             
            omitting: shellLayout == .regularSidebar
                ? ClashUtilitiesCatalog.regularHubExcludes
                : [],
            icon: { symbol in
                ClashSymbolImage(symbol: symbol)
            },
            destinationContent: { item in
                GoldenFlowUtilitiesDestinationAdapter(
                    vpn: vpn,
                    command: command,
                    connections: connections,
                    networkQuality: networkQuality,
                    stun: stun,
                    proxyShare: proxyShare,
                    destination: item,
                    activityLens: $activityLens,
                    usesRegularDetailLayout:
                        !ownsNavigationContainer
                )
            }
        )
    }

    private var productPalette: ClashClientUI.ClashProductPalette {
        ClashClientUI.ClashProductPalette.clashProduct
    }

    private var sharedSnapshot: AppleClientSnapshot {
        AppleClientSnapshot(
            revision: 0,
            connection: AppleClientConnectionSnapshot(
                phase: command.isConnected
                    ? .connected
                    : .disconnected
            ),
            utilities: ClashUtilitiesSnapshot(
                nativeAPIConnected: command.isConnected,
                activeConnectionCount:
                    connections.activeConnectionCount,
                requestCount: connections.requestLog.count,
                logCount: command.logs.count,
                isRecordingLogs: ClashLogSettings.isRecording(
                    from: GlobalConfig.appGroupDefaults
                ),
                logRetentionTitle: ClashCopy.string(
                    ClashLogSettings.retention(
                        from: GlobalConfig.appGroupDefaults
                    ).title,
                    locale: locale
                ),
                providerCount: nil,
                networkQualitySummary: networkQuality.summary,
                stunSummary: stun.summary,
                proxyShareStatus: proxyShare.phase.title,
                proxyShareEnabled: proxyShare.status.enabled
            )
        )
    }

}

 
 
 
 
 
struct GoldenFlowUtilitiesDestinationAdapter: View {
    @ObservedObject var vpn: VPNController
    @ObservedObject var command: ClashCommandClient
    @ObservedObject var connections: ConnectionsModel
    @ObservedObject var networkQuality: NetworkQualityModel
    @ObservedObject var stun: STUNTestModel
    @ObservedObject var proxyShare: ProxyShareModel
    let destination:
        AppNavigationDestination.UtilitiesDestination
    @Binding var activityLens: ClashActivityLens
    var usesRegularDetailLayout: Bool
     
     
     
     
    var loadsPersistedLogs = !false

    var body: some View {
         
         
        pageBody
            .clashPageTitle(.copy(destination.title))
    }

    @ViewBuilder
    private var pageBody: some View {
        Group {
            switch destination {
            case .root:
                EmptyView()
             
             
             
             
            case .activity, .connections, .requests, .logs:
                 
                 
                 
                ActivityView(
                    command: command,
                    connections: connections,
                    lens: $activityLens,
                    loadsPersistedLogs: loadsPersistedLogs
                )
                .equatable()
                .task(id: destination) {
                    guard
                        let requested = ClashActivityLens(
                            destination: destination
                        )
                    else { return }
                    activityLens = requested
                }
            case .networkQuality:
                NetworkQualityView(model: networkQuality)
            case .stun:
                STUNTestView(model: stun)
            case .dnsQuery:
                DNSQueryView(command: command)
            case .proxyShare:
#if os(macOS)
                 
                 
                 
                ProxyShareView(model: proxyShare).equatable()
#else
                ProxyShareView(model: proxyShare)
#endif
            case .tailscale:
                TailscaleStatusView(command: command)
            case .runtime:
                RuntimeDetailView(
                    command: command,
                    usesRegularDetailLayout:
                        usesRegularDetailLayout,
                    restart: { Task { await vpn.forceRestart() } }
                )
            case .providers:
                 
                 
                 
                 
                 
                 
                ProvidersView(vpn: vpn, command: command)
            case .diagnosticsInbox:
                MetricKitInboxView()
            }
        }
        .environment(
            \.clashUsesRegularDetailLayout,
            usesRegularDetailLayout
        )
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct LogsDestinationView: View {
     
     
     
     
     
     
     
    let command: ClashCommandClient
    let loadsPersistedLogs: Bool
     
    var query = ""
     
    var isShown = true
    @State private var survived: [String] = []
    @State private var liveLogs: [String] = []
    @State private var isConnected = false
     
     
     
    @State private var recording = ClashLogSettings.isRecording(
        from: GlobalConfig.appGroupDefaults
    )

    var body: some View {
        LogsContent(
            lines: recording ? survived + liveLogs : survived,
            isConnected: isConnected,
            clear: {
                command.clearLogs()
                 
                 
                 
                 
                 
                 
                survived = []
            },
            command: command,
            query: query,
            isShown: isShown
        )
         
         
        .onReceive(command.$logs) { liveLogs = $0 }
        .onReceive(command.$isConnected) { isConnected = $0 }
        .onReceive(NotificationCenter.default.publisher(for: ClashLogSettings.recordingDidChange)) { _ in
            recording = ClashLogSettings.isRecording(from: GlobalConfig.appGroupDefaults)
        }
        .task {
            guard loadsPersistedLogs else {
                survived = []
                return
            }
            survived = await Task.detached(priority: .userInitiated) {
                ClashLogStore.shared.mergedTail()
            }.value
        }
    }
}


