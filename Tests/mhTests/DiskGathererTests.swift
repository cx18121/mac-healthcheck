import Testing
import Foundation
@testable import mh

@Suite("DiskGatherer (shallow)")
struct DiskGathererShallowTests {

    private func fixture(_ name: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures")!
        return try! String(contentsOf: url, encoding: .utf8)
    }

    @Test("parses df -h output, keeping only physical mounts")
    func parsesDfOutput() async throws {
        let runner = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(path: "/bin/df", args: ["-h"]):
                .init(stdout: fixture("df_h_normal"), stderr: "", exitCode: 0)
        ])
        let result = await DiskGatherer.shallow(runner: runner)
        guard case .value(let disk) = result else {
            Issue.record("expected .value, got \(result)"); return
        }
        // We keep only mounts the user cares about: /, /System/Volumes/Data
        #expect(disk.mounts.count >= 2)
        let root = disk.mounts.first(where: { $0.mountPoint == "/" })
        #expect(root?.percentFull == 4)
    }
}
