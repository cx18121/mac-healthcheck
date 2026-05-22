import Testing
import Foundation
@testable import mh

@Suite("ProcessRunner")
struct ProcessRunnerTests {
    @Test("FakeProcessRunner returns scripted result")
    func fakeReturnsScriptedResult() async throws {
        let fake = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(path: "/bin/echo", args: ["hello"]):
                .init(stdout: "hello\n", stderr: "", exitCode: 0)
        ])
        let result = try await fake.run(executableURL: URL(fileURLWithPath: "/bin/echo"),
                                         arguments: ["hello"],
                                         stdin: nil,
                                         timeout: 1.0)
        #expect(result.stdout == "hello\n")
        #expect(result.stderr == "")
        #expect(result.exitCode == 0)
    }

    @Test("FoundationProcessRunner runs /bin/echo")
    func foundationRunsEcho() async throws {
        let runner = FoundationProcessRunner()
        let result = try await runner.run(executableURL: URL(fileURLWithPath: "/bin/echo"),
                                           arguments: ["hello", "world"],
                                           stdin: nil,
                                           timeout: 5.0)
        #expect(result.stdout == "hello world\n")
        #expect(result.exitCode == 0)
    }

    @Test("FoundationProcessRunner enforces timeout")
    func foundationEnforcesTimeout() async throws {
        let runner = FoundationProcessRunner()
        do {
            _ = try await runner.run(executableURL: URL(fileURLWithPath: "/bin/sleep"),
                                      arguments: ["2"],
                                      stdin: nil,
                                      timeout: 0.1)
            Issue.record("expected timeout to throw")
        } catch ProcessRunnerError.timedOut {
            // expected
        }
    }
}
