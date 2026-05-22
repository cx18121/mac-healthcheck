import Testing
import Foundation
@testable import mh

@Suite("BatteryGatherer (shallow)")
struct BatteryGathererShallowTests {

    private func fixture(_ name: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures")!
        return try! String(contentsOf: url, encoding: .utf8)
    }

    @Test("parses AC-powered, full-battery output")
    func parsesAcOutput() async throws {
        let runner = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(path: "/usr/bin/pmset", args: ["-g", "batt"]):
                .init(stdout: fixture("pmset_batt_ac"), stderr: "", exitCode: 0)
        ])
        let result = await BatteryGatherer.shallow(runner: runner)
        guard case .value(let bat) = result else {
            Issue.record("expected .value, got \(result)"); return
        }
        #expect(bat.percent == 100)
        #expect(bat.onAC == true)
        #expect(bat.charging == false)  // "charged", not actively charging
    }

    @Test("parses battery-powered, discharging output")
    func parsesDrainOutput() async throws {
        let runner = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(path: "/usr/bin/pmset", args: ["-g", "batt"]):
                .init(stdout: fixture("pmset_batt_drain"), stderr: "", exitCode: 0)
        ])
        let result = await BatteryGatherer.shallow(runner: runner)
        guard case .value(let bat) = result else {
            Issue.record("expected .value, got \(result)"); return
        }
        #expect(bat.percent == 67)
        #expect(bat.onAC == false)
        #expect(bat.timeRemainingMinutes == 4 * 60 + 12)
    }
}
