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
        case (.unavailable, _), (_, .unavailable):
            return .unavailable
        case (.timedOut, _), (_, .timedOut):
            return .timedOut
        case (.failed(let a), .failed(let b)):
            return .failed("airport: \(a); networksetup: \(b)")
        case (.failed(let m), _):
            return .failed("airport: \(m)")
        case (_, .failed(let m)):
            return .failed("networksetup: \(m)")
        case (.value(let airportOut), .value(let networkOut)):
            return parse(airport: airportOut, networksetup: networkOut, interface: interface)
        }
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
}
