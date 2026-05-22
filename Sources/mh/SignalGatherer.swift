import Foundation

struct SignalGatherer: Sendable {
    let runner: ProcessRunner

    init(runner: ProcessRunner = FoundationProcessRunner()) {
        self.runner = runner
    }

    func gatherShallow() async -> ShallowSnapshot {
        async let cpu = CPUGatherer.shallow(runner: runner)
        async let wifi = WifiGatherer.shallow(runner: runner)
        async let disk = DiskGatherer.shallow(runner: runner)
        async let battery = BatteryGatherer.shallow(runner: runner)
        let (c, w, d, b) = await (cpu, wifi, disk, battery)
        return ShallowSnapshot(
            cpu: ProbeResultBox(c),
            wifi: ProbeResultBox(w),
            disk: ProbeResultBox(d),
            battery: ProbeResultBox(b),
            timestamp: Date()
        )
    }

    func gatherDeep(_ domain: Domain, shallow: ShallowSnapshot) async -> DeepSnapshot {
        let deep: DeepData
        switch domain {
        case .cpu:
            if case .value(let d) = await CPUGatherer.deep(runner: runner) {
                deep = .cpu(d)
            } else {
                deep = .cpu(CPUDeep(fullTopOutput: "(deep probe failed)",
                                    thermalPressure: "", uptimeSeconds: 0))
            }
        case .wifi:
            if case .value(let d) = await WifiGatherer.deep(runner: runner) {
                deep = .wifi(d)
            } else {
                deep = .wifi(WifiDeep(systemProfilerOutput: "(deep probe failed)",
                                      dnsTimingMs: nil, gatewayPingMs: nil, traceroute: nil))
            }
        case .disk:
            if case .value(let d) = await DiskGatherer.deep(runner: runner) {
                deep = .disk(d)
            } else {
                deep = .disk(DiskDeep(topDirectories: [], purgeableGB: nil))
            }
        case .battery:
            if case .value(let d) = await BatteryGatherer.deep(runner: runner) {
                deep = .battery(d)
            } else {
                deep = .battery(BatteryDeep(pmsetGFull: "(deep probe failed)",
                                            powerHistory: "", cycleCount: nil))
            }
        }
        return DeepSnapshot(domain: domain, shallow: shallow, deep: deep, deepTimestamp: Date())
    }
}
