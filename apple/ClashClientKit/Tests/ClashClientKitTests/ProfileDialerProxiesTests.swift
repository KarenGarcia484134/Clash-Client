import XCTest
@testable import ClashClientKit

final class ProfileDialerProxiesTests: XCTestCase {
    private func root() -> [String: Any] {
        [
            "proxies": [
                ["name": "HK", "type": "ss"],
                ["name": "JP", "type": "vmess", "dialer-proxy": "HK"],
                ["name": "US", "type": "trojan"],
                ["name": "Relay", "type": "socks5"],
            ] as [Any],
            "proxy-groups": [
                ["name": "Auto", "type": "url-test", "proxies": ["HK", "US"]],
                ["name": "Select", "type": "select", "proxies": ["Auto", "Relay", "DIRECT"]],
                ["name": "Everything", "type": "select", "include-all": true],
            ] as [Any],
        ]
    }

    private func dialer(_ root: [String: Any], _ name: String) -> String? {
        ((root["proxies"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }
            .first { $0["name"] as? String == name }?["dialer-proxy"] as? String
    }

    func testInjectsIntoTheMatchingProxy() {
        var config = root()
        let report = ProfileDialerProxies.inject(into: &config, [.init(node: "US", target: "Relay")])
        XCTAssertEqual(report.applied, ["US": "Relay"])
        XCTAssertTrue(report.skipped.isEmpty)
        XCTAssertEqual(dialer(config, "US"), "Relay")
        XCTAssertEqual(dialer(config, "JP"), "HK")
        XCTAssertNil(dialer(config, "HK"))
    }

    func testAGroupCanBeTheTarget() {
        var config = root()
        ProfileDialerProxies.inject(into: &config, [.init(node: "Relay", target: "Auto")])
        XCTAssertEqual(dialer(config, "Relay"), "Auto")
    }

    func testReplacesAndDropsTheProfilesOwnDialer() {
        var config = root()
        ProfileDialerProxies.inject(into: &config, [.init(node: "JP", target: "US")])
        XCTAssertEqual(dialer(config, "JP"), "US")
        config = root()
        ProfileDialerProxies.inject(into: &config, [.init(node: "JP", target: ProfileDialerProxies.direct)])
        XCTAssertNil(dialer(config, "JP"))
    }

    func testSkipsMissingNodeAndTarget() {
        var config = root()
        let report = ProfileDialerProxies.inject(into: &config, [
            .init(node: "Gone", target: "HK"),
            .init(node: "US", target: "Vanished"),
            .init(node: "Relay", target: "HK"),
        ])
        XCTAssertEqual(report.skipped, ["Gone": .missingNode, "US": .missingTarget])
        XCTAssertEqual(report.applied, ["Relay": "HK"])
        XCTAssertNil(dialer(config, "US"))
        XCTAssertEqual(dialer(config, "Relay"), "HK")
    }

    func testSkipsCycles() {
        var config = root()
         
        var report = ProfileDialerProxies.inject(into: &config, [.init(node: "HK", target: "JP")])
        XCTAssertEqual(report.skipped, ["HK": .cycle])
        XCTAssertNil(dialer(config, "HK"))
         
        config = root()
        report = ProfileDialerProxies.inject(into: &config, [.init(node: "HK", target: "Select")])
        XCTAssertEqual(report.skipped, ["HK": .cycle])
         
        config = root()
        report = ProfileDialerProxies.inject(into: &config, [.init(node: "US", target: "Everything")])
        XCTAssertEqual(report.skipped, ["US": .cycle])
         
        config = root()
        report = ProfileDialerProxies.inject(into: &config, [
            .init(node: "US", target: "Relay"),
            .init(node: "Relay", target: "US"),
        ])
        XCTAssertEqual(report.applied, ["US": "Relay"])
        XCTAssertEqual(report.skipped, ["Relay": .cycle])
        XCTAssertNil(dialer(config, "Relay"))
    }

    func testSelfIsNotATarget() {
        var config = root()
        let report = ProfileDialerProxies.inject(into: &config, [.init(node: "US", target: "US")])
        XCTAssertEqual(report.skipped, ["US": .missingTarget])
    }

    func testProviderNodesAreNotInTheGraph() {
        var config = root()
        config["proxy-providers"] = ["sub": ["type": "http", "url": "https://example.com"]]
        let graph = ProfileDialerProxyGraph(root: config)
        XCTAssertFalse(graph.proxySet.contains("FromProvider"))
        XCTAssertEqual(ProfileDialerProxies.issue(graph, [.init(node: "FromProvider", target: "HK")], node: "FromProvider"),
                       .missingNode)
    }

    func testCandidatesLeaveOutSelfBuiltinsAndLoops() {
        let graph = ProfileDialerProxyGraph(root: root())
        let candidates = ProfileDialerProxies.candidates(graph, [], node: "HK")
        XCTAssertFalse(candidates.contains("HK"))
        XCTAssertFalse(candidates.contains("DIRECT"))
        XCTAssertFalse(candidates.contains("JP"))
        XCTAssertFalse(candidates.contains("Auto"))
        XCTAssertFalse(candidates.contains("Select"))
        XCTAssertFalse(candidates.contains("Everything"))
        XCTAssertEqual(candidates, ["US", "Relay"])
        XCTAssertEqual(ProfileDialerProxies.candidates(graph, [], node: "Relay"), ["Auto", "HK", "JP", "US"])
    }

    func testSettingEditsInPlace() {
        var settings = ProfileDialerProxies.setting([], target: "HK", for: "US")
        settings = ProfileDialerProxies.setting(settings, target: "Relay", for: "JP")
        settings = ProfileDialerProxies.setting(settings, target: "Auto", for: "US")
        XCTAssertEqual(settings, [.init(node: "US", target: "Auto"), .init(node: "JP", target: "Relay")])
        settings = ProfileDialerProxies.setting(settings, target: nil, for: "US")
        XCTAssertEqual(settings, [.init(node: "JP", target: "Relay")])
    }

    func testEmptySettingsLeaveTheConfigAlone() {
        var config = root()
        let report = ProfileDialerProxies.inject(into: &config, [])
        XCTAssertTrue(report.applied.isEmpty && report.skipped.isEmpty)
        XCTAssertEqual(dialer(config, "JP"), "HK")
    }

    func testCodableRoundTrip() throws {
        let settings = [ProfileDialerProxy(node: "US", target: "HK")]
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode([ProfileDialerProxy].self, from: data), settings)
    }
}
