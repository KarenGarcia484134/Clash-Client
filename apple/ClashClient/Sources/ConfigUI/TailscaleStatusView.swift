import SwiftUI
import ClashClientUI

/// The app side of the Tailscale page: every capability is a
/// `{"cmd":"tailscale"}` message the VPN extension forwards to the kernel.
struct TailscaleStatusView: View {
    @ObservedObject var command: ClashCommandClient

    var body: some View {
        ClashTailscaleView(
            isConnected: command.isConnected,
            capabilities: ClashTailscaleCapabilities(
                nodes: {
                    ClashTailscaleDecoding.nodes(
                        await command.sendTailscale(["action": "nodes"], timeoutSeconds: 10)
                    )
                },
                status: { node, start in
                    ClashTailscaleDecoding.status(
                        await command.sendTailscale([
                            "action": "status",
                            "name": node,
                            "start": start,
                            "wait": start,
                        ])
                    )
                },
                ping: { node, targets in
                    ClashTailscaleDecoding.pings(
                        await command.sendTailscale([
                            "action": "ping",
                            "name": node,
                            "targets": targets,
                        ]),
                        targets: targets
                    )
                },
                reconnect: { node in
                    ClashTailscaleDecoding.actionError(
                        await command.sendTailscale(["action": "reconnect", "name": node])
                    )
                },
                resetLogin: { node in
                    // FlClash resets in two steps, and so does this: the
                    // kernel closes the node, forgets it and deletes its
                    // saved login, then the profile reloads, which starts
                    // a fresh node that logs in again.
                    let reset = ClashTailscaleDecoding.status(
                        await command.sendTailscale([
                            "action": "status",
                            "name": node,
                            "reset": true,
                        ])
                    )
                    if let error = reset.error, !error.isEmpty { return error }
                    if let refusal = await command.requestProviderReload() { return refusal }
                    // The reload runs after the extension has answered.
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    return nil
                }
            )
        )
    }
}
