import Foundation

enum WifiGatherer {

    static let shallowTimeout: TimeInterval = 1.0  // airport + networksetup are typically fast (<300ms); 1s headroom
    static let airportURL = URL(fileURLWithPath:
        "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport")
    static let networksetupURL = URL(fileURLWithPath: "/usr/sbin/networksetup")

    static func shallow(runner: ProcessRunner, interface: String = "en0") async -> ProbeResult<WifiShallow> {
        async let airportR = runAirport(runner: runner)
        async let networkR = runNetworksetup(runner: runner, interface: interface)
        let (airport, network) = await (airportR, networkR)

        switch (airport, network) {
        // Both unavailable → truly no wifi info
        case (.unavailable, .unavailable):
            return .unavailable
        case (.timedOut, _), (_, .timedOut):
            return .timedOut
        case (.failed(let a), .failed(let b)):
            return .failed("airport: \(a); networksetup: \(b)")
        case (.failed(let m), _):
            return .failed("airport: \(m)")
        case (_, .failed(let m)):
            return .failed("networksetup: \(m)")
        // Airport unavailable (macOS 15+ deprecation) but networksetup gave us SSID — degrade gracefully
        case (.unavailable, .value(let networkOut)):
            return parseNetworksetupOnly(networksetup: networkOut, interface: interface)
        // Networksetup unavailable but airport worked — shouldn't happen but handle it
        case (.value(let airportOut), .unavailable):
            return parse(airport: airportOut, networksetup: "", interface: interface)
        case (.value(let airportOut), .value(let networkOut)):
            return parse(airport: airportOut, networksetup: networkOut, interface: interface)
        }
    }

    private static func parseNetworksetupOnly(networksetup: String, interface: String) -> ProbeResult<WifiShallow> {
        let ssidLine = networksetup.components(separatedBy: "\n")
            .first(where: { $0.contains("Current Wi-Fi Network:") })
        let ssid = ssidLine?
            .replacingOccurrences(of: "Current Wi-Fi Network:", with: "")
            .trimmingCharacters(in: .whitespaces)
        return .value(WifiShallow(
            ssid: (ssid?.isEmpty == false) ? ssid : nil,
            rssi: nil,
            channel: nil,
            linkRateMbps: nil,
            interface: interface
        ))
    }

    private static func runAirport(runner: ProcessRunner) async -> ProbeResult<String> {
        do {
            let r = try await runner.run(
                executableURL: airportURL, arguments: ["-I"],
                stdin: nil, timeout: shallowTimeout
            )
            if r.exitCode != 0 { return .failed("exit \(r.exitCode)") }
            return .value(r.stdout)
        } catch ProcessRunnerError.timedOut { return .timedOut }
        catch ProcessRunnerError.spawnFailed { return .unavailable }
        catch { return .failed("\(error)") }
    }

    private static func runNetworksetup(runner: ProcessRunner, interface: String) async -> ProbeResult<String> {
        do {
            let r = try await runner.run(
                executableURL: networksetupURL,
                arguments: ["-getairportnetwork", interface],
                stdin: nil, timeout: shallowTimeout
            )
            if r.exitCode != 0 { return .failed("exit \(r.exitCode)") }
            return .value(r.stdout)
        } catch ProcessRunnerError.timedOut { return .timedOut }
        catch ProcessRunnerError.spawnFailed { return .unavailable }
        catch { return .failed("\(error)") }
    }

