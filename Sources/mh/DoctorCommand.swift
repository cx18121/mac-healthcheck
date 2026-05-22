import ArgumentParser
import Foundation

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check that mh's environment is ready (codex, probes, auth)"
    )

    func run() async throws {
        var allGreen = true
        let runner = FoundationProcessRunner()

        for binary in ["/usr/bin/top", "/bin/df", "/usr/bin/pmset",
                       "/usr/sbin/networksetup"] {
            allGreen = await checkExists(binary) && allGreen
        }

        // Codex path discovery: shared with MH.run so the two don't drift.
        // Well-known Homebrew paths first, then `which codex` for npm/pnpm/fnm installs.
        let codexFound = await CodexClient.resolvePath(runner: runner)
        if let path = codexFound {
            if CodexClient.wellKnownPaths.contains(path) {
                print("✓ codex at \(path)")
            } else {
                print("✓ codex at \(path) (via PATH)")
            }
        } else {
            print("✗ codex not found at \(CodexClient.wellKnownPaths.joined(separator: " or ")), nor via `which codex`")
            print("  → install via: brew install codex   (or npm i -g codex)")
            allGreen = false
        }

        // Codex auth check via `codex login status` (verified to exist in this
        // CLI version; exits 0 and prints "Logged in ..." when authed).
        if let codex = codexFound {
            do {
                let result = try await runner.run(
                    executableURL: URL(fileURLWithPath: codex),
                    arguments: ["login", "status"],
                    stdin: nil, timeout: 5.0
                )
                // `codex login status` prints "Logged in using ChatGPT" when authed.
                // Anchor on "logged in using" (which doesn't appear in "Not logged in").
                // NOTE: codex writes this line to stderr (not stdout) when launched
                // without a controlling TTY, so we check both streams.
                let combined = (result.stdout + "\n" + result.stderr).lowercased()
                if result.exitCode == 0 && combined.contains("logged in using") {
                    print("✓ codex authenticated")
                } else {
                    print("✗ codex not authenticated — run: codex login")
                    allGreen = false
                }
            } catch {
                print("✗ codex login status failed: \(error)")
                allGreen = false
            }
        }

        // Optional: airport (deprecated but used)
        let airportPath = "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
        if FileManager.default.isExecutableFile(atPath: airportPath) {
            print("✓ airport at \(airportPath)")
        } else {
            print("! airport not found at \(airportPath) — WiFi probe will degrade to networksetup-only")
        }

        if !allGreen {
            throw ExitCode(2)
        }
        print("\nAll required checks passed.")
    }

    private func checkExists(_ path: String) async -> Bool {
        if FileManager.default.isExecutableFile(atPath: path) {
            print("✓ \(path)")
            return true
        } else {
            print("✗ \(path) — required probe binary missing")
            return false
        }
    }

}
