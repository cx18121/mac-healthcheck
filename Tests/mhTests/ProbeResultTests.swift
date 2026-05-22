import Testing
@testable import mh

@Suite("ProbeResult")
struct ProbeResultTests {
    @Test("value case carries payload")
    func valueCarriesPayload() {
        let p: ProbeResult<Int> = .value(42)
        guard case .value(let n) = p else {
            Issue.record("expected .value"); return
        }
        #expect(n == 42)
    }

    @Test("isSuccess returns true only for .value")
    func isSuccessOnlyForValue() {
        #expect(ProbeResult<Int>.value(1).isSuccess)
        #expect(!ProbeResult<Int>.unavailable.isSuccess)
        #expect(!ProbeResult<Int>.timedOut.isSuccess)
        #expect(!ProbeResult<Int>.failed("boom").isSuccess)
    }

    @Test("Domain rawValues are stable lowercased names")
    func domainRawValues() {
        #expect(Domain.wifi.rawValue == "wifi")
        #expect(Domain.cpu.rawValue == "cpu")
        #expect(Domain.disk.rawValue == "disk")
        #expect(Domain.battery.rawValue == "battery")
    }
}
