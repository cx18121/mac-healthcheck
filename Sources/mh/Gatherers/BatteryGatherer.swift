import Foundation

enum BatteryGatherer {

    static let shallowTimeout: TimeInterval = 1.0  // pmset is fast (<200ms typically); 1s headroom
    static let pmsetURL = URL(fileURLWithPath: "/usr/bin/pmset")

    static func shallow(runner: ProcessRunner) async -> ProbeResult<BatteryShallow> {
        do {
            let r = try await runner.run(
                executableURL: pmsetURL, arguments: ["-g", "batt"],
                stdin: nil, timeout: shallowTimeout
            )
            if r.exitCode != 0 { return .failed("pmset exited \(r.exitCode)") }
            return parse(pmset: r.stdout)
        } catch ProcessRunnerError.timedOut { return .timedOut }
        catch ProcessRunnerError.spawnFailed { return .unavailable }
        catch { return .failed("\(error)") }
    }

    private static func parse(pmset: String) -> ProbeResult<BatteryShallow> {
        let onAC = pmset.contains("'AC Power'")
        // Find "67%;" or "100%;" pattern
        var percent = -1
        if let percentRange = pmset.range(of: #"\d+%;"#, options: .regularExpression) {
            let pctStr = pmset[percentRange].dropLast(2)  // strip "%;"
            percent = Int(pctStr) ?? -1
        }
        if percent < 0 { return .failed("could not parse percent") }

        let charging = pmset.contains("; charging;")
        var timeRemaining: Int? = nil
        if let m = pmset.range(of: #";\s+(\d+):(\d+)\s+remaining"#, options: .regularExpression) {
            let hhmm = pmset[m]
                .replacingOccurrences(of: ";", with: "")
                .replacingOccurrences(of: " remaining", with: "")
                .trimmingCharacters(in: .whitespaces)
            let parts = hhmm.split(separator: ":")
            if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), h + m > 0 {
                timeRemaining = h * 60 + m
            }
        }

        return .value(BatteryShallow(
            percent: percent,
            onAC: onAC,
            charging: charging,
            timeRemainingMinutes: timeRemaining
        ))
    }

    static let deepTimeout: TimeInterval = 3.0
    static let ioregURL = URL(fileURLWithPath: "/usr/sbin/ioreg")

    static func deep(runner: ProcessRunner) async -> ProbeResult<BatteryDeep> {
        async let gR = runPmsetGAll(runner: runner)
        async let lR = runPmsetGLog(runner: runner)
        async let cR = runIoregCycles(runner: runner)
        let (g, l, c) = await (gR, lR, cR)

        let gFull = g.value ?? "(unavailable)"
        let history = l.value ?? "(unavailable)"
        let cycles = c.value.flatMap(parseCycleCount)

        return .value(BatteryDeep(
            pmsetGFull: String(gFull.prefix(2048)),
            powerHistory: String(history.prefix(4096)),
            cycleCount: cycles
        ))
    }

    private static func runPmsetGAll(runner: ProcessRunner) async -> ProbeResult<String> {
        do {
            let r = try await runner.run(executableURL: pmsetURL, arguments: ["-g"],
                                          stdin: nil, timeout: deepTimeout)
            return r.exitCode == 0 ? .value(r.stdout) : .failed("exit \(r.exitCode)")
        } catch { return .failed("\(error)") }
    }

    private static func runPmsetGLog(runner: ProcessRunner) async -> ProbeResult<String> {
        // pmset -g log can be very long. We truncate at the caller level.
        do {
            let r = try await runner.run(executableURL: pmsetURL, arguments: ["-g", "log"],
                                          stdin: nil, timeout: deepTimeout)
            return r.exitCode == 0 ? .value(r.stdout) : .failed("exit \(r.exitCode)")
        } catch ProcessRunnerError.timedOut { return .timedOut }
        catch { return .failed("\(error)") }
    }

    private static func runIoregCycles(runner: ProcessRunner) async -> ProbeResult<String> {
        do {
            let r = try await runner.run(
                executableURL: ioregURL,
                arguments: ["-rn", "AppleSmartBattery"],
                stdin: nil, timeout: deepTimeout)
            return r.exitCode == 0 ? .value(r.stdout) : .failed("exit \(r.exitCode)")
        } catch { return .failed("\(error)") }
    }

    static func parseCycleCount(_ ioregOut: String) -> Int? {
        if let m = ioregOut.range(of: #""CycleCount" = (\d+)"#, options: .regularExpression) {
            return ioregOut[m].split(separator: " ").last.flatMap { Int($0) }
        }
        return nil
    }
}
