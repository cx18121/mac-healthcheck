import ArgumentParser
import Foundation

@main
struct MH: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mh",
        abstract: "macOS diagnostic CLI with LLM synthesis",
        subcommands: [Doctor.self]
    )

    func run() async throws {
        let runner = FoundationProcessRunner()
        let gatherer = SignalGatherer(runner: runner)
        // Use the shared resolver so MH and `mh doctor` agree on where codex lives.
        // Falls back to the canonical Homebrew path if resolution fails — CodexClient
        // will then surface a clear error on the first call rather than crashing here.
        let codexPath = await CodexClient.resolvePath(runner: runner) ?? "/opt/homebrew/bin/codex"
        let codex = CodexClient(runner: runner, codexPath: codexPath, model: "gpt-5.5")

        FileHandle.standardError.write(Data("[gathering signals... ".utf8))
        let started = Date()
        let shallow = await gatherer.gatherShallow()
        FileHandle.standardError.write(Data("\(format(elapsed: started))]\n".utf8))

        FileHandle.standardError.write(Data("[triaging... ".utf8))
        let triageStart = Date()
        let triage: TriageResponse
        do {
            let p = try PromptBuilder.triage(shallow)
            triage = try await codex.openSession(
                prompt: p.prompt, schemaFile: p.schemaFile, decoding: TriageResponse.self
            )
        } catch {
            FileHandle.standardError.write(Data("failed]\n".utf8))
            try? AuditLogger.append(["error": "\(error)", "ts": ISO8601DateFormatter().string(from: Date())],
                                     to: AuditLogger.errorFile)
            print("(codex triage failed; raw snapshot follows)\n")
            print(localFallbackReport(shallow))
            return
        }
        FileHandle.standardError.write(Data("\(format(elapsed: triageStart))]\n".utf8))

        guard let domain = Domain(rawValue: triage.domain) else {
            print("Everything looks normal — Codex reasoning: \(triage.reasoning)")
            return
        }

        FileHandle.standardError.write(Data("[deep gather: \(domain.rawValue)... ".utf8))
        let deepStart = Date()
        let deepSnap = await gatherer.gatherDeep(domain, shallow: shallow)
        FileHandle.standardError.write(Data("\(format(elapsed: deepStart))]\n".utf8))

        FileHandle.standardError.write(Data("[analyzing... ".utf8))
        let analysisStart = Date()
        let analysis: AnalysisResponse
        do {
            let p = try PromptBuilder.analysis(deepSnap)
            analysis = try await codex.resume(
                prompt: p.prompt, schemaFile: p.schemaFile, decoding: AnalysisResponse.self
            )
        } catch {
            FileHandle.standardError.write(Data("failed]\n".utf8))
            try? AuditLogger.append(["error": "\(error)", "ts": ISO8601DateFormatter().string(from: Date())],
                                     to: AuditLogger.errorFile)
            print("(codex analysis failed)")
            return
        }
        FileHandle.standardError.write(Data("\(format(elapsed: analysisStart))]\n\n".utf8))

        print(analysis.report)
        print("\n### Fixes")
        for fix in analysis.fixes {
            let marker = fix.dangerous ? " ⚠" : ""
            print("\(fix.id). \(fix.description)\(marker)")
        }

        // Log session for later debugging
        if let tid = await codex.threadId {
            try? AuditLogger.append([
                "ts": ISO8601DateFormatter().string(from: Date()),
                "thread_id": tid, "domain": domain.rawValue
            ], to: AuditLogger.sessionsFile)
        }

        let chat = ChatLoop(codex: codex, executor: FixExecutor(runner: runner),
                             fixes: analysis.fixes, snapshotTimestamp: deepSnap.deepTimestamp)
        await chat.run()
    }

    private func format(elapsed start: Date) -> String {
        let s = Date().timeIntervalSince(start)
        return String(format: "%.1fs", s)
    }

    private func localFallbackReport(_ s: ShallowSnapshot) -> String {
        var out = "## Local snapshot (Codex unavailable)\n\n"
        out += "Timestamp: \(s.timestamp)\n"
        out += "CPU: \(s.cpu)\nWiFi: \(s.wifi)\nDisk: \(s.disk)\nBattery: \(s.battery)\n"
        return out
    }
}

struct TriageResponse: Codable {
    let domain: String      // wifi/cpu/disk/battery/none
    let reasoning: String
}
