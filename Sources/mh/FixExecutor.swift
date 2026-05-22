import Foundation

enum FixExecutorError: Error {
    case invalidParam(String)
    case unsupportedAction(FixAction)
    case userDeclined
    case revalidationFailed(String)
}

struct FixExecutionResult: Sendable {
    let exitCode: Int32
    let stdoutPreview: String
    let stderrPreview: String
}

struct FixExecutor: Sendable {
    let runner: ProcessRunner
    /// Confirmation hook. Called before executing any fix marked dangerous. Tests inject a stub.
    let confirm: @Sendable (FixAction, String) async -> Bool
    static let execTimeout: TimeInterval = 15.0
    static let sudoURL = URL(fileURLWithPath: "/usr/bin/sudo")
    static let networksetupURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    static let osascriptURL = URL(fileURLWithPath: "/usr/bin/osascript")
    static let killURL = URL(fileURLWithPath: "/bin/kill")
    static let rmURL = URL(fileURLWithPath: "/bin/rm")
    static let dockerURL = URL(fileURLWithPath: "/usr/local/bin/docker")
    static let npmURL = URL(fileURLWithPath: "/opt/homebrew/bin/npm")

    init(runner: ProcessRunner = FoundationProcessRunner(),
         confirm: @escaping @Sendable (FixAction, String) async -> Bool = Self.interactiveConfirm) {
        self.runner = runner
        self.confirm = confirm
    }

    func execute(_ fix: ProposedFix) async throws -> FixExecutionResult {
        // 1) Confirm dangerous fixes (use either Codex flag OR the per-action fallback)
        let isDangerous = fix.dangerous || fix.action.dangerousByDefault
        if isDangerous {
            let ok = await confirm(fix.action, fix.description)
            guard ok else { throw FixExecutorError.userDeclined }
        }

        let result: ProcessResult
        switch fix.action {
        case .restartWifi:
            let params = try decode(RestartWifiParams.self, fix.paramsJson)
            try validateInterface(params.interface)
            _ = try await runner.run(
                executableURL: Self.networksetupURL,
                arguments: ["-setairportpower", params.interface, "off"],
                stdin: nil, timeout: Self.execTimeout
            )
            result = try await runner.run(
                executableURL: Self.networksetupURL,
                arguments: ["-setairportpower", params.interface, "on"],
                stdin: nil, timeout: Self.execTimeout
            )
        default:
            let (url, args) = try buildCommand(for: fix)
            result = try await runner.run(
                executableURL: url, arguments: args, stdin: nil, timeout: Self.execTimeout
            )
        }

        try? AuditLogger.append([
            "ts": ISO8601DateFormatter().string(from: Date()),
            "fix_id": fix.id,
            "action": fix.action.rawValue,
            "params_json": fix.paramsJson,
            "description": fix.description,
            "exit_code": Int(result.exitCode),
            "stdout_preview": String(result.stdout.prefix(1024)),
            "stderr_preview": String(result.stderr.prefix(1024))
        ], to: AuditLogger.logFile)

        return FixExecutionResult(
            exitCode: result.exitCode,
            stdoutPreview: String(result.stdout.prefix(1024)),
            stderrPreview: String(result.stderr.prefix(1024))
        )
    }

    // MARK: - Build commands

    private func buildCommand(for fix: ProposedFix) throws -> (URL, [String]) {
        switch fix.action {
        case .flushDns:
            return (Self.sudoURL, ["-n", "dscacheutil", "-flushcache"])

        case .restartWifi:
            // Handled in execute() as a two-step run
            fatalError("restartWifi handled in execute(), not buildCommand")

        case .quitApp, .killPid, .clearXcodeDerivedData, .clearNpmCache, .dockerStopAll:
            throw FixExecutorError.unsupportedAction(fix.action)  // implemented in Task 17
        }
    }

    private func validateInterface(_ s: String) throws {
        let pattern = #"^en\d+$"#
        guard s.range(of: pattern, options: .regularExpression) != nil else {
            throw FixExecutorError.invalidParam("interface '\(s)' does not match ^en\\d+$")
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw FixExecutorError.invalidParam("params_json not utf8")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw FixExecutorError.invalidParam("decode \(T.self): \(error)")
        }
    }

    static let interactiveConfirm: @Sendable (FixAction, String) async -> Bool = { action, desc in
        print("\nRun \(action.rawValue) (\(desc))? [y/N] ", terminator: "")
        let line = readLine() ?? ""
        return line.lowercased().hasPrefix("y")
    }
}
