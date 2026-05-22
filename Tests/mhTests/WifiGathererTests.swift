import Testing
import Foundation
@testable import mh

@Suite("WifiGatherer (shallow)")
struct WifiGathererShallowTests {

    private func fixture(_ name: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures")!
        return try! String(contentsOf: url, encoding: .utf8)
    }

    private static let goodCoreWLAN: WifiGatherer.CoreWLANReader = { _ in
        CoreWLANSnapshot(ssid: "HomeNetwork", rssi: -45, channel: 36, linkRateMbps: 866)
    }

    private static let emptyCoreWLAN: WifiGatherer.CoreWLANReader = { _ in
        CoreWLANSnapshot(ssid: nil, rssi: nil, channel: nil, linkRateMbps: nil)
    }

    @Test("combines CoreWLAN signal data with networksetup SSID")
    func combinesSources() async throws {
        let runner = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(
                path: "/usr/sbin/networksetup",
                args: ["-getairportnetwork", "en0"]
            ): .init(stdout: fixture("networksetup_getairportnetwork"), stderr: "", exitCode: 0)
        ])
        let result = await WifiGatherer.shallow(runner: runner, coreWLANReader: Self.goodCoreWLAN)
        guard case .value(let wifi) = result else {
            Issue.record("expected .value, got \(result)"); return
        }
        #expect(wifi.ssid == "HomeNetwork")
        #expect(wifi.rssi == -45)
        #expect(wifi.channel == 36)
        #expect(wifi.linkRateMbps == 866)
        #expect(wifi.interface == "en0")
    }

    @Test("degrades to networksetup SSID only when CoreWLAN has no data")
    func degradesWhenCoreWLANEmpty() async throws {
        let runner = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(
                path: "/usr/sbin/networksetup",
                args: ["-getairportnetwork", "en0"]
            ): .init(stdout: fixture("networksetup_getairportnetwork"), stderr: "", exitCode: 0)
        ])
        let result = await WifiGatherer.shallow(runner: runner, coreWLANReader: Self.emptyCoreWLAN)
        guard case .value(let wifi) = result else {
            Issue.record("expected .value, got \(result)"); return
        }
        #expect(wifi.ssid == "HomeNetwork")  // from networksetup
        #expect(wifi.rssi == nil)
        #expect(wifi.channel == nil)
        #expect(wifi.linkRateMbps == nil)
    }
}
