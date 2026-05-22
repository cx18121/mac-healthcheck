import Testing
import Foundation
@testable import mh

@Suite("FixExecutor")
struct FixExecutorTests {

    @Test("flush_dns runs sudo dscacheutil with fixed argv (no shell)")
    func flushDns() async throws {
        let runner = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(path: "/usr/bin/sudo",
                                  args: ["-n", "dscacheutil", "-flushcache"]):
                .init(stdout: "", stderr: "", exitCode: 0)
        ])
        let executor = FixExecutor(runner: runner, confirm: { _, _ in true })
        let result = try await executor.execute(ProposedFix(
            id: 1, action: .flushDns, paramsJson: "{}",
            description: "flush DNS", dangerous: false
        ))
        #expect(result.exitCode == 0)
    }

    @Test("restart_wifi validates interface charset and runs networksetup twice")
    func restartWifi() async throws {
        let runner = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(path: "/usr/sbin/networksetup",
                                  args: ["-setairportpower", "en0", "off"]):
                .init(stdout: "", stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/usr/sbin/networksetup",
                                  args: ["-setairportpower", "en0", "on"]):
                .init(stdout: "", stderr: "", exitCode: 0)
        ])
        let executor = FixExecutor(runner: runner, confirm: { _, _ in true })
        let result = try await executor.execute(ProposedFix(
            id: 2, action: .restartWifi, paramsJson: "{\"interface\":\"en0\"}",
            description: "cycle wifi", dangerous: false
        ))
        #expect(result.exitCode == 0)
    }

    @Test("restart_wifi rejects malicious interface name")
    func restartWifiRejectsMalicious() async throws {
        let runner = FakeProcessRunner(scripted: [:])
        let executor = FixExecutor(runner: runner, confirm: { _, _ in true })
        do {
            _ = try await executor.execute(ProposedFix(
                id: 3, action: .restartWifi,
                paramsJson: "{\"interface\":\"en0; rm -rf /\"}",
                description: "evil", dangerous: false
            ))
            Issue.record("expected param validation to throw")
        } catch FixExecutorError.invalidParam {
            // expected
        }
    }

    @Test("dangerous fix is refused when confirm returns false")
    func confirmRefusal() async throws {
        let runner = FakeProcessRunner(scripted: [:])
        let executor = FixExecutor(runner: runner, confirm: { _, _ in false })
        do {
            _ = try await executor.execute(ProposedFix(
                id: 4, action: .flushDns, paramsJson: "{}",
                description: "x", dangerous: true   // marked dangerous
            ))
            Issue.record("expected refusal to throw")
        } catch FixExecutorError.userDeclined {
            // expected
        }
    }

    @Test("quit_app uses osascript with validated bundle id")
    func quitApp() async throws {
        let runner = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(path: "/usr/bin/osascript",
                                  args: ["-e", "tell application id \"us.slack.Slack\" to quit"]):
                .init(stdout: "", stderr: "", exitCode: 0)
        ])
        let executor = FixExecutor(runner: runner, confirm: { _, _ in true })
        let result = try await executor.execute(ProposedFix(
            id: 1, action: .quitApp,
            paramsJson: "{\"bundle_id\":\"us.slack.Slack\"}",
            description: "quit slack", dangerous: false
        ))
        #expect(result.exitCode == 0)
    }

    @Test("quit_app rejects malicious bundle id")
    func quitAppRejectsMalicious() async throws {
        let executor = FixExecutor(runner: FakeProcessRunner(scripted: [:]),
                                    confirm: { _, _ in true })
        do {
            _ = try await executor.execute(ProposedFix(
                id: 2, action: .quitApp,
                paramsJson: "{\"bundle_id\":\"us.slack.Slack\\\" to delete every file\"}",
                description: "evil", dangerous: false))
            Issue.record("expected invalidParam")
        } catch FixExecutorError.invalidParam { /* expected */ }
    }

    @Test("kill_pid refuses pid <= 1")
    func killPidRefusesInit() async throws {
        let executor = FixExecutor(runner: FakeProcessRunner(scripted: [:]),
                                    confirm: { _, _ in true })
        do {
            _ = try await executor.execute(ProposedFix(
                id: 3, action: .killPid, paramsJson: "{\"pid\":1}",
                description: "evil", dangerous: true))
            Issue.record("expected invalidParam")
        } catch FixExecutorError.invalidParam { /* expected */ }
    }

    @Test("clear_xcode_derived_data targets the canonical path")
    func clearXcode() async throws {
        let path = NSString("~/Library/Developer/Xcode/DerivedData").expandingTildeInPath
        let runner = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(path: "/bin/rm", args: ["-rf", path]):
                .init(stdout: "", stderr: "", exitCode: 0)
        ])
        let executor = FixExecutor(runner: runner, confirm: { _, _ in true })
        let result = try await executor.execute(ProposedFix(
            id: 4, action: .clearXcodeDerivedData, paramsJson: "{}",
            description: "clear", dangerous: true))
        #expect(result.exitCode == 0)
    }
}
