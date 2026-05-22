import Testing
import Foundation
@testable import mh

@Suite("WifiGatherer (shallow)")
struct WifiGathererShallowTests {

    private func fixture(_ name: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures")!
        return try! String(contentsOf: url, encoding: .utf8)
    }

    @Test("parses airport -I + networksetup output")
    func parsesAirportOutput() async throws {
        let runner = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(
                path: "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport",
                args: ["-I"]
            ): .init(stdout: fixture("airport_I_normal"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(
                path: "/usr/sbin/networksetup",
                args: ["-getairportnetwork", "en0"]
            ): .init(stdout: fixture("networksetup_getairportnetwork"), stderr: "", exitCode: 0)
        ])
        let result = await WifiGatherer.shallow(runner: runner, interface: "en0")
        guard case .value(let wifi) = result else {
            Issue.record("expected .value, got \(result)"); return
        }
        #expect(wifi.ssid == "HomeNetwork")
        #expect(wifi.rssi == -45)
        #expect(wifi.channel == 36)
        #expect(wifi.linkRateMbps == 866)
        #expect(wifi.interface == "en0")
    }

    @Test("returns .unavailable when airport binary missing")
    func airportMissing() async throws {
        struct UnavailableRunner: ProcessRunner {
            func run(executableURL: URL, arguments: [String], stdin: String?,
                     timeout: TimeInterval) async throws -> ProcessResult {
                throw ProcessRunnerError.spawnFailed("no such file")
            }
        }
        let result = await WifiGatherer.shallow(runner: UnavailableRunner(), interface: "en0")
        guard case .unavailable = result else {
            Issue.record("expected .unavailable, got \(result)"); return
        }
    }
}
