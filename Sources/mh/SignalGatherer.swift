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
            let r = await CPUGatherer.deep(runner: runner)
            if case .value(let d) = r {
                deep = .cpu(d)
            } else {
                deep = .cpu(CPUDeep(fullTopOutput: "(probe failed: \(r))",
                                    thermalPressure: "", uptimeSeconds: 0))
            }
        case .wifi, .disk, .battery:
            // Implemented in Task 16
            fatalError("deep gather not yet implemented for \(domain)")
        }
        return DeepSnapshot(domain: domain, shallow: shallow, deep: deep, deepTimestamp: Date())
    }
}
