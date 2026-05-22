import ArgumentParser
import Foundation

private func runFocus(_ domain: Domain) async throws {
    let runner = FoundationProcessRunner()
    let gatherer = SignalGatherer(runner: runner)
    let resolvedPath = await CodexClient.resolvePath(runner: runner) ?? "/opt/homebrew/bin/codex"
    let codex = CodexClient(runner: runner, codexPath: resolvedPath, model: "gpt-5.5")

    FileHandle.standardError.write(Data("[gathering signals... ".utf8))
    let started = Date()
    let shallow = await gatherer.gatherShallow()
    FileHandle.standardError.write(Data("\(formatElapsed(from: started))]\n".utf8))

    FileHandle.standardError.write(Data("[deep gather: \(domain.rawValue)... ".utf8))
    let deepStart = Date()
    let deepSnap = await gatherer.gatherDeep(domain, shallow: shallow)
    FileHandle.standardError.write(Data("\(formatElapsed(from: deepStart))]\n".utf8))

    FileHandle.standardError.write(Data("[analyzing... ".utf8))
    let analysisStart = Date()
    let analysis: AnalysisResponse
    do {
        let p = try PromptBuilder.analysis(deepSnap)
        // No triage session to resume from — start a NEW session for the analysis
        analysis = try await codex.openSession(
            prompt: p.prompt, schemaFile: p.schemaFile, decoding: AnalysisResponse.self
        )
    } catch {
        FileHandle.standardError.write(Data("failed]\n".utf8))
        try? AuditLogger.append(["error": "\(error)",
                                  "ts": ISO8601DateFormatter().string(from: Date()),
                                  "domain": domain.rawValue,
                                  "mode": "focus"],
                                 to: AuditLogger.errorFile)
        print("(codex analysis failed: \(error))")
        return
    }
    FileHandle.standardError.write(Data("\(formatElapsed(from: analysisStart))]\n\n".utf8))

    print(analysis.report)
    if !analysis.fixes.isEmpty {
        print("\n### Fixes")
        for fix in analysis.fixes {
            let marker = fix.dangerous ? " ⚠" : ""
            print("\(fix.id). \(fix.description)\(marker)")
        }
    }

    // Log session for later debugging
    if let tid = await codex.threadId {
        try? AuditLogger.append([
            "ts": ISO8601DateFormatter().string(from: Date()),
            "thread_id": tid, "domain": domain.rawValue, "mode": "focus"
        ], to: AuditLogger.sessionsFile)
    }

    let chat = ChatLoop(codex: codex, executor: FixExecutor(runner: runner),
                        fixes: analysis.fixes, snapshotTimestamp: deepSnap.deepTimestamp)
    await chat.run()
}

private func formatElapsed(from start: Date) -> String {
    let s = Date().timeIntervalSince(start)
    return String(format: "%.1fs", s)
}

struct WifiFocus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wifi",
        abstract: "Deep-dive WiFi diagnostics (skips triage)"
    )
    func run() async throws { try await runFocus(.wifi) }
}

struct CPUFocus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cpu",
        abstract: "Deep-dive CPU diagnostics (skips triage)"
    )
    func run() async throws { try await runFocus(.cpu) }
}

struct DiskFocus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disk",
        abstract: "Deep-dive disk diagnostics (skips triage)"
    )
    func run() async throws { try await runFocus(.disk) }
}

struct BatteryFocus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "battery",
        abstract: "Deep-dive battery diagnostics (skips triage)"
    )
    func run() async throws { try await runFocus(.battery) }
}
