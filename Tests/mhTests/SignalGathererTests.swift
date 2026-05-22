import Testing
import Foundation
@testable import mh

@Suite("SignalGatherer")
struct SignalGathererTests {

    private func fixturedRunner() -> FakeProcessRunner {
        func read(_ name: String) -> String {
            let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures")!
            return try! String(contentsOf: url, encoding: .utf8)
        }
        return FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(path: "/usr/bin/top",
                                  args: ["-l", "1", "-n", "5", "-stats", "pid,cpu,mem,command"]):
                .init(stdout: read("top_runaway_slack"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(
                path: "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport",
                args: ["-I"]):
                .init(stdout: read("airport_I_normal"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/usr/sbin/networksetup",
                                  args: ["-getairportnetwork", "en0"]):
                .init(stdout: read("networksetup_getairportnetwork"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/bin/df", args: ["-h"]):
                .init(stdout: read("df_h_normal"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/usr/bin/pmset", args: ["-g", "batt"]):
                .init(stdout: read("pmset_batt_ac"), stderr: "", exitCode: 0)
        ])
    }

    @Test("gatherShallow runs all four probes and returns populated snapshot")
    func gathersAllFour() async throws {
        let gatherer = SignalGatherer(runner: fixturedRunner())
        let snapshot = await gatherer.gatherShallow()
        #expect(snapshot.cpu.isOk)
        #expect(snapshot.wifi.isOk)
        #expect(snapshot.disk.isOk)
        #expect(snapshot.battery.isOk)
    }
}

extension ProbeResultBox {
    var isOk: Bool { if case .value = self { return true }; return false }
}
