import Testing
import Foundation
@testable import mh

/// Local to this test file. The production `TriageResponse` is defined in Task 18 alongside
/// `AnalysisResponse`. At Task 11 time it doesn't exist yet, so the test names its decode
/// type distinctively to avoid future collisions.
struct FixtureTriageResponse: Codable, Equatable {
    let domain: String
    let reasoning: String
}

@Suite("CodexClient")
struct CodexClientTests {

    private func fixture(_ name: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures")!
        return try! String(contentsOf: url, encoding: .utf8)
    }

    @Test("openSession parses thread_id and structured response")
    func openSessionParses() async throws {
        let schema = FileManager.default.temporaryDirectory.appendingPathComponent("schema.json")
        try "{}".write(to: schema, atomically: true, encoding: .utf8)

        let runner = FakeProcessRunner(scripted: [
            // Matches the args CodexClient.openSession will use
            FakeProcessRunner.Key(path: "/opt/homebrew/bin/codex",
                                  args: ["exec", "--json", "--output-schema", schema.path, "-"]):
                .init(stdout: fixture("codex_triage_response"), stderr: "", exitCode: 0)
        ])
        let client = CodexClient(runner: runner, codexPath: "/opt/homebrew/bin/codex")
        let response: FixtureTriageResponse = try await client.openSession(
            prompt: "anything",
            schemaFile: schema,
            decoding: FixtureTriageResponse.self
        )
        #expect(response.domain == "cpu")
        #expect(response.reasoning.contains("Slack"))
        #expect(await client.threadId == "019e4db8-6142-7031-a4b2-189862c6546f")
    }

    @Test("openSession throws on error event")
    func openSessionThrowsOnError() async throws {
        let schema = FileManager.default.temporaryDirectory.appendingPathComponent("schema.json")
        try "{}".write(to: schema, atomically: true, encoding: .utf8)

        let errorJsonl = """
        {"type":"turn.started"}
        {"type":"error","message":"rate limited"}
        """
        let runner = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(path: "/opt/homebrew/bin/codex",
                                  args: ["exec", "--json", "--output-schema", schema.path, "-"]):
                .init(stdout: errorJsonl, stderr: "", exitCode: 1)
        ])
        let client = CodexClient(runner: runner, codexPath: "/opt/homebrew/bin/codex")
        do {
            _ = try await client.openSession(prompt: "x", schemaFile: schema, decoding: FixtureTriageResponse.self)
            Issue.record("expected throw")
        } catch CodexClientError.codexError(let msg) {
            #expect(msg.contains("rate limited"))
        }
    }
}
