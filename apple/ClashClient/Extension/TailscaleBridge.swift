@preconcurrency import Clash
import Foundation

/// Forwards the app's `{"cmd":"tailscale"}` requests to the kernel's
/// tailscale exports. Every export takes and returns JSON text and reports
/// a failure as an `"error"` field, so the reply is the export's own text.
/// The exports can block for seconds (a status that waits for the node to
/// settle, a ping), so they run off the provider's message queue.
enum TailscaleBridge {
    static let capability = "tailscale-v1"

    static func respond(to request: [String: Any]) async -> Data {
        let action = request["action"] as? String ?? "status"
        let name = request["name"] as? String ?? ""
        let flags = ["start", "wait", "rebind", "reset"].reduce(into: [String: Bool]()) {
            $0[$1] = request[$1] as? Bool ?? false
        }
        let flag = { (key: String) in flags[key] ?? false }
        let targets = request["targets"] as? [String] ?? []
        let reply: String = await Task.detached(priority: .userInitiated) {
            switch action {
            case "nodes":
                return ClashTailscaleNodes()
            case "status":
                return ClashTailscaleStatus(json([
                    "name": name,
                    "start": flag("start"),
                    "wait": flag("wait"),
                    "rebind": flag("rebind"),
                    "reset": flag("reset"),
                ]))
            case "ping":
                return ClashTailscalePing(json(["name": name, "targets": targets]))
            case "derpRoutes":
                return ClashTailscaleDERPRoutes(name)
            case "reconnect":
                return ClashTailscaleReconnect(name)
            case "networkChanged":
                return ClashTailscaleNetworkChanged()
            default:
                return json(["error": "unknown tailscale action \(action)"])
            }
        }.value
        return Data(reply.utf8)
    }

    private static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Tells the kernel's tailscale nodes the network changed once the
/// physical path has stopped changing for a moment, so a Wi-Fi to cellular
/// handover, which can report several paths in a row, rebinds the nodes
/// once instead of once per report.
final class TailscaleNetworkChangeDebouncer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "clash.tailscale.network-change")
    private let delay: DispatchTimeInterval
    private let notify: @Sendable () -> Void
    private var pending: DispatchWorkItem?

    init(
        delay: DispatchTimeInterval = .milliseconds(1_500),
        notify: @escaping @Sendable () -> Void = { _ = ClashTailscaleNetworkChanged() }
    ) {
        self.delay = delay
        self.notify = notify
    }

    func schedule() {
        queue.async { [self] in
            pending?.cancel()
            let item = DispatchWorkItem { [notify] in notify() }
            pending = item
            queue.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    func cancel() {
        queue.async { [self] in
            pending?.cancel()
            pending = nil
        }
    }
}
