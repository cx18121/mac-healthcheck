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
}