    private static func parse(airport: String, networksetup: String, interface: String) -> ProbeResult<WifiShallow> {
        // airport -I gives RSSI, channel, link rate
        let map = airport.components(separatedBy: "\n").reduce(into: [String: String]()) { dict, line in
            let pair = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2 { dict[pair[0]] = pair[1] }
        }
        guard !map.isEmpty else {
            return .failed("airport -I output unrecognised (no parseable key:value lines)")
        }
        let rssi = map["agrCtlRSSI"].flatMap(Int.init)
        let linkRate = map["lastTxRate"].flatMap(Double.init)
        // "channel: 36,80" → primary channel = 36
        let channel = map["channel"]?.split(separator: ",").first.flatMap { Int($0) }

        // networksetup: "Current Wi-Fi Network: HomeNetwork" (or "You are not associated...")
        let ssidLine = networksetup.components(separatedBy: "\n")
            .first(where: { $0.contains("Current Wi-Fi Network:") })
        let ssid = ssidLine?
            .replacingOccurrences(of: "Current Wi-Fi Network:", with: "")
            .trimmingCharacters(in: .whitespaces)

        return .value(WifiShallow(
            ssid: (ssid?.isEmpty == false) ? ssid : nil,
            rssi: rssi,
            channel: channel,
            linkRateMbps: linkRate,
            interface: interface
        ))
    }

    static let deepTimeout: TimeInterval = 3.0
    static let systemProfilerURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    static let digURL = URL(fileURLWithPath: "/usr/bin/dig")
    static let pingURL = URL(fileURLWithPath: "/sbin/ping")

    static func deep(runner: ProcessRunner) async -> ProbeResult<WifiDeep> {
        async let spR = runSystemProfiler(runner: runner)
        async let digR = runDig(runner: runner)
        async let pingR = runPing(runner: runner)
        let (sp, dig, ping) = await (spR, digR, pingR)

        guard case .value(let spOut) = sp else {
            return .failed("system_profiler did not return data")
        }
        let dnsMs: Double? = (dig.value).flatMap(parseDigMs)
        let gatewayMs: Double? = (ping.value).flatMap(parsePingAvgMs)

        return .value(WifiDeep(
            systemProfilerOutput: String(spOut.prefix(8192)),
            dnsTimingMs: dnsMs,
            gatewayPingMs: gatewayMs,
            traceroute: nil    // traceroute optional; skipped for v0.1 to keep deep gather <3s
        ))
    }

    private static func runSystemProfiler(runner: ProcessRunner) async -> ProbeResult<String> {
        do {
            let r = try await runner.run(
                executableURL: systemProfilerURL, arguments: ["SPAirPortDataType", "-detailLevel", "basic"],
                stdin: nil, timeout: deepTimeout)
            return r.exitCode == 0 ? .value(r.stdout) : .failed("exit \(r.exitCode)")
        } catch ProcessRunnerError.timedOut { return .timedOut }
        catch { return .failed("\(error)") }
    }

    private static func runDig(runner: ProcessRunner) async -> ProbeResult<String> {
        do {
            let r = try await runner.run(
                executableURL: digURL, arguments: ["+stats", "+tries=1", "+time=2", "apple.com"],
                stdin: nil, timeout: deepTimeout)
            return r.exitCode == 0 ? .value(r.stdout) : .failed("dig exit \(r.exitCode)")
        } catch { return .failed("\(error)") }
    }

    private static func runPing(runner: ProcessRunner) async -> ProbeResult<String> {
        // Resolve default gateway via `netstat -rn -f inet` parse — out of scope for v0.1.
        // Skip ping for v0.1; return unavailable so deep gather still succeeds.
        _ = runner
        return .unavailable
    }

    static func parseDigMs(_ s: String) -> Double? {
        if let range = s.range(of: #";; Query time: (\d+) msec"#, options: .regularExpression) {
            let digits = s[range].compactMap { $0.isNumber ? $0 : nil }
            return Double(String(digits))
        }
        return nil
    }

    static func parsePingAvgMs(_ s: String) -> Double? {
        // "round-trip min/avg/max/stddev = 1.234/2.345/3.456/0.123 ms"
        guard let range = s.range(of: #"min/avg/max/stddev = \S+"#, options: .regularExpression) else {
            return nil
        }
        let parts = s[range].split(separator: "=").last?.trimmingCharacters(in: .whitespaces)
                            .split(separator: "/")
        guard let parts = parts, parts.count >= 2 else { return nil }
        return Double(parts[1])
    }
}

extension ProbeResult {
    var value: T? { if case .value(let v) = self { return v }; return nil }
}
