import Testing
import Foundation
@testable import mh

@Suite("End-to-end pipeline (fixtures only)")
struct EndToEndTests {

    private func read(_ name: String, _ ext: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")!
        return try! String(contentsOf: url, encoding: .utf8)
    }

    @Test("shallow → triage → deep → analysis → fixes (no real codex)")
    func fullPipelineWithFixtures() async throws {
        // Build a minimal shallow snapshot first so we can call PromptBuilder.triage()
        // and capture the EXACT schema URL it resolves (from the main target's Bundle.module).
        // FakeProcessRunner matches on exact argv, so the test must use the same URL the
        // production code will pass — not a separately-resolved test-bundle URL.
        let probeRunner = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(path: "/usr/bin/top",
                                  args: ["-l", "1", "-n", "5", "-stats", "pid,cpu,mem,command"]):
                .init(stdout: read("top_runaway_slack", "txt"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport",
                                  args: ["-I"]):
                .init(stdout: read("airport_I_normal", "txt"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/usr/sbin/networksetup",
                                  args: ["-getairportnetwork", "en0"]):
                .init(stdout: read("networksetup_getairportnetwork", "txt"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/bin/df", args: ["-h"]):
                .init(stdout: read("df_h_normal", "txt"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/usr/bin/pmset", args: ["-g", "batt"]):
                .init(stdout: read("pmset_batt_ac", "txt"), stderr: "", exitCode: 0)
        ])
        let probeGatherer = SignalGatherer(runner: probeRunner)
        let shallow = await probeGatherer.gatherShallow()
        #expect(shallow.cpu.isOk)

        // Resolve schema URLs the same way PromptBuilder does so the FakeProcessRunner keys
        // line up with the actual argv CodexClient will produce.
        let triagePromptForURL = try PromptBuilder.triage(shallow)
        let triageSchemaPath = triagePromptForURL.schemaFile.path

        // Build the deep snapshot now so we can pre-compute the analysis schema URL too.
        let deepProbeRunner = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(path: "/usr/bin/top",
                                  args: ["-l", "1", "-n", "20", "-stats", "pid,cpu,mem,command"]):
                .init(stdout: read("top_runaway_slack", "txt"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/usr/bin/pmset", args: ["-g", "therm"]):
                .init(stdout: read("pmset_therm", "txt"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/usr/bin/uptime", args: []):
                .init(stdout: " 19:23  up 4 days, 12:34, 3 users, load averages: 1.2 1.1 1.0\n",
                      stderr: "", exitCode: 0)
        ])
        let deepGatherer = SignalGatherer(runner: deepProbeRunner)
        let deepSnap = await deepGatherer.gatherDeep(.cpu, shallow: shallow)
        let analysisPromptForURL = try PromptBuilder.analysis(deepSnap)
        let analysisSchemaPath = analysisPromptForURL.schemaFile.path

        // Now build the full pipeline runner with every probe + codex call scripted.
        let codexPath = "/opt/homebrew/bin/codex"
        let threadId = "019e4db8-6142-7031-a4b2-189862c6546f"
        let runner = FakeProcessRunner(scripted: [
            // Shallow probes
            FakeProcessRunner.Key(path: "/usr/bin/top",
                                  args: ["-l", "1", "-n", "5", "-stats", "pid,cpu,mem,command"]):
                .init(stdout: read("top_runaway_slack", "txt"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport",
                                  args: ["-I"]):
                .init(stdout: read("airport_I_normal", "txt"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/usr/sbin/networksetup",
                                  args: ["-getairportnetwork", "en0"]):
                .init(stdout: read("networksetup_getairportnetwork", "txt"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/bin/df", args: ["-h"]):
                .init(stdout: read("df_h_normal", "txt"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/usr/bin/pmset", args: ["-g", "batt"]):
                .init(stdout: read("pmset_batt_ac", "txt"), stderr: "", exitCode: 0),
            // Triage codex call — uses URL resolved by PromptBuilder above
            FakeProcessRunner.Key(path: codexPath,
                                  args: ["exec", "--json", "--output-schema", triageSchemaPath, "-"]):
                .init(stdout: read("codex_triage_response", "jsonl"), stderr: "", exitCode: 0),
            // Deep CPU probes
            FakeProcessRunner.Key(path: "/usr/bin/top",
                                  args: ["-l", "1", "-n", "20", "-stats", "pid,cpu,mem,command"]):
                .init(stdout: read("top_runaway_slack", "txt"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/usr/bin/pmset", args: ["-g", "therm"]):
                .init(stdout: read("pmset_therm", "txt"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/usr/bin/uptime", args: []):
                .init(stdout: " 19:23  up 4 days, 12:34, 3 users, load averages: 1.2 1.1 1.0\n",
                      stderr: "", exitCode: 0),
            // Analysis codex call (resume with captured thread_id)
            FakeProcessRunner.Key(path: codexPath,
                                  args: ["exec", "resume", threadId,
                                         "--json", "--output-schema", analysisSchemaPath, "-"]):
                .init(stdout: read("codex_analysis_response", "jsonl"), stderr: "", exitCode: 0)
        ])

        let gatherer = SignalGatherer(runner: runner)
        let codex = CodexClient(runner: runner, codexPath: codexPath)

        // 1. Shallow gather
        let realShallow = await gatherer.gatherShallow()
        #expect(realShallow.cpu.isOk)

        // 2. Triage
        let triagePrompt = try PromptBuilder.triage(realShallow)
        let triage: TriageResponse = try await codex.openSession(
            prompt: triagePrompt.prompt,
            schemaFile: triagePrompt.schemaFile,
            decoding: TriageResponse.self
        )
        #expect(triage.domain == "cpu")
        #expect(await codex.threadId == threadId)

        // 3. Deep gather for the triaged domain
        let realDeepSnap = await gatherer.gatherDeep(.cpu, shallow: realShallow)

        // 4. Analysis
        let analysisPrompt = try PromptBuilder.analysis(realDeepSnap)
        let analysis: AnalysisResponse = try await codex.resume(
            prompt: analysisPrompt.prompt,
            schemaFile: analysisPrompt.schemaFile,
            decoding: AnalysisResponse.self
        )
        #expect(analysis.report.contains("Slack"))
        #expect(analysis.fixes.count == 1)
        #expect(analysis.fixes.first?.action == .quitApp)
        #expect(analysis.fixes.first?.paramsJson.contains("us.slack.Slack") == true)
    }
}
