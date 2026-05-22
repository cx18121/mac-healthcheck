import Testing
import Foundation
@testable import mh

@Suite("CPUGatherer (deep)")
struct CPUGathererDeepTests {

    private func fixture(_ name: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures")!
        return try! String(contentsOf: url, encoding: .utf8)
    }

    @Test("deep gathers extended top, thermal state, and uptime")
    func deepGatherer() async throws {
        let runner = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(path: "/usr/bin/top",
                                  args: ["-l", "1", "-n", "20", "-stats", "pid,cpu,mem,command"]):
                .init(stdout: fixture("top_runaway_slack"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/usr/bin/pmset", args: ["-g", "therm"]):
                .init(stdout: fixture("pmset_therm"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/usr/bin/uptime", args: []):
                .init(stdout: " 19:23  up 4 days, 12:34, 3 users, load averages: 1.2 1.1 1.0\n",
                       stderr: "", exitCode: 0)
        ])
        let result = await CPUGatherer.deep(runner: runner)
        guard case .value(let deep) = result else {
            Issue.record("expected .value, got \(result)"); return
        }
        #expect(deep.fullTopOutput.contains("Slack Helper"))
        #expect(deep.thermalPressure.contains("CPU_Speed_Limit"))
        #expect(deep.uptimeSeconds > 0)
    }
}
