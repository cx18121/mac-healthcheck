import Testing
import Foundation
@testable import mh

@Suite("ChatLoop")
struct ChatLoopTests {

    @Test("parses 'run 2' into fix index 1")
    func parsesRunCommand() {
        #expect(ChatLoop.parseRunCommand("run 2") == 1)
        #expect(ChatLoop.parseRunCommand("run 0") == nil)         // 1-indexed
        #expect(ChatLoop.parseRunCommand("RUN 3") == 2)
        #expect(ChatLoop.parseRunCommand("not a command") == nil)
        #expect(ChatLoop.parseRunCommand("run abc") == nil)
        #expect(ChatLoop.parseRunCommand("exit") == nil)
    }
}
