import Foundation

struct ProcessResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum ProcessRunnerError: Error {
    case timedOut
    case spawnFailed(String)
}

protocol ProcessRunner: Sendable {
    /// Runs an executable with fixed argv. Never uses /bin/sh -c. The `stdin` parameter,
    /// if provided, is written to the child process's standard input.
    func run(executableURL: URL,
             arguments: [String],
             stdin: String?,
             timeout: TimeInterval) async throws -> ProcessResult
}

struct FoundationProcessRunner: ProcessRunner {
    func run(executableURL: URL,
             arguments: [String],
             stdin: String?,
             timeout: TimeInterval) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Wire up an AsyncStream so we can await termination without bridging a
        // non-Sendable Process across task boundaries via a continuation closure.
        let (terminationStream, terminationContinuation) = AsyncStream.makeStream(of: Void.self)
        process.terminationHandler = { _ in
            terminationContinuation.yield(())
            terminationContinuation.finish()
        }

        if let stdin = stdin {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
            do {
                try process.run()
            } catch {
                throw ProcessRunnerError.spawnFailed(String(describing: error))
            }
            try stdinPipe.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
            try stdinPipe.fileHandleForWriting.close()
        } else {
            do {
                try process.run()
            } catch {
                throw ProcessRunnerError.spawnFailed(String(describing: error))
            }
        }

        // Race waiting for termination against a timeout. The TaskGroup returns
        // `true` if the timeout fired first, `false` if the process terminated.
        // We deliberately do NOT capture the non-Sendable `Process` inside the
        // task group; instead we await the termination via the AsyncStream and
        // signal termination from the (already-bound) termination handler.
        let timedOut: Bool = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return true
            }
            group.addTask {
                for await _ in terminationStream { break }
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        if timedOut {
            if process.isRunning {
                process.terminate()
            }
            // Drain pipes to avoid leaking file descriptors; ignore content.
            _ = try? stdoutPipe.fileHandleForReading.readToEnd()
            _ = try? stderrPipe.fileHandleForReading.readToEnd()
            throw ProcessRunnerError.timedOut
        }

        let outData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        let errData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
        return ProcessResult(
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }
}

/// Test double. Maps `(executable, args)` keys to scripted results.
struct FakeProcessRunner: ProcessRunner {
    struct Key: Hashable, Sendable {
        let path: String
        let args: [String]
    }
    struct Scripted: Sendable {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }
    let scripted: [Key: Scripted]

    func run(executableURL: URL,
             arguments: [String],
             stdin: String?,
             timeout: TimeInterval) async throws -> ProcessResult {
        let key = Key(path: executableURL.path, args: arguments)
        guard let s = scripted[key] else {
            throw ProcessRunnerError.spawnFailed(
                "no scripted result for \(key.path) \(key.args.joined(separator: " "))"
            )
        }
        return ProcessResult(stdout: s.stdout, stderr: s.stderr, exitCode: s.exitCode)
    }
}
