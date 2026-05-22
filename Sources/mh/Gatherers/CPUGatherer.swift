import Foundation

enum CPUGatherer {

    static let shallowTimeout: TimeInterval = 0.5
    static let topURL = URL(fileURLWithPath: "/usr/bin/top")

    static func shallow(runner: ProcessRunner) async -> ProbeResult<CPUShallow> {
        let result: ProcessResult
        do {
            result = try await runner.run(
                executableURL: topURL,
                arguments: ["-l", "1", "-n", "5", "-stats", "pid,cpu,mem,command"],
                stdin: nil,
                timeout: shallowTimeout
            )
        } catch ProcessRunnerError.timedOut {
            return .timedOut
        } catch {
            return .failed("spawn failed: \(error)")
        }
        if result.exitCode != 0 {
            return .failed("top exited \(result.exitCode): \(result.stderr.prefix(200))")
        }
        return parse(top: result.stdout)
    }

    static func parse(top: String) -> ProbeResult<CPUShallow> {
        let lines = top.components(separatedBy: "\n")
        guard let loadLine = lines.first(where: { $0.hasPrefix("Load Avg:") }) else {
            return .failed("could not find 'Load Avg' line")
        }
        // "Load Avg: 4.21, 3.85, 3.40"
        let loadStr = loadLine
            .replacingOccurrences(of: "Load Avg:", with: "")
            .trimmingCharacters(in: .whitespaces)
        let loadAvg = loadStr.split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard loadAvg.count == 3 else {
            return .failed("could not parse 3 load averages from '\(loadStr)'")
        }

        // Find the PID header line, then parse the following process rows
        guard let headerIdx = lines.firstIndex(where: { $0.hasPrefix("PID") }) else {
            return .failed("could not find PID header line")
        }
        let procRows = lines.dropFirst(headerIdx + 1)
            .prefix(5)
            .compactMap(parseTopRow(_:))

        let loadAverage = LoadAverage(oneMin: loadAvg[0], fiveMin: loadAvg[1], fifteenMin: loadAvg[2])
        return .value(CPUShallow(loadAverage: loadAverage, topProcesses: Array(procRows)))
    }

    /// "12345  380.0 12.5   Slack Helper (Renderer)"
    private static func parseTopRow(_ row: String) -> TopProcess? {
        let trimmed = row.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Split off first three fields by whitespace; the rest is the command.
        let scanner = Scanner(string: trimmed)
        scanner.charactersToBeSkipped = .whitespaces
        guard let pid = scanner.scanInt32(),
              let cpu = scanner.scanDouble(),
              let mem = scanner.scanDouble() else {
            return nil
        }
        let rest = String(trimmed[scanner.currentIndex...])
            .trimmingCharacters(in: .whitespaces)
        return TopProcess(pid: pid, cpuPercent: cpu, memoryMB: mem, command: rest)
    }
}
