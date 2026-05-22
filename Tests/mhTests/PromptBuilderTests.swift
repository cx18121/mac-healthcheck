import Testing
import Foundation
@testable import mh

@Suite("PromptBuilder")
struct PromptBuilderTests {

    @Test("triage prompt embeds JSON-encoded snapshot and identifies schema file")
    func triagePromptShape() throws {
        let snapshot = ShallowSnapshot(
            cpu: .value(CPUShallow(loadAverage: LoadAverage(oneMin: 4.2, fiveMin: 3.8, fifteenMin: 3.4), topProcesses: [])),
            wifi: .unavailable,
            disk: .value(DiskShallow(mounts: [])),
            battery: .value(BatteryShallow(percent: 80, onAC: false, charging: false, timeRemainingMinutes: 240)),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let result = try PromptBuilder.triage(snapshot)
        // Schema file exists and is readable
        let schemaData = try Data(contentsOf: result.schemaFile)
        let schemaJson = try JSONSerialization.jsonObject(with: schemaData) as! [String: Any]
        #expect((schemaJson["required"] as? [String])?.contains("domain") == true)
        // Prompt contains the snapshot JSON
        #expect(result.prompt.contains("\"cpu\""))
        #expect(result.prompt.contains("\"wifi\""))
        #expect(result.prompt.contains("unavailable"))
    }
}
