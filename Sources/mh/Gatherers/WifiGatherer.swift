@preconcurrency import CoreWLAN
import Foundation

struct CoreWLANSnapshot: Sendable {
    let ssid: String?
    let rssi: Int?
    let channel: Int?
    let linkRateMbps: Double?
}

enum WifiGatherer {

    typealias CoreWLANReader = @Sendable (String) -> CoreWLANSnapshot

    static let shallowTimeout: TimeInterval = 1.0  // networksetup is typically fast (<300ms); 1s headroom
    static let networksetupURL = URL(fileURLWithPath: "/usr/sbin/networksetup")

    /// Default reader pulls live values from the real CWWiFiClient. Tests inject their own.
    static let realCoreWLANReader: CoreWLANReader = { interface in
        let client = CWWiFiClient.shared()
        guard let iface = client.interface(withName: interface) else {
            return CoreWLANSnapshot(ssid: nil, rssi: nil, channel: nil, linkRateMbps: nil)
        }
        let rssi = iface.rssiValue()
        return CoreWLANSnapshot(
            ssid: iface.ssid(),
            rssi: rssi == 0 ? nil : rssi,
            channel: iface.wlanChannel()?.channelNumber,
            linkRateMbps: iface.transmitRate() > 0 ? iface.transmitRate() : nil
        )
    }

    static func shallow(
        runner: ProcessRunner,
        interface: String = "en0",
        coreWLANReader: CoreWLANReader? = nil
    ) async -> ProbeResult<WifiShallow> {
        let cw = (coreWLANReader ?? realCoreWLANReader)(interface)
        let networkR = await runNetworksetup(runner: runner, interface: interface)
        switch networkR {
        case .unavailable, .timedOut:
            // Even if networksetup is unavailable, return what CoreWLAN gave us (might be all nils).
            return .value(WifiShallow(
                ssid: cw.ssid, rssi: cw.rssi, channel: cw.channel,
                linkRateMbps: cw.linkRateMbps, interface: interface
            ))
        case .failed(let m):
            return .failed("networksetup: \(m)")
        case .value(let networkOut):
            // Prefer CoreWLAN's SSID (more reliable) but fall back to networksetup's parse.
            let nsSSID = parseNetworksetupSSID(networkOut)
            return .value(WifiShallow(
                ssid: cw.ssid ?? nsSSID,
                rssi: cw.rssi,
                channel: cw.channel,
                linkRateMbps: cw.linkRateMbps,
                interface: interface
            ))
        }
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

    private static func parseNetworksetupSSID(_ output: String) -> String? {
        let ssidLine = output.components(separatedBy: "\n")
            .first(where: { $0.contains("Current Wi-Fi Network:") })
        let ssid = ssidLine?
            .replacingOccurrences(of: "Current Wi-Fi Network:", with: "")
            .trimmingCharacters(in: .whitespaces)
        return (ssid?.isEmpty == false) ? ssid : nil
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
