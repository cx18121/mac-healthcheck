import Foundation

enum CodexClientError: Error {
    case codexError(String)
    case malformedOutput(String)
    case noAgentMessage
    case decodingFailed(String)
    case sessionNotStarted          // resume() called before openSession()
}

actor CodexClient {
    private let runner: ProcessRunner
    private let codexURL: URL
    private let model: String?
    private(set) var threadId: String?
    static let callTimeout: TimeInterval = 30.0
    static let wellKnownPaths = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]

    init(runner: ProcessRunner = FoundationProcessRunner(),
         codexPath: String = "/opt/homebrew/bin/codex",
         model: String? = nil) {
        self.runner = runner
        self.codexURL = URL(fileURLWithPath: codexPath)
        self.model = model
    }

    /// Discovers the codex executable: well-known Homebrew paths first, then `which codex`
    /// (which picks up npm/pnpm/fnm-installed copies via the user's PATH). Used by both
    /// `mh doctor` and `MH.run` so they don't drift.
    static func resolvePath(runner: ProcessRunner) async -> String? {
        for path in wellKnownPaths {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        do {
            let result = try await runner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/which"),
                arguments: ["codex"],
                stdin: nil, timeout: 2.0
            )
            guard result.exitCode == 0 else { return nil }
            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : path
        } catch {
            return nil
        }
    }

    /// Start a new conversation. Captures and stores the `thread_id` for subsequent resume calls.
    func openSession<T: Decodable>(
        prompt: String,
        schemaFile: URL,
        decoding: T.Type
    ) async throws -> T {
        var args = ["exec", "--json", "--output-schema", schemaFile.path]
        if let m = model { args.append(contentsOf: ["-m", m]) }
        args.append("-")
        let result = try await runner.run(
            executableURL: codexURL,
            arguments: args,
            stdin: prompt,
            timeout: Self.callTimeout
        )
        let (parsedThreadId, payload) = try parseJsonl(result.stdout)
        guard let tid = parsedThreadId else {
            throw CodexClientError.malformedOutput("thread.started event missing from Codex output")
        }
        self.threadId = tid
        return try decode(payload, as: T.self)
    }

    /// Continue an existing conversation. Schema can be overridden per turn (pass nil to inherit).
    func resume<T: Decodable>(
        prompt: String,
        schemaFile: URL?,
        decoding: T.Type
    ) async throws -> T {
        guard let tid = threadId else {
            throw CodexClientError.sessionNotStarted
        }
        var args = ["exec", "resume", tid, "--json"]
        if let schema = schemaFile {
            args.append(contentsOf: ["--output-schema", schema.path])
        }
        if let m = model { args.append(contentsOf: ["-m", m]) }
        args.append("-")
        let result = try await runner.run(
            executableURL: codexURL,
            arguments: args,
            stdin: prompt,
            timeout: Self.callTimeout
        )
        let (_, payload) = try parseJsonl(result.stdout)
        return try decode(payload, as: T.self)
    }

    // MARK: - JSONL parsing

    /// Returns (thread_id-if-present, final agent_message text).
    private func parseJsonl(_ stdout: String) throws -> (String?, String) {
        var threadId: String?
        var agentMessage: String?
        for line in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            guard let type = obj["type"] as? String else { continue }
            switch type {
            case "thread.started":
                threadId = obj["thread_id"] as? String
            case "item.completed":
                // If Codex emits multiple agent_message items in one turn (e.g. streaming
                // chunks or tool-call sequences), last one wins — the final message is the
                // complete schema-conformant JSON.
                if let item = obj["item"] as? [String: Any],
                   item["type"] as? String == "agent_message",
                   let text = item["text"] as? String {
                    agentMessage = text
                }
            case "error":
                let msg = (obj["message"] as? String) ?? "unknown codex error"
                throw CodexClientError.codexError(msg)
            default:
                break
            }
        }
        guard let msg = agentMessage else {
            throw CodexClientError.noAgentMessage
        }
        return (threadId, msg)
    }

    private func decode<T: Decodable>(_ payload: String, as type: T.Type) throws -> T {
        guard let data = payload.data(using: .utf8) else {
            throw CodexClientError.decodingFailed("payload not utf8")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CodexClientError.decodingFailed("\(error)")
        }
    }
}
