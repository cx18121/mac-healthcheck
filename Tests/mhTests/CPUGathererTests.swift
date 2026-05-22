import Testing
import Foundation
@testable import mh

@Suite("CPUGatherer (shallow)")
struct CPUGathererShallowTests {

    private func fixturedRunner(_ name: String) -> FakeProcessRunner {
        let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures")!
        let text = try! String(contentsOf: url, encoding: .utf8)
        return FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(path: "/usr/bin/top",
                                  args: ["-l", "1", "-n", "5",
                                         "-stats", "pid,cpu,mem,command"]):
                .init(stdout: text, stderr: "", exitCode: 0)
        ])
    }

    @Test("parses load average and top processes from real top output")
    func parsesTopOutput() async throws {
        let runner = fixturedRunner("top_runaway_slack")
        let result = await CPUGatherer.shallow(runner: runner)
        guard case .value(let cpu) = result else {
            Issue.record("expected .value, got \(result)"); return
        }
        #expect(cpu.loadAverage.oneMin == 4.21)
        #expect(cpu.loadAverage.fiveMin == 3.85)
        #expect(cpu.loadAverage.fifteenMin == 3.40)
        #expect(cpu.topProcesses.count == 5)
        #expect(cpu.topProcesses.first?.pid == 12345)
        #expect(cpu.topProcesses.first?.cpuPercent == 380.0)
        #expect(cpu.topProcesses.first?.command == "Slack Helper (Renderer)")
    }

    @Test("returns .timedOut on subprocess timeout")
    func handlesTimeout() async throws {
        struct AlwaysTimesOutRunner: ProcessRunner {
            func run(executableURL: URL, arguments: [String], stdin: String?,
                     timeout: TimeInterval) async throws -> ProcessResult {
                throw ProcessRunnerError.timedOut
            }
        }
        let result = await CPUGatherer.shallow(runner: AlwaysTimesOutRunner())
        guard case .timedOut = result else {
            Issue.record("expected .timedOut, got \(result)"); return
        }
    }

    @Test("returns .failed on non-zero exit")
    func handlesNonZeroExit() async throws {
        let runner = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(path: "/usr/bin/top",
                                  args: ["-l", "1", "-n", "5",
                                         "-stats", "pid,cpu,mem,command"]):
                .init(stdout: "", stderr: "top: unknown option", exitCode: 1)
        ])
        let result = await CPUGatherer.shallow(runner: runner)
        guard case .failed = result else {
            Issue.record("expected .failed, got \(result)"); return
        }
    }

    @Test("returns .failed when binary spawn fails")
    func handlesSpawnFailed() async throws {
        // FakeProcessRunner with no scripted entries throws .spawnFailed for any call
        let result = await CPUGatherer.shallow(runner: FakeProcessRunner(scripted: [:]))
        guard case .failed = result else {
            Issue.record("expected .failed, got \(result)"); return
        }
    }
}
