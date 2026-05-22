import Foundation

struct AnalysisResponse: Codable, Sendable {
    let report: String
    let fixes: [ProposedFix]
}

struct ChatLoop {
    let codex: CodexClient
    let executor: FixExecutor
    let fixes: [ProposedFix]
    let snapshotTimestamp: Date
    let maxTurns: Int
    static let staleThresholdSeconds: TimeInterval = 60

    init(codex: CodexClient, executor: FixExecutor, fixes: [ProposedFix],
         snapshotTimestamp: Date, maxTurns: Int = 6) {
        self.codex = codex
        self.executor = executor
        self.fixes = fixes
        self.snapshotTimestamp = snapshotTimestamp
        self.maxTurns = maxTurns
    }

    func run() async {
        var turns = 0
        print("\n(chat mode active — ask follow-up questions, `run N` to execute a fix, or `exit`)")
        while turns < maxTurns {
            print("> ", terminator: "")
            guard let line = readLine() else { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.lowercased() == "exit" { return }
            if let idx = Self.parseRunCommand(trimmed) {
                await handleRun(idx)
            } else {
                await handleFollowUp(trimmed)
            }
            turns += 1
        }
        print("(turn budget of \(maxTurns) reached; restart `mh` for a fresh session)")
    }

    private func handleRun(_ idx: Int) async {
        guard idx >= 0, idx < fixes.count else {
            print("no fix #\(idx + 1); reports has \(fixes.count) fix(es)")
            return
        }
        let age = Date().timeIntervalSince(snapshotTimestamp)
        if age > Self.staleThresholdSeconds {
            print("Snapshot is \(Int(age))s old; PIDs/interfaces may have changed. Continue? [y/N] ",
                  terminator: "")
            let line = readLine() ?? ""
            guard line.lowercased().hasPrefix("y") else {
                print("(skipped — re-run `mh` for a fresh snapshot)")
                return
            }
        }
        do {
            let result = try await executor.execute(fixes[idx])
            print("[exit \(result.exitCode)] \(result.stdoutPreview)")
            if !result.stderrPreview.isEmpty {
                print("[stderr] \(result.stderrPreview)")
            }
        } catch FixExecutorError.userDeclined {
            print("(declined)")
        } catch FixExecutorError.invalidParam(let m) {
            print("invalid fix parameters: \(m)")
        } catch FixExecutorError.revalidationFailed(let m) {
            print("fix is stale: \(m)")
        } catch {
            print("fix failed: \(error)")
        }
    }

    private func handleFollowUp(_ line: String) async {
        struct FollowUpResponse: Codable { let report: String; let fixes: [ProposedFix] }
        do {
            let resp: FollowUpResponse = try await codex.resume(
                prompt: line, schemaFile: nil, decoding: FollowUpResponse.self
            )
            print(resp.report)
        } catch {
            print("(codex follow-up failed: \(error))")
        }
    }

    /// "run 2" → 1 (zero-indexed). 1-indexed in user input.
    static func parseRunCommand(_ s: String) -> Int? {
        let trimmed = s.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.hasPrefix("run ") else { return nil }
        let rest = trimmed.dropFirst("run ".count).trimmingCharacters(in: .whitespaces)
        guard let n = Int(rest), n >= 1 else { return nil }
        return n - 1
    }
}
