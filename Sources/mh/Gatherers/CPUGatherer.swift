import Foundation

enum CPUGatherer {

    // top -l 1 has a mandatory sample interval (~1s default); 3.0 gives headroom on a loaded machine.
    static let shallowTimeout: TimeInterval = 3.0
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

    private static func parse(top: String) -> ProbeResult<CPUShallow> {
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
        guard let headerIdx = lines.firstIndex(where: { $0.hasPrefix("PID ") || $0.hasPrefix("PID\t") }) else {
            return .failed("could not find PID header line")
        }
        let procRows = lines.dropFirst(headerIdx + 1)
            .prefix(5)
            .compactMap(parseTopRow(_:))
        guard !procRows.isEmpty else {
            return .failed("PID header found but no process rows parsed")
        }

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

    static let deepTimeout: TimeInterval = 3.0
    static let pmsetURL = URL(fileURLWithPath: "/usr/bin/pmset")
    static let uptimeURL = URL(fileURLWithPath: "/usr/bin/uptime")

    static func deep(runner: ProcessRunner) async -> ProbeResult<CPUDeep> {
        async let topR = runDeepTop(runner: runner)
        async let thermR = runThermal(runner: runner)
        async let upR = runUptime(runner: runner)
        let (top, therm, uptime) = await (topR, thermR, upR)

        // Allow individual probes to degrade — only fail the whole thing if top fails.
        guard case .value(let topOut) = top else {
            if case .timedOut = top { return .timedOut }
            return .failed("deep top failed")
        }
        let thermOut: String
        if case .value(let t) = therm { thermOut = t } else { thermOut = "(unavailable)" }
        let upSeconds: Int
        if case .value(let u) = uptime { upSeconds = parseUptime(u) } else { upSeconds = 0 }

        return .value(CPUDeep(
            fullTopOutput: String(topOut.prefix(4096)),
            thermalPressure: String(thermOut.prefix(2048)),
            uptimeSeconds: upSeconds
        ))
    }

    private static func runDeepTop(runner: ProcessRunner) async -> ProbeResult<String> {
        do {
            let r = try await runner.run(
                executableURL: topURL,
                arguments: ["-l", "1", "-n", "20", "-stats", "pid,cpu,mem,command"],
                stdin: nil, timeout: deepTimeout)
            if r.exitCode != 0 { return .failed("top exit \(r.exitCode)") }
            return .value(r.stdout)
        } catch ProcessRunnerError.timedOut { return .timedOut }
        catch { return .failed("\(error)") }
    }

    private static func runThermal(runner: ProcessRunner) async -> ProbeResult<String> {
        do {
            let r = try await runner.run(
                executableURL: pmsetURL, arguments: ["-g", "therm"],
                stdin: nil, timeout: deepTimeout)
            if r.exitCode != 0 { return .failed("pmset exit \(r.exitCode)") }
            return .value(r.stdout)
        } catch ProcessRunnerError.timedOut { return .timedOut }
        catch ProcessRunnerError.spawnFailed { return .unavailable }
        catch { return .failed("\(error)") }
    }

    private static func runUptime(runner: ProcessRunner) async -> ProbeResult<String> {
        do {
            let r = try await runner.run(
                executableURL: uptimeURL, arguments: [],
                stdin: nil, timeout: deepTimeout)
            if r.exitCode != 0 { return .failed("uptime exit \(r.exitCode)") }
            return .value(r.stdout)
        } catch ProcessRunnerError.timedOut { return .timedOut }
        catch { return .failed("\(error)") }
    }

    /// "19:23 up 4 days, 12:34, ..." → 4*86400 + 12*3600 + 34*60
    static func parseUptime(_ line: String) -> Int {
        var seconds = 0
        if let m = line.range(of: #"(\d+) days?"#, options: .regularExpression) {
            let s = line[m].split(separator: " ").first.flatMap { Int($0) } ?? 0
            seconds += s * 86400
        }
        // "up 12:34" or "up 12 hrs"
        if let m = line.range(of: #"\b(\d+):(\d+)\b"#, options: .regularExpression) {
            let parts = String(line[m]).split(separator: ":")
            if parts.count == 2, let h = Int(parts[0]), let mm = Int(parts[1]) {
                seconds += h * 3600 + mm * 60
            }
        } else if let m = line.range(of: #"(\d+) hrs?"#, options: .regularExpression) {
            let s = line[m].split(separator: " ").first.flatMap { Int($0) } ?? 0
            seconds += s * 3600
        }
        return seconds
    }
}
