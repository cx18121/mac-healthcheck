import Foundation

enum DiskGatherer {

    static let shallowTimeout: TimeInterval = 1.0  // df -h is fast (<100ms typically); 1s headroom
    static let dfURL = URL(fileURLWithPath: "/bin/df")

    /// Mount points worth surfacing to the LLM. Skip Apple's internal volumes.
    static let interestingMounts: Set<String> = ["/", "/System/Volumes/Data"]

    static func shallow(runner: ProcessRunner) async -> ProbeResult<DiskShallow> {
        do {
            let r = try await runner.run(
                executableURL: dfURL, arguments: ["-h"],
                stdin: nil, timeout: shallowTimeout
            )
            if r.exitCode != 0 { return .failed("df exited \(r.exitCode)") }
            return parse(df: r.stdout)
        } catch ProcessRunnerError.timedOut { return .timedOut }
        catch ProcessRunnerError.spawnFailed { return .unavailable }
        catch { return .failed("\(error)") }
    }

    private static func parse(df: String) -> ProbeResult<DiskShallow> {
        let lines = df.components(separatedBy: "\n").dropFirst() // header
        var mounts: [MountUsage] = []
        for line in lines {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 9 else { continue }
            // df's mount point is always the last whitespace-separated token; using cols.last
            // is immune to filesystem device names that contain spaces (rare but possible).
            guard let mountPoint = cols.last.map(String.init) else { continue }
            guard interestingMounts.contains(mountPoint) else { continue }
            // Capacity is e.g. "4%"
            let pctStr = String(cols[4]).replacingOccurrences(of: "%", with: "")
            // Avail is e.g. "234Gi"
            let availStr = String(cols[3])
            guard let pct = Int(pctStr) else { continue }
            let availableGB = parseHumanSize(availStr)
            mounts.append(MountUsage(mountPoint: mountPoint, percentFull: pct, availableGB: availableGB))
        }
        // Following the fail-loud pattern from CPUGatherer: empty mounts is suspicious.
        guard !mounts.isEmpty else {
            return .failed("df -h produced no rows matching interesting mounts (/ or /System/Volumes/Data)")
        }
        return .value(DiskShallow(mounts: mounts))
    }

    /// "234Gi" → 234.0; "500Mi" → 0.488 (GB).
    /// Returns 0.0 for unrecognised suffixes (e.g. "Bi"). Acceptable for v0.1 because
    /// our `interestingMounts` set excludes the Apple internal volumes that report sub-GB sizes.
    private static func parseHumanSize(_ s: String) -> Double {
        var s = s
        var multiplier: Double = 1.0
        if s.hasSuffix("Ti") { multiplier = 1024.0; s.removeLast(2) }
        else if s.hasSuffix("Gi") { multiplier = 1.0; s.removeLast(2) }
        else if s.hasSuffix("Mi") { multiplier = 1.0 / 1024.0; s.removeLast(2) }
        else if s.hasSuffix("Ki") { multiplier = 1.0 / (1024.0 * 1024.0); s.removeLast(2) }
        return (Double(s) ?? 0.0) * multiplier
    }
}
