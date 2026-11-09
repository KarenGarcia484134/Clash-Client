import Foundation
import ClashClientUI
import ClashMacClient

 
 
 
 
 
 
 
struct ClashMacSystemRoutePlan: Equatable {
     
    var destination: ClashMacSecondaryDestination?
    var command: ClashSystemVPNPolicy.Command?
    var mode: AppleClientOutboundMode?

    static func plan(
        for route: ClashSystemRoute,
        isActive: Bool
    ) -> ClashMacSystemRoutePlan {
        switch route {
        case .vpn(let action):
            return ClashMacSystemRoutePlan(
                destination: nil,
                command: ClashSystemVPNPolicy.command(for: action, isActive: isActive),
                mode: nil
            )
        case .mode(let mode):
            let outbound: AppleClientOutboundMode
            switch mode {
            case .rule: outbound = .rule
            case .global: outbound = .global
            case .direct: outbound = .direct
            }
            return ClashMacSystemRoutePlan(destination: nil, command: nil, mode: outbound)
        case .open(let destination):
            let secondary: ClashMacSecondaryDestination?
            switch destination {
            case .overview, .home: secondary = nil
            case .profiles: secondary = .profiles
            case .nodes, .proxies: secondary = .proxies
            case .logs: secondary = .utility(.logs)
            case .tools, .utilities: secondary = .utility(.root)
            case .more: secondary = .more(.root)
            case .tailscale: secondary = .utility(.tailscale)
            }
            return ClashMacSystemRoutePlan(destination: secondary, command: nil, mode: nil)
        }
    }
}
