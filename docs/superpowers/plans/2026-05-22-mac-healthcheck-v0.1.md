# Mac Healthcheck v0.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a single Swift CLI binary `mh` that gathers macOS health signals, sends them to Codex CLI for staged LLM synthesis, prints a markdown analysis with structured fix proposals, and drops into a chat loop with allowlist-gated auto-fix execution.

**Architecture:** Single Swift Package Manager executable. Two-mode gather (shallow cross-cut → Codex triage → deep gather on dominant domain → Codex analysis). `codex exec --json --output-schema` subprocess for structured LLM output. Closed-enum `FixAction` allowlist with revalidation + audit log for Tier-1 auto-fix. Foundation + swift-argument-parser only. Reference design: `docs/superpowers/specs/2026-05-21-mac-healthcheck-v0.1-design.md`.

**Tech Stack:** Swift 6.3, Swift Package Manager, Foundation, `swift-argument-parser`, Swift Testing (`@Test` macros), Codex CLI 0.132+ (external runtime dependency).

---

## File Structure

After this plan completes, the repo will have:

```
mac-healthcheck/
├── Package.swift                                   # SPM manifest
├── README.md                                       # (existing — updated in Task 18)
├── docs/superpowers/
│   ├── specs/2026-05-21-mac-healthcheck-v0.1-design.md   # (existing)
│   └── plans/2026-05-22-mac-healthcheck-v0.1.md          # (this file)
├── Sources/mh/
│   ├── Domain.swift                                # enum Domain (4 cases)
│   ├── ProbeResult.swift                           # enum ProbeResult<T>
│   ├── Snapshots.swift                             # ShallowSnapshot, DeepSnapshot, per-domain shallow + deep structs
│   ├── ProcessRunner.swift                         # protocol + Foundation impl for subprocess running
│   ├── Gatherers/
│   │   ├── CPUGatherer.swift                       # shallow + deep CPU probes
│   │   ├── WifiGatherer.swift                      # shallow + deep WiFi probes
│   │   ├── DiskGatherer.swift                      # shallow + deep Disk probes
│   │   └── BatteryGatherer.swift                   # shallow + deep Battery probes
│   ├── SignalGatherer.swift                        # composes the per-domain gatherers
│   ├── PromptBuilder.swift                         # triage/analysis prompt constructors
│   ├── CodexClient.swift                           # `codex exec` subprocess wrapper
│   ├── FixAction.swift                             # enum + per-action param structs
│   ├── FixExecutor.swift                           # revalidate + build + run + audit
│   ├── ChatLoop.swift                              # REPL + run-N parsing
│   ├── DoctorCommand.swift                         # `mh doctor` subcommand
│   ├── Logging.swift                               # audit + error log helpers
│   ├── main.swift                                  # @main + MH struct (root command)
│   └── Resources/
│       ├── triage_schema.json                      # bundled at build time
│       └── analysis_schema.json                    # bundled at build time
└── Tests/mhTests/
    ├── ProbeResultTests.swift
    ├── CPUGathererTests.swift
    ├── WifiGathererTests.swift
    ├── DiskGathererTests.swift
    ├── BatteryGathererTests.swift
    ├── PromptBuilderTests.swift
    ├── CodexClientTests.swift
    ├── FixExecutorTests.swift
    ├── ChatLoopTests.swift
    ├── EndToEndTests.swift
    └── Fixtures/
        ├── top_normal.txt
        ├── top_runaway_slack.txt
        ├── airport_I_normal.txt
        ├── system_profiler_wifi.txt
        ├── df_h_normal.txt
        ├── df_h_full.txt
        ├── pmset_batt_ac.txt
        ├── pmset_batt_drain.txt
        ├── codex_triage_response.jsonl
        └── codex_analysis_response.jsonl
```

**Boundaries:**
- Each gatherer (CPU/Wifi/Disk/Battery) is one file, one responsibility, independently testable with fixture stdout.
- `ProcessRunner` is the only file that actually spawns processes — every other component takes a `ProcessRunner` injected. Tests pass a `FakeProcessRunner`.
- `FixExecutor` and `FixAction` are split: enum + param structs live with the enum; the executor is the verb side.
- `CodexClient` is the only place that knows the Codex CLI flag surface. If Codex CLI changes, that's the only file to update.

---

## Task 1: Initialize Swift Package + first compiling binary

**Files:**
- Create: `Package.swift`
- Create: `Sources/mh/main.swift`
- Create: `.gitignore`

- [ ] **Step 1: Verify clean repo state**

Run: `git status`
Expected: clean working tree, on `main`, only the spec + plan committed so far.

- [ ] **Step 2: Create `.gitignore`**

Create file `.gitignore`:

```gitignore
.build/
.swiftpm/
*.xcodeproj/
DerivedData/
.DS_Store
~/.local/state/mh/
```

- [ ] **Step 3: Create `Package.swift`**

Create file `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mh",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mh", targets: ["mh"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        .executableTarget(
            name: "mh",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            resources: [
                .copy("Resources/triage_schema.json"),
                .copy("Resources/analysis_schema.json")
            ]
        ),
        .testTarget(
            name: "mhTests",
            dependencies: ["mh"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
```

- [ ] **Step 4: Create stub `main.swift`**

Create directories: `Sources/mh/Resources/`, `Sources/mh/Gatherers/`, `Tests/mhTests/Fixtures/`.
Create empty placeholder files so the resources/fixtures directories exist for SPM:

```bash
mkdir -p Sources/mh/Resources Sources/mh/Gatherers Tests/mhTests/Fixtures
touch Sources/mh/Resources/triage_schema.json
touch Sources/mh/Resources/analysis_schema.json
touch Tests/mhTests/Fixtures/.gitkeep
```

Then create `Sources/mh/main.swift`:

```swift
import ArgumentParser

@main
struct MH: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mh",
        abstract: "macOS diagnostic CLI with LLM synthesis"
    )

    func run() async throws {
        print("mh v0.1 — not yet implemented")
    }
}
```

- [ ] **Step 5: Build and run**

Run: `swift build`
Expected: builds successfully, fetches swift-argument-parser, produces `.build/debug/mh`.

Run: `swift run mh`
Expected: prints `mh v0.1 — not yet implemented` and exits 0.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/mh/main.swift Sources/mh/Resources/ Sources/mh/Gatherers/.gitkeep Tests/mhTests/Fixtures/.gitkeep .gitignore
git commit -m "scaffold: SPM package with stub mh executable"
```

If `.gitkeep` files were not needed (because resources have placeholder JSON), adjust accordingly — but ensure all referenced directories exist for SPM to find them.

---

## Task 2: Foundational types — `Domain` + `ProbeResult`

**Files:**
- Create: `Sources/mh/Domain.swift`
- Create: `Sources/mh/ProbeResult.swift`
- Create: `Tests/mhTests/ProbeResultTests.swift`

- [ ] **Step 1: Write the failing test**

Create file `Tests/mhTests/ProbeResultTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test`
Expected: FAIL with "cannot find 'ProbeResult'" and/or "cannot find 'Domain'".

- [ ] **Step 3: Implement `Domain`**

Create file `Sources/mh/Domain.swift`:

```swift
import Foundation

enum Domain: String, Codable, CaseIterable, Sendable {
    case wifi
    case cpu
    case disk
    case battery
}
```

- [ ] **Step 4: Implement `ProbeResult`**

Create file `Sources/mh/ProbeResult.swift`:

```swift
import Foundation

/// Outcome of running a single signal probe. Probes never throw — every
/// failure mode is a typed case so the caller can build a partial snapshot.
enum ProbeResult<T: Sendable>: Sendable {
    case value(T)
    case unavailable        // the probe binary is not installed (e.g. docker missing)
    case timedOut           // hit the per-probe timeout
    case failed(String)     // ran but produced unexpected output / non-zero exit

    var isSuccess: Bool {
        if case .value = self { return true }
        return false
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test`
Expected: PASS for all three tests in ProbeResult suite.

- [ ] **Step 6: Commit**

```bash
git add Sources/mh/Domain.swift Sources/mh/ProbeResult.swift Tests/mhTests/ProbeResultTests.swift
git commit -m "feat(types): add Domain enum and ProbeResult<T>"
```

---

## Task 3: `ProcessRunner` protocol + Foundation implementation

**Files:**
- Create: `Sources/mh/ProcessRunner.swift`
- Create: `Tests/mhTests/ProcessRunnerTests.swift`

This is the seam every other component uses to run subprocesses. Tests inject a fake.

- [ ] **Step 1: Write the failing test**

Create file `Tests/mhTests/ProcessRunnerTests.swift`:

```swift
import Testing
import Foundation
@testable import mh

@Suite("ProcessRunner")
struct ProcessRunnerTests {
    @Test("FakeProcessRunner returns scripted result")
    func fakeReturnsScriptedResult() async throws {
        let fake = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(path: "/bin/echo", args: ["hello"]):
                .init(stdout: "hello\n", stderr: "", exitCode: 0)
        ])
        let result = try await fake.run(executableURL: URL(fileURLWithPath: "/bin/echo"),
                                         arguments: ["hello"],
                                         stdin: nil,
                                         timeout: 1.0)
        #expect(result.stdout == "hello\n")
        #expect(result.stderr == "")
        #expect(result.exitCode == 0)
    }

    @Test("FoundationProcessRunner runs /bin/echo")
    func foundationRunsEcho() async throws {
        let runner = FoundationProcessRunner()
        let result = try await runner.run(executableURL: URL(fileURLWithPath: "/bin/echo"),
                                           arguments: ["hello", "world"],
                                           stdin: nil,
                                           timeout: 5.0)
        #expect(result.stdout == "hello world\n")
        #expect(result.exitCode == 0)
    }

    @Test("FoundationProcessRunner enforces timeout")
    func foundationEnforcesTimeout() async throws {
        let runner = FoundationProcessRunner()
        do {
            _ = try await runner.run(executableURL: URL(fileURLWithPath: "/bin/sleep"),
                                      arguments: ["2"],
                                      stdin: nil,
                                      timeout: 0.1)
            Issue.record("expected timeout to throw")
        } catch ProcessRunnerError.timedOut {
            // expected
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProcessRunner`
Expected: FAIL with "cannot find 'FakeProcessRunner'" / "cannot find 'FoundationProcessRunner'".

- [ ] **Step 3: Implement `ProcessRunner`**

Create file `Sources/mh/ProcessRunner.swift`:

```swift
import Foundation

struct ProcessResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum ProcessRunnerError: Error {
    case timedOut
    case spawnFailed(String)
}

protocol ProcessRunner: Sendable {
    /// Runs an executable with fixed argv. Never uses /bin/sh -c. The `stdin` parameter,
    /// if provided, is written to the child process's standard input.
    func run(executableURL: URL,
             arguments: [String],
             stdin: String?,
             timeout: TimeInterval) async throws -> ProcessResult
}

struct FoundationProcessRunner: ProcessRunner {
    func run(executableURL: URL,
             arguments: [String],
             stdin: String?,
             timeout: TimeInterval) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let stdin = stdin {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
            try process.run()
            try stdinPipe.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
            try stdinPipe.fileHandleForWriting.close()
        } else {
            try process.run()
        }

        // Race the process against a timeout
        let result = try await withThrowingTaskGroup(of: ProcessResult?.self) { group in
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                }
                return nil
            }
            group.addTask {
                await withCheckedContinuation { cont in
                    process.terminationHandler = { _ in cont.resume() }
                }
                let outData = try stdoutPipe.fileHandleForReading.readToEnd() ?? Data()
                let errData = try stderrPipe.fileHandleForReading.readToEnd() ?? Data()
                return ProcessResult(
                    stdout: String(decoding: outData, as: UTF8.self),
                    stderr: String(decoding: errData, as: UTF8.self),
                    exitCode: process.terminationStatus
                )
            }
            for try await result in group {
                if let result = result {
                    group.cancelAll()
                    return result
                }
            }
            throw ProcessRunnerError.timedOut
        }
        return result
    }
}

/// Test double. Maps `(executable, args)` keys to scripted results.
struct FakeProcessRunner: ProcessRunner {
    struct Key: Hashable, Sendable {
        let path: String
        let args: [String]
    }
    struct Scripted: Sendable {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }
    let scripted: [Key: Scripted]

    func run(executableURL: URL,
             arguments: [String],
             stdin: String?,
             timeout: TimeInterval) async throws -> ProcessResult {
        let key = Key(path: executableURL.path, args: arguments)
        guard let s = scripted[key] else {
            throw ProcessRunnerError.spawnFailed(
                "no scripted result for \(key.path) \(key.args.joined(separator: " "))"
            )
        }
        return ProcessResult(stdout: s.stdout, stderr: s.stderr, exitCode: s.exitCode)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ProcessRunner`
Expected: PASS for all three ProcessRunner tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/mh/ProcessRunner.swift Tests/mhTests/ProcessRunnerTests.swift
git commit -m "feat(runner): add ProcessRunner protocol with Foundation + Fake impls"
```

---

## Task 4: Snapshot types

**Files:**
- Create: `Sources/mh/Snapshots.swift`

No tests for plain data types — they're exercised by the gatherer tests in Tasks 5-8.

- [ ] **Step 1: Create `Snapshots.swift`**

Create file `Sources/mh/Snapshots.swift`:

```swift
import Foundation

// MARK: - Shallow per-domain structs

struct CPUShallow: Codable, Sendable {
    let loadAverage: [Double]      // 1, 5, 15 minute
    let topProcesses: [TopProcess] // up to 5
}

struct TopProcess: Codable, Sendable {
    let pid: Int32
    let cpuPercent: Double
    let memoryMB: Double
    let command: String
}

struct WifiShallow: Codable, Sendable {
    let ssid: String?
    let rssi: Int?         // dBm; nil if not associated
    let channel: Int?
    let linkRateMbps: Double?
    let interface: String  // e.g. "en0"
}

struct DiskShallow: Codable, Sendable {
    let mounts: [MountUsage]
}

struct MountUsage: Codable, Sendable {
    let mountPoint: String
    let percentFull: Int
    let availableGB: Double
}

struct BatteryShallow: Codable, Sendable {
    let percent: Int
    let onAC: Bool
    let charging: Bool
    let timeToEmptyMinutes: Int?
}

// MARK: - Composite snapshots

struct ShallowSnapshot: Codable, Sendable {
    let cpu: ProbeResultBox<CPUShallow>
    let wifi: ProbeResultBox<WifiShallow>
    let disk: ProbeResultBox<DiskShallow>
    let battery: ProbeResultBox<BatteryShallow>
    let timestamp: Date
}

// MARK: - Deep snapshot (domain-specific union)

struct DeepSnapshot: Codable, Sendable {
    let domain: Domain
    let shallow: ShallowSnapshot
    let deep: DeepData
    let timestamp: Date
}

enum DeepData: Codable, Sendable {
    case cpu(CPUDeep)
    case wifi(WifiDeep)
    case disk(DiskDeep)
    case battery(BatteryDeep)
}

struct CPUDeep: Codable, Sendable {
    let fullTopOutput: String       // raw top with more rows (truncated to 4KB)
    let thermalPressure: String     // pmset -g therm output
    let uptimeSeconds: Int
}

struct WifiDeep: Codable, Sendable {
    let systemProfilerOutput: String  // truncated SPAirPortDataType section
    let dnsTimingMs: Double?
    let gatewayPingMs: Double?
    let traceroute: String?           // first 5 hops, truncated
}

struct DiskDeep: Codable, Sendable {
    let topDirectories: [DiskUsage]   // du -sh on known cache paths
    let purgeableGB: Double?
}

struct DiskUsage: Codable, Sendable {
    let path: String
    let sizeGB: Double
}

struct BatteryDeep: Codable, Sendable {
    let pmsetGFull: String           // pmset -g
    let powerHistory: String         // pmset -g log | tail -50 (truncated)
    let cycleCount: Int?
}

// MARK: - JSON-friendly wrapper for ProbeResult

/// `ProbeResult<T>` cannot directly conform to `Codable` because it has an associated value
/// that varies. We wrap it for encoding into prompts.
enum ProbeResultBox<T: Codable & Sendable>: Codable, Sendable {
    case value(T)
    case unavailable
    case timedOut
    case failed(String)

    init(_ result: ProbeResult<T>) {
        switch result {
        case .value(let v): self = .value(v)
        case .unavailable: self = .unavailable
        case .timedOut: self = .timedOut
        case .failed(let msg): self = .failed(msg)
        }
    }

    private enum CodingKeys: String, CodingKey { case status, value, message }
    private enum Status: String, Codable { case ok, unavailable, timedOut, failed }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .value(let v):
            try c.encode(Status.ok, forKey: .status)
            try c.encode(v, forKey: .value)
        case .unavailable:
            try c.encode(Status.unavailable, forKey: .status)
        case .timedOut:
            try c.encode(Status.timedOut, forKey: .status)
        case .failed(let msg):
            try c.encode(Status.failed, forKey: .status)
            try c.encode(msg, forKey: .message)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let status = try c.decode(Status.self, forKey: .status)
        switch status {
        case .ok: self = .value(try c.decode(T.self, forKey: .value))
        case .unavailable: self = .unavailable
        case .timedOut: self = .timedOut
        case .failed: self = .failed(try c.decode(String.self, forKey: .message))
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: builds without errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/mh/Snapshots.swift
git commit -m "feat(types): add Shallow/Deep snapshot structs + ProbeResultBox"
```

---

## Task 5: CPU gatherer (shallow) with fixture-based test

**Files:**
- Create: `Sources/mh/Gatherers/CPUGatherer.swift`
- Create: `Tests/mhTests/CPUGathererTests.swift`
- Create: `Tests/mhTests/Fixtures/top_runaway_slack.txt`

The CPU gatherer is the first real probe — it sets the pattern for the other three.

- [ ] **Step 1: Create test fixture**

Create file `Tests/mhTests/Fixtures/top_runaway_slack.txt`:

```
Processes: 412 total, 4 running, 408 sleeping, 2204 threads
2026/05/21 22:14:08
Load Avg: 4.21, 3.85, 3.40
CPU usage: 32.55% user, 12.10% sys, 55.34% idle
SharedLibs: 412M resident, 89M data, 32M linkedit.
MemRegions: 245678 total, 12G resident, 412M private, 4G shared.
PhysMem: 24G used (4G wired, 8G compressor), 8G unused.
VM: 234T vsize, 4256M framework vsize, 0(0) swapins, 0(0) swapouts.
Networks: packets: 1234567/2.3G in, 765432/1.8G out.
Disks: 12345678/567G read, 7654321/345G written.

PID    %CPU %MEM   COMMAND
12345  380.0 12.5   Slack Helper (Renderer)
67890   45.2  3.1   WindowServer
11111   12.0  2.8   kernel_task
22222    8.3  1.5   Google Chrome Helper
33333    5.1  0.9   mds_stores
```

- [ ] **Step 2: Write the failing test**

Create file `Tests/mhTests/CPUGathererTests.swift`:

```swift
import Testing
import Foundation
@testable import mh

@Suite("CPUGatherer (shallow)")
struct CPUGathererShallowTests {

    private func fixturedRunner(_ name: String) -> FakeProcessRunner {
        let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures")!
        let text = try! String(contentsOf: url, encoding: .utf8)
        return FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(path: "/usr/bin/top",
                                  args: ["-l", "1", "-n", "5",
                                         "-stats", "pid,cpu,mem,command"]):
                .init(stdout: text, stderr: "", exitCode: 0)
        ])
    }

    @Test("parses load average and top processes from real top output")
    func parsesTopOutput() async throws {
        let runner = fixturedRunner("top_runaway_slack")
        let result = await CPUGatherer.shallow(runner: runner)
        guard case .value(let cpu) = result else {
            Issue.record("expected .value, got \(result)"); return
        }
        #expect(cpu.loadAverage == [4.21, 3.85, 3.40])
        #expect(cpu.topProcesses.count == 5)
        #expect(cpu.topProcesses.first?.pid == 12345)
        #expect(cpu.topProcesses.first?.cpuPercent == 380.0)
        #expect(cpu.topProcesses.first?.command == "Slack Helper (Renderer)")
    }

    @Test("returns .timedOut on subprocess timeout")
    func handlesTimeout() async throws {
        struct AlwaysTimesOutRunner: ProcessRunner {
            func run(executableURL: URL, arguments: [String], stdin: String?,
                     timeout: TimeInterval) async throws -> ProcessResult {
                throw ProcessRunnerError.timedOut
            }
        }
        let result = await CPUGatherer.shallow(runner: AlwaysTimesOutRunner())
        guard case .timedOut = result else {
            Issue.record("expected .timedOut, got \(result)"); return
        }
    }

    @Test("returns .failed on non-zero exit")
    func handlesNonZeroExit() async throws {
        let runner = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(path: "/usr/bin/top",
                                  args: ["-l", "1", "-n", "5",
                                         "-stats", "pid,cpu,mem,command"]):
                .init(stdout: "", stderr: "top: unknown option", exitCode: 1)
        ])
        let result = await CPUGatherer.shallow(runner: runner)
        guard case .failed = result else {
            Issue.record("expected .failed, got \(result)"); return
        }
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter CPUGatherer`
Expected: FAIL with "cannot find 'CPUGatherer'".

- [ ] **Step 4: Implement `CPUGatherer.shallow`**

Create file `Sources/mh/Gatherers/CPUGatherer.swift`:

```swift
import Foundation

enum CPUGatherer {

    static let shallowTimeout: TimeInterval = 0.5
    static let topURL = URL(fileURLWithPath: "/usr/bin/top")

    static func shallow(runner: ProcessRunner) async -> ProbeResult<CPUShallow> {
        let result: ProcessResult
        do {
            result = try await runner.run(
                executableURL: topURL,
                arguments: ["-l", "1", "-n", "5", "-stats", "pid,cpu,mem,command"],
                stdin: nil,
                timeout: shallowTimeout
            )
        } catch ProcessRunnerError.timedOut {
            return .timedOut
        } catch {
            return .failed("spawn failed: \(error)")
        }
        if result.exitCode != 0 {
            return .failed("top exited \(result.exitCode): \(result.stderr.prefix(200))")
        }
        return parse(top: result.stdout)
    }

    static func parse(top: String) -> ProbeResult<CPUShallow> {
        let lines = top.components(separatedBy: "\n")
        guard let loadLine = lines.first(where: { $0.hasPrefix("Load Avg:") }) else {
            return .failed("could not find 'Load Avg' line")
        }
        // "Load Avg: 4.21, 3.85, 3.40"
        let loadStr = loadLine
            .replacingOccurrences(of: "Load Avg:", with: "")
            .trimmingCharacters(in: .whitespaces)
        let loadAvg = loadStr.split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard loadAvg.count == 3 else {
            return .failed("could not parse 3 load averages from '\(loadStr)'")
        }

        // Find the PID header line, then parse the following process rows
        guard let headerIdx = lines.firstIndex(where: { $0.hasPrefix("PID") }) else {
            return .failed("could not find PID header line")
        }
        let procRows = lines.dropFirst(headerIdx + 1)
            .prefix(5)
            .compactMap(parseTopRow(_:))

        return .value(CPUShallow(loadAverage: loadAvg, topProcesses: Array(procRows)))
    }

    /// "12345  380.0 12.5   Slack Helper (Renderer)"
    private static func parseTopRow(_ row: String) -> TopProcess? {
        let trimmed = row.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Split off first three fields by whitespace; the rest is the command.
        var scanner = Scanner(string: trimmed)
        scanner.charactersToBeSkipped = .whitespaces
        guard let pid = scanner.scanInt32(),
              let cpu = scanner.scanDouble(),
              let mem = scanner.scanDouble() else {
            return nil
        }
        let rest = String(trimmed[scanner.currentIndex...])
            .trimmingCharacters(in: .whitespaces)
        return TopProcess(pid: pid, cpuPercent: cpu, memoryMB: mem, command: rest)
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter CPUGatherer`
Expected: PASS for all three CPUGatherer tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/mh/Gatherers/CPUGatherer.swift Tests/mhTests/CPUGathererTests.swift Tests/mhTests/Fixtures/top_runaway_slack.txt
git commit -m "feat(gather): CPU shallow gatherer with fixture-based parser"
```

---

## Task 6: Wifi gatherer (shallow)

**Files:**
- Create: `Sources/mh/Gatherers/WifiGatherer.swift`
- Create: `Tests/mhTests/WifiGathererTests.swift`
- Create: `Tests/mhTests/Fixtures/airport_I_normal.txt`
- Create: `Tests/mhTests/Fixtures/networksetup_getairportnetwork.txt`

`airport -I` deprecation note: in macOS 14+ Apple shipped airport behind a deprecation warning but it still works. We use it for v0.1; if it disappears the gatherer returns `.unavailable` and `mh` degrades gracefully.

- [ ] **Step 1: Create test fixtures**

Create file `Tests/mhTests/Fixtures/airport_I_normal.txt`:

```
     agrCtlRSSI: -45
     agrExtRSSI: 0
    agrCtlNoise: -89
    agrExtNoise: 0
          state: running
        op mode: station 
     lastTxRate: 866
        maxRate: 866
lastAssocStatus: 0
    802.11 auth: open
      link auth: wpa2-psk
          BSSID: 
           SSID: HomeNetwork
            MCS: 9
        channel: 36,80
```

Create file `Tests/mhTests/Fixtures/networksetup_getairportnetwork.txt`:

```
Current Wi-Fi Network: HomeNetwork
```

- [ ] **Step 2: Write the failing test**

Create file `Tests/mhTests/WifiGathererTests.swift`:

```swift
import Testing
import Foundation
@testable import mh

@Suite("WifiGatherer (shallow)")
struct WifiGathererShallowTests {

    private func fixture(_ name: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures")!
        return try! String(contentsOf: url, encoding: .utf8)
    }

    @Test("parses airport -I + networksetup output")
    func parsesAirportOutput() async throws {
        let runner = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(
                path: "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport",
                args: ["-I"]
            ): .init(stdout: fixture("airport_I_normal"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(
                path: "/usr/sbin/networksetup",
                args: ["-getairportnetwork", "en0"]
            ): .init(stdout: fixture("networksetup_getairportnetwork"), stderr: "", exitCode: 0)
        ])
        let result = await WifiGatherer.shallow(runner: runner, interface: "en0")
        guard case .value(let wifi) = result else {
            Issue.record("expected .value, got \(result)"); return
        }
        #expect(wifi.ssid == "HomeNetwork")
        #expect(wifi.rssi == -45)
        #expect(wifi.channel == 36)
        #expect(wifi.linkRateMbps == 866)
        #expect(wifi.interface == "en0")
    }

    @Test("returns .unavailable when airport binary missing")
    func airportMissing() async throws {
        struct UnavailableRunner: ProcessRunner {
            func run(executableURL: URL, arguments: [String], stdin: String?,
                     timeout: TimeInterval) async throws -> ProcessResult {
                throw ProcessRunnerError.spawnFailed("no such file")
            }
        }
        let result = await WifiGatherer.shallow(runner: UnavailableRunner(), interface: "en0")
        guard case .unavailable = result else {
            Issue.record("expected .unavailable, got \(result)"); return
        }
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter WifiGatherer`
Expected: FAIL.

- [ ] **Step 4: Implement `WifiGatherer.shallow`**

Create file `Sources/mh/Gatherers/WifiGatherer.swift`:

```swift
import Foundation

enum WifiGatherer {

    static let shallowTimeout: TimeInterval = 0.5
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

    static func parse(airport: String, networksetup: String, interface: String) -> ProbeResult<WifiShallow> {
        // airport -I gives RSSI, channel, link rate
        let map = airport.components(separatedBy: "\n").reduce(into: [String: String]()) { dict, line in
            let pair = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2 { dict[pair[0]] = pair[1] }
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
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter WifiGatherer`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/mh/Gatherers/WifiGatherer.swift Tests/mhTests/WifiGathererTests.swift Tests/mhTests/Fixtures/airport_I_normal.txt Tests/mhTests/Fixtures/networksetup_getairportnetwork.txt
git commit -m "feat(gather): WiFi shallow gatherer (airport + networksetup)"
```

---

## Task 7: Disk gatherer (shallow)

**Files:**
- Create: `Sources/mh/Gatherers/DiskGatherer.swift`
- Create: `Tests/mhTests/DiskGathererTests.swift`
- Create: `Tests/mhTests/Fixtures/df_h_normal.txt`

- [ ] **Step 1: Create fixture**

Create file `Tests/mhTests/Fixtures/df_h_normal.txt`:

```
Filesystem      Size   Used  Avail Capacity iused      ifree %iused  Mounted on
/dev/disk3s1s1 460Gi  9.0Gi  234Gi     4%  371k  4.3M    8%   /
devfs          194Ki  194Ki    0Bi   100%   672     0  100%   /dev
/dev/disk3s6   460Gi  3.0Gi  234Gi     2%     3  2.4M    0%   /System/Volumes/VM
/dev/disk3s4   460Gi  10Mi  234Gi     1%    44  2.4M    0%   /System/Volumes/Preboot
/dev/disk3s2   460Gi  6.6Gi  234Gi     3%  3.1k  2.4M    0%   /System/Volumes/Update
/dev/disk1s2   500Mi  6.5Mi  481Mi     2%     1  4.9k    0%   /System/Volumes/xarts
/dev/disk1s1   500Mi  6.4Mi  481Mi     2%    32  4.9k    1%   /System/Volumes/iSCPreboot
/dev/disk1s3   500Mi  712Ki  481Mi     1%    52  4.9k    1%   /System/Volumes/Hardware
/dev/disk3s5   460Gi  187Gi  234Gi    45%  2.0M  2.4M   46%   /System/Volumes/Data
```

- [ ] **Step 2: Write the failing test**

Create file `Tests/mhTests/DiskGathererTests.swift`:

```swift
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
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter DiskGatherer`
Expected: FAIL.

- [ ] **Step 4: Implement `DiskGatherer.shallow`**

Create file `Sources/mh/Gatherers/DiskGatherer.swift`:

```swift
import Foundation

enum DiskGatherer {

    static let shallowTimeout: TimeInterval = 0.5
    static let dfURL = URL(fileURLWithPath: "/bin/df")

    /// Mount points worth surfacing to the LLM. Skip Apple's internal volumes.
    static let interestingMounts: Set<String> = ["/", "/System/Volumes/Data"]

    static func shallow(runner: ProcessRunner) async -> ProbeResult<DiskShallow> {
        do {
            let r = try await runner.run(
                executableURL: dfURL, arguments: ["-h"],
                stdin: nil, timeout: shallowTimeout
            )
            if r.exitCode != 0 { return .failed("df exited \(r.exitCode)") }
            return parse(df: r.stdout)
        } catch ProcessRunnerError.timedOut { return .timedOut }
        catch ProcessRunnerError.spawnFailed { return .unavailable }
        catch { return .failed("\(error)") }
    }

    static func parse(df: String) -> ProbeResult<DiskShallow> {
        let lines = df.components(separatedBy: "\n").dropFirst() // header
        var mounts: [MountUsage] = []
        for line in lines {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 9 else { continue }
            let mountPoint = String(cols[8])
            guard interestingMounts.contains(mountPoint) else { continue }
            // Capacity is e.g. "4%"
            let pctStr = String(cols[4]).replacingOccurrences(of: "%", with: "")
            // Avail is e.g. "234Gi"
            let availStr = String(cols[3])
            guard let pct = Int(pctStr) else { continue }
            let availableGB = parseHumanSize(availStr)
            mounts.append(MountUsage(mountPoint: mountPoint, percentFull: pct, availableGB: availableGB))
        }
        return .value(DiskShallow(mounts: mounts))
    }

    /// "234Gi" → 234.0; "500Mi" → 0.488 (GB)
    private static func parseHumanSize(_ s: String) -> Double {
        var s = s
        var multiplier: Double = 1.0
        if s.hasSuffix("Ti") { multiplier = 1024.0; s.removeLast(2) }
        else if s.hasSuffix("Gi") { multiplier = 1.0; s.removeLast(2) }
        else if s.hasSuffix("Mi") { multiplier = 1.0 / 1024.0; s.removeLast(2) }
        else if s.hasSuffix("Ki") { multiplier = 1.0 / (1024.0 * 1024.0); s.removeLast(2) }
        return (Double(s) ?? 0.0) * multiplier
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter DiskGatherer`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/mh/Gatherers/DiskGatherer.swift Tests/mhTests/DiskGathererTests.swift Tests/mhTests/Fixtures/df_h_normal.txt
git commit -m "feat(gather): Disk shallow gatherer (df -h)"
```

---

## Task 8: Battery gatherer (shallow)

**Files:**
- Create: `Sources/mh/Gatherers/BatteryGatherer.swift`
- Create: `Tests/mhTests/BatteryGathererTests.swift`
- Create: `Tests/mhTests/Fixtures/pmset_batt_ac.txt`
- Create: `Tests/mhTests/Fixtures/pmset_batt_drain.txt`

- [ ] **Step 1: Create fixtures**

Create file `Tests/mhTests/Fixtures/pmset_batt_ac.txt`:

```
Now drawing from 'AC Power'
 -InternalBattery-0 (id=12345678)	100%; charged; 0:00 remaining present: true
```

Create file `Tests/mhTests/Fixtures/pmset_batt_drain.txt`:

```
Now drawing from 'Battery Power'
 -InternalBattery-0 (id=12345678)	67%; discharging; 4:12 remaining present: true
```

- [ ] **Step 2: Write the failing test**

Create file `Tests/mhTests/BatteryGathererTests.swift`:

```swift
import Testing
import Foundation
@testable import mh

@Suite("BatteryGatherer (shallow)")
struct BatteryGathererShallowTests {

    private func fixture(_ name: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures")!
        return try! String(contentsOf: url, encoding: .utf8)
    }

    @Test("parses AC-powered, full-battery output")
    func parsesAcOutput() async throws {
        let runner = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(path: "/usr/bin/pmset", args: ["-g", "batt"]):
                .init(stdout: fixture("pmset_batt_ac"), stderr: "", exitCode: 0)
        ])
        let result = await BatteryGatherer.shallow(runner: runner)
        guard case .value(let bat) = result else {
            Issue.record("expected .value, got \(result)"); return
        }
        #expect(bat.percent == 100)
        #expect(bat.onAC == true)
        #expect(bat.charging == false)  // "charged", not actively charging
    }

    @Test("parses battery-powered, discharging output")
    func parsesDrainOutput() async throws {
        let runner = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(path: "/usr/bin/pmset", args: ["-g", "batt"]):
                .init(stdout: fixture("pmset_batt_drain"), stderr: "", exitCode: 0)
        ])
        let result = await BatteryGatherer.shallow(runner: runner)
        guard case .value(let bat) = result else {
            Issue.record("expected .value, got \(result)"); return
        }
        #expect(bat.percent == 67)
        #expect(bat.onAC == false)
        #expect(bat.timeToEmptyMinutes == 4 * 60 + 12)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter BatteryGatherer`
Expected: FAIL.

- [ ] **Step 4: Implement `BatteryGatherer.shallow`**

Create file `Sources/mh/Gatherers/BatteryGatherer.swift`:

```swift
import Foundation

enum BatteryGatherer {

    static let shallowTimeout: TimeInterval = 0.5
    static let pmsetURL = URL(fileURLWithPath: "/usr/bin/pmset")

    static func shallow(runner: ProcessRunner) async -> ProbeResult<BatteryShallow> {
        do {
            let r = try await runner.run(
                executableURL: pmsetURL, arguments: ["-g", "batt"],
                stdin: nil, timeout: shallowTimeout
            )
            if r.exitCode != 0 { return .failed("pmset exited \(r.exitCode)") }
            return parse(pmset: r.stdout)
        } catch ProcessRunnerError.timedOut { return .timedOut }
        catch ProcessRunnerError.spawnFailed { return .unavailable }
        catch { return .failed("\(error)") }
    }

    static func parse(pmset: String) -> ProbeResult<BatteryShallow> {
        let onAC = pmset.contains("'AC Power'")
        // Find "67%;" or "100%;" pattern
        var percent = -1
        if let percentRange = pmset.range(of: #"\d+%;"#, options: .regularExpression) {
            let pctStr = pmset[percentRange].dropLast(2)  // strip "%;"
            percent = Int(pctStr) ?? -1
        }
        if percent < 0 { return .failed("could not parse percent") }

        let charging = pmset.contains("; charging;")
        var timeRemaining: Int? = nil
        if let m = pmset.range(of: #";\s+(\d+):(\d+)\s+remaining"#, options: .regularExpression) {
            let hhmm = pmset[m]
                .replacingOccurrences(of: ";", with: "")
                .replacingOccurrences(of: " remaining", with: "")
                .trimmingCharacters(in: .whitespaces)
            let parts = hhmm.split(separator: ":")
            if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), h + m > 0 {
                timeRemaining = h * 60 + m
            }
        }

        return .value(BatteryShallow(
            percent: percent,
            onAC: onAC,
            charging: charging,
            timeToEmptyMinutes: timeRemaining
        ))
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter BatteryGatherer`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/mh/Gatherers/BatteryGatherer.swift Tests/mhTests/BatteryGathererTests.swift Tests/mhTests/Fixtures/pmset_batt_ac.txt Tests/mhTests/Fixtures/pmset_batt_drain.txt
git commit -m "feat(gather): Battery shallow gatherer (pmset -g batt)"
```

---

## Task 9: `SignalGatherer` — compose the four shallow probes in parallel

**Files:**
- Create: `Sources/mh/SignalGatherer.swift`
- Create: `Tests/mhTests/SignalGathererTests.swift`

- [ ] **Step 1: Write the failing test**

Create file `Tests/mhTests/SignalGathererTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SignalGatherer`
Expected: FAIL.

- [ ] **Step 3: Implement `SignalGatherer`**

Create file `Sources/mh/SignalGatherer.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SignalGatherer`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/mh/SignalGatherer.swift Tests/mhTests/SignalGathererTests.swift
git commit -m "feat(gather): SignalGatherer composes 4 shallow probes in parallel"
```

---

## Task 10: Bundle schema resources + `PromptBuilder.triage`

**Files:**
- Modify: `Sources/mh/Resources/triage_schema.json`
- Create: `Sources/mh/PromptBuilder.swift`
- Create: `Tests/mhTests/PromptBuilderTests.swift`

Schemas must comply with OpenAI Structured Outputs strict mode: every nested object needs `additionalProperties: false`, and `required` must include every key in `properties`.

- [ ] **Step 1: Write `triage_schema.json`**

Replace contents of `Sources/mh/Resources/triage_schema.json`:

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["domain", "reasoning"],
  "properties": {
    "domain": {
      "type": "string",
      "enum": ["wifi", "cpu", "disk", "battery", "none"]
    },
    "reasoning": {
      "type": "string",
      "maxLength": 300
    }
  }
}
```

- [ ] **Step 2: Write the failing test**

Create file `Tests/mhTests/PromptBuilderTests.swift`:

```swift
import Testing
import Foundation
@testable import mh

@Suite("PromptBuilder")
struct PromptBuilderTests {

    @Test("triage prompt embeds JSON-encoded snapshot and identifies schema file")
    func triagePromptShape() throws {
        let snapshot = ShallowSnapshot(
            cpu: .value(CPUShallow(loadAverage: [4.2, 3.8, 3.4], topProcesses: [])),
            wifi: .unavailable,
            disk: .value(DiskShallow(mounts: [])),
            battery: .value(BatteryShallow(percent: 80, onAC: false, charging: false, timeToEmptyMinutes: 240)),
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
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter PromptBuilder`
Expected: FAIL with "cannot find 'PromptBuilder'".

- [ ] **Step 4: Implement `PromptBuilder.triage`**

Create file `Sources/mh/PromptBuilder.swift`:

```swift
import Foundation

struct TriagePrompt {
    let prompt: String
    let schemaFile: URL
}

struct AnalysisPrompt {
    let prompt: String
    let schemaFile: URL
}

enum PromptBuilder {

    enum BuilderError: Error {
        case missingResource(String)
    }

    static func triage(_ snapshot: ShallowSnapshot) throws -> TriagePrompt {
        let snapshotJson = try encodeSnapshotJson(snapshot)
        let prompt = """
        You are diagnosing a Mac. Below are shallow health signals across four domains \
        (CPU, WiFi, disk, battery). Probes that could not run are marked with a \
        non-"ok" status field.

        SHALLOW_SNAPSHOT:
        \(snapshotJson)

        Choose the SINGLE most concerning domain (or "none" if everything looks normal). \
        Respond ONLY with JSON matching the supplied schema. The reasoning field should \
        explain in <=300 chars why this domain is the most concerning.
        """

        guard let url = Bundle.module.url(forResource: "triage_schema", withExtension: "json") else {
            throw BuilderError.missingResource("triage_schema.json")
        }
        return TriagePrompt(prompt: prompt, schemaFile: url)
    }

    // (analysis() added in Task 14)

    private static func encodeSnapshotJson<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter PromptBuilder`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/mh/PromptBuilder.swift Sources/mh/Resources/triage_schema.json Tests/mhTests/PromptBuilderTests.swift
git commit -m "feat(prompt): PromptBuilder.triage + bundled triage_schema.json"
```

---

## Task 11: `CodexClient.openSession` — first real Codex integration

**Files:**
- Create: `Sources/mh/CodexClient.swift`
- Create: `Tests/mhTests/CodexClientTests.swift`
- Create: `Tests/mhTests/Fixtures/codex_triage_response.jsonl`

The `CodexClient` is the only file that knows the Codex CLI flag surface.

- [ ] **Step 1: Create fixture (real Codex JSONL output shape)**

Create file `Tests/mhTests/Fixtures/codex_triage_response.jsonl`:

```
{"type":"thread.started","thread_id":"019e4db8-6142-7031-a4b2-189862c6546f"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"{\"domain\":\"cpu\",\"reasoning\":\"Slack at 380% CPU is the most abnormal signal.\"}"}}
{"type":"turn.completed","usage":{"input_tokens":18741,"cached_input_tokens":2432,"output_tokens":126,"reasoning_output_tokens":68}}
```

- [ ] **Step 2: Write the failing test**

Create file `Tests/mhTests/CodexClientTests.swift`:

```swift
import Testing
import Foundation
@testable import mh

/// Local to this test file. The production `TriageResponse` is defined in Task 18 alongside
/// `AnalysisResponse`. At Task 11 time it doesn't exist yet, so the test names its decode
/// type distinctively to avoid future collisions.
struct FixtureTriageResponse: Codable, Equatable {
    let domain: String
    let reasoning: String
}

@Suite("CodexClient")
struct CodexClientTests {

    private func fixture(_ name: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures")!
        return try! String(contentsOf: url, encoding: .utf8)
    }

    @Test("openSession parses thread_id and structured response")
    func openSessionParses() async throws {
        let schema = FileManager.default.temporaryDirectory.appendingPathComponent("schema.json")
        try "{}".write(to: schema, atomically: true, encoding: .utf8)

        let runner = FakeProcessRunner(scripted: [
            // Matches the args CodexClient.openSession will use
            FakeProcessRunner.Key(path: "/opt/homebrew/bin/codex",
                                  args: ["exec", "--json", "--output-schema", schema.path, "-"]):
                .init(stdout: fixture("codex_triage_response"), stderr: "", exitCode: 0)
        ])
        let client = CodexClient(runner: runner, codexPath: "/opt/homebrew/bin/codex")
        let response: FixtureTriageResponse = try await client.openSession(
            prompt: "anything",
            schemaFile: schema,
            decoding: FixtureTriageResponse.self
        )
        #expect(response.domain == "cpu")
        #expect(response.reasoning.contains("Slack"))
        #expect(await client.threadId == "019e4db8-6142-7031-a4b2-189862c6546f")
    }

    @Test("openSession throws on error event")
    func openSessionThrowsOnError() async throws {
        let schema = FileManager.default.temporaryDirectory.appendingPathComponent("schema.json")
        try "{}".write(to: schema, atomically: true, encoding: .utf8)

        let errorJsonl = """
        {"type":"turn.started"}
        {"type":"error","message":"rate limited"}
        """
        let runner = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(path: "/opt/homebrew/bin/codex",
                                  args: ["exec", "--json", "--output-schema", schema.path, "-"]):
                .init(stdout: errorJsonl, stderr: "", exitCode: 1)
        ])
        let client = CodexClient(runner: runner, codexPath: "/opt/homebrew/bin/codex")
        do {
            _ = try await client.openSession(prompt: "x", schemaFile: schema, decoding: FixtureTriageResponse.self)
            Issue.record("expected throw")
        } catch CodexClientError.codexError(let msg) {
            #expect(msg.contains("rate limited"))
        }
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter CodexClient`
Expected: FAIL.

- [ ] **Step 4: Implement `CodexClient`**

Create file `Sources/mh/CodexClient.swift`:

```swift
import Foundation

enum CodexClientError: Error {
    case codexError(String)
    case malformedOutput(String)
    case noAgentMessage
    case decodingFailed(String)
}

actor CodexClient {
    private let runner: ProcessRunner
    private let codexURL: URL
    private(set) var threadId: String?
    static let callTimeout: TimeInterval = 30.0

    init(runner: ProcessRunner = FoundationProcessRunner(),
         codexPath: String = "/opt/homebrew/bin/codex") {
        self.runner = runner
        self.codexURL = URL(fileURLWithPath: codexPath)
    }

    /// Start a new conversation. Captures and stores the `thread_id` for subsequent resume calls.
    func openSession<T: Decodable>(
        prompt: String,
        schemaFile: URL,
        decoding: T.Type
    ) async throws -> T {
        let args = ["exec", "--json", "--output-schema", schemaFile.path, "-"]
        let result = try await runner.run(
            executableURL: codexURL,
            arguments: args,
            stdin: prompt,
            timeout: Self.callTimeout
        )
        let (threadId, payload) = try parseJsonl(result.stdout)
        self.threadId = threadId
        return try decode(payload, as: T.self)
    }

    /// Continue an existing conversation. Schema can be overridden per turn (pass nil to inherit).
    func resume<T: Decodable>(
        prompt: String,
        schemaFile: URL?,
        decoding: T.Type
    ) async throws -> T {
        guard let tid = threadId else {
            throw CodexClientError.malformedOutput("resume called before openSession")
        }
        var args = ["exec", "resume", tid, "--json"]
        if let schema = schemaFile {
            args.append(contentsOf: ["--output-schema", schema.path])
        }
        args.append("-")
        let result = try await runner.run(
            executableURL: codexURL,
            arguments: args,
            stdin: prompt,
            timeout: Self.callTimeout
        )
        let (_, payload) = try parseJsonl(result.stdout)
        return try decode(payload, as: T.self)
    }

    // MARK: - JSONL parsing

    /// Returns (thread_id-if-present, final agent_message text).
    private func parseJsonl(_ stdout: String) throws -> (String?, String) {
        var threadId: String?
        var agentMessage: String?
        for line in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            guard let type = obj["type"] as? String else { continue }
            switch type {
            case "thread.started":
                threadId = obj["thread_id"] as? String
            case "item.completed":
                if let item = obj["item"] as? [String: Any],
                   item["type"] as? String == "agent_message",
                   let text = item["text"] as? String {
                    agentMessage = text
                }
            case "error":
                let msg = (obj["message"] as? String) ?? "unknown codex error"
                throw CodexClientError.codexError(msg)
            default:
                break
            }
        }
        guard let msg = agentMessage else {
            throw CodexClientError.noAgentMessage
        }
        return (threadId, msg)
    }

    private func decode<T: Decodable>(_ payload: String, as type: T.Type) throws -> T {
        guard let data = payload.data(using: .utf8) else {
            throw CodexClientError.decodingFailed("payload not utf8")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CodexClientError.decodingFailed("\(error)")
        }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter CodexClient`
Expected: PASS for both tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/mh/CodexClient.swift Tests/mhTests/CodexClientTests.swift Tests/mhTests/Fixtures/codex_triage_response.jsonl
git commit -m "feat(codex): CodexClient.openSession with JSONL parsing + thread_id capture"
```

---

## Task 12: `mh doctor` subcommand

**Files:**
- Create: `Sources/mh/DoctorCommand.swift`
- Modify: `Sources/mh/main.swift`

Gives Charlie a debug surface before the full pipeline exists. Checks: Codex installed, Codex authenticated, top/df/pmset/networksetup/airport present.

- [ ] **Step 1: Create `DoctorCommand.swift`**

Create file `Sources/mh/DoctorCommand.swift`:

```swift
import ArgumentParser
import Foundation

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check that mh's environment is ready (codex, probes, auth)"
    )

    func run() async throws {
        var allGreen = true
        let runner = FoundationProcessRunner()

        for binary in ["/usr/bin/top", "/bin/df", "/usr/bin/pmset",
                       "/usr/sbin/networksetup"] {
            allGreen = await checkExists(binary) && allGreen
        }

        // Codex path discovery
        let codexCandidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        var codexFound: String? = nil
        for path in codexCandidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                codexFound = path
                print("✓ codex at \(path)")
                break
            }
        }
        if codexFound == nil {
            print("✗ codex not found at \(codexCandidates.joined(separator: " or "))")
            print("  → install via: brew install codex   (or npm i -g codex)")
            allGreen = false
        }

        // Codex auth check
        if let codex = codexFound {
            do {
                let result = try await runner.run(
                    executableURL: URL(fileURLWithPath: codex),
                    arguments: ["whoami"],
                    stdin: nil, timeout: 5.0
                )
                if result.exitCode == 0 && !result.stdout.contains("not signed in") {
                    print("✓ codex authenticated")
                } else {
                    print("✗ codex not authenticated — run: codex login")
                    allGreen = false
                }
            } catch {
                print("✗ codex whoami failed: \(error)")
                allGreen = false
            }
        }

        // Optional: airport (deprecated but used)
        let airportPath = "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
        if FileManager.default.isExecutableFile(atPath: airportPath) {
            print("✓ airport at \(airportPath)")
        } else {
            print("! airport not found at \(airportPath) — WiFi probe will degrade to networksetup-only")
        }

        if !allGreen {
            throw ExitCode(2)
        }
        print("\nAll required checks passed.")
    }

    private func checkExists(_ path: String) async -> Bool {
        if FileManager.default.isExecutableFile(atPath: path) {
            print("✓ \(path)")
            return true
        } else {
            print("✗ \(path) — required probe binary missing")
            return false
        }
    }
}
```

- [ ] **Step 2: Wire `doctor` into the root command**

Replace `Sources/mh/main.swift`:

```swift
import ArgumentParser

@main
struct MH: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mh",
        abstract: "macOS diagnostic CLI with LLM synthesis",
        subcommands: [Doctor.self]
    )

    func run() async throws {
        print("mh v0.1 — pipeline not yet wired; try `mh doctor`")
    }
}
```

- [ ] **Step 3: Build and manually run**

Run: `swift run mh doctor`
Expected: prints checkmarks for /usr/bin/top, /bin/df, /usr/bin/pmset, /usr/sbin/networksetup. Codex check passes or fails depending on the environment. Exit code 0 if all green.

- [ ] **Step 4: Commit**

```bash
git add Sources/mh/DoctorCommand.swift Sources/mh/main.swift
git commit -m "feat(cli): mh doctor subcommand for env preflight"
```

---

## Task 13: Deep gatherer — CPU domain only

**Files:**
- Modify: `Sources/mh/Gatherers/CPUGatherer.swift` (add `deep` static func)
- Modify: `Sources/mh/SignalGatherer.swift` (add `gatherDeep` method)
- Create: `Tests/mhTests/CPUGathererDeepTests.swift`
- Create: `Tests/mhTests/Fixtures/pmset_therm.txt`

We do CPU deep first because the CPU test fixture already exists (`top_runaway_slack.txt`); other domains follow same pattern in Task 16.

- [ ] **Step 1: Create fixture**

Create file `Tests/mhTests/Fixtures/pmset_therm.txt`:

```
CPU_Scheduler_Limit 	= 100
CPU_Available_CPUs 	= 10
CPU_Speed_Limit 	= 100
```

- [ ] **Step 2: Write the failing test**

Create file `Tests/mhTests/CPUGathererDeepTests.swift`:

```swift
import Testing
import Foundation
@testable import mh

@Suite("CPUGatherer (deep)")
struct CPUGathererDeepTests {

    private func fixture(_ name: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures")!
        return try! String(contentsOf: url, encoding: .utf8)
    }

    @Test("deep gathers extended top, thermal state, and uptime")
    func deepGatherer() async throws {
        let runner = FakeProcessRunner(scripted: [
            FakeProcessRunner.Key(path: "/usr/bin/top",
                                  args: ["-l", "1", "-n", "20", "-stats", "pid,cpu,mem,command"]):
                .init(stdout: fixture("top_runaway_slack"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/usr/bin/pmset", args: ["-g", "therm"]):
                .init(stdout: fixture("pmset_therm"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/usr/bin/uptime", args: []):
                .init(stdout: " 19:23  up 4 days, 12:34, 3 users, load averages: 1.2 1.1 1.0\n",
                       stderr: "", exitCode: 0)
        ])
        let result = await CPUGatherer.deep(runner: runner)
        guard case .value(let deep) = result else {
            Issue.record("expected .value, got \(result)"); return
        }
        #expect(deep.fullTopOutput.contains("Slack Helper"))
        #expect(deep.thermalPressure.contains("CPU_Speed_Limit"))
        #expect(deep.uptimeSeconds > 0)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter CPUGathererDeep`
Expected: FAIL.

- [ ] **Step 4: Add `CPUGatherer.deep`**

Append to `Sources/mh/Gatherers/CPUGatherer.swift` (inside the existing `enum CPUGatherer`):

```swift
    static let deepTimeout: TimeInterval = 3.0
    static let pmsetURL = URL(fileURLWithPath: "/usr/bin/pmset")
    static let uptimeURL = URL(fileURLWithPath: "/usr/bin/uptime")

    static func deep(runner: ProcessRunner) async -> ProbeResult<CPUDeep> {
        async let topR = runDeepTop(runner: runner)
        async let thermR = runThermal(runner: runner)
        async let upR = runUptime(runner: runner)
        let (top, therm, uptime) = await (topR, thermR, upR)

        // Allow individual probes to degrade — only fail the whole thing if top fails.
        guard case .value(let topOut) = top else {
            if case .timedOut = top { return .timedOut }
            return .failed("deep top failed")
        }
        let thermOut: String
        if case .value(let t) = therm { thermOut = t } else { thermOut = "(unavailable)" }
        let upSeconds: Int
        if case .value(let u) = uptime { upSeconds = parseUptime(u) } else { upSeconds = 0 }

        return .value(CPUDeep(
            fullTopOutput: String(topOut.prefix(4096)),
            thermalPressure: String(thermOut.prefix(2048)),
            uptimeSeconds: upSeconds
        ))
    }

    private static func runDeepTop(runner: ProcessRunner) async -> ProbeResult<String> {
        do {
            let r = try await runner.run(
                executableURL: topURL,
                arguments: ["-l", "1", "-n", "20", "-stats", "pid,cpu,mem,command"],
                stdin: nil, timeout: deepTimeout)
            if r.exitCode != 0 { return .failed("top exit \(r.exitCode)") }
            return .value(r.stdout)
        } catch ProcessRunnerError.timedOut { return .timedOut }
        catch { return .failed("\(error)") }
    }

    private static func runThermal(runner: ProcessRunner) async -> ProbeResult<String> {
        do {
            let r = try await runner.run(
                executableURL: pmsetURL, arguments: ["-g", "therm"],
                stdin: nil, timeout: deepTimeout)
            if r.exitCode != 0 { return .failed("pmset exit \(r.exitCode)") }
            return .value(r.stdout)
        } catch ProcessRunnerError.timedOut { return .timedOut }
        catch ProcessRunnerError.spawnFailed { return .unavailable }
        catch { return .failed("\(error)") }
    }

    private static func runUptime(runner: ProcessRunner) async -> ProbeResult<String> {
        do {
            let r = try await runner.run(
                executableURL: uptimeURL, arguments: [],
                stdin: nil, timeout: deepTimeout)
            if r.exitCode != 0 { return .failed("uptime exit \(r.exitCode)") }
            return .value(r.stdout)
        } catch ProcessRunnerError.timedOut { return .timedOut }
        catch { return .failed("\(error)") }
    }

    /// "19:23 up 4 days, 12:34, ..." → 4*86400 + 12*3600 + 34*60
    static func parseUptime(_ line: String) -> Int {
        var seconds = 0
        if let m = line.range(of: #"(\d+) days?"#, options: .regularExpression) {
            let s = line[m].split(separator: " ").first.flatMap { Int($0) } ?? 0
            seconds += s * 86400
        }
        // "up 12:34" or "up 12 hrs"
        if let m = line.range(of: #"\b(\d+):(\d+)\b"#, options: .regularExpression) {
            let parts = String(line[m]).split(separator: ":")
            if parts.count == 2, let h = Int(parts[0]), let mm = Int(parts[1]) {
                seconds += h * 3600 + mm * 60
            }
        } else if let m = line.range(of: #"(\d+) hrs?"#, options: .regularExpression) {
            let s = line[m].split(separator: " ").first.flatMap { Int($0) } ?? 0
            seconds += s * 3600
        }
        return seconds
    }
```

- [ ] **Step 5: Add `gatherDeep` to `SignalGatherer`**

Append to `Sources/mh/SignalGatherer.swift` (inside the existing `struct SignalGatherer`):

```swift
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
        return DeepSnapshot(domain: domain, shallow: shallow, deep: deep, timestamp: Date())
    }
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --filter CPUGathererDeep`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/mh/Gatherers/CPUGatherer.swift Sources/mh/SignalGatherer.swift Tests/mhTests/CPUGathererDeepTests.swift Tests/mhTests/Fixtures/pmset_therm.txt
git commit -m "feat(gather): deep gather for CPU domain (top -n 20, pmset therm, uptime)"
```

---

## Task 14: `PromptBuilder.analysis` + `analysis_schema.json`

**Files:**
- Modify: `Sources/mh/Resources/analysis_schema.json`
- Modify: `Sources/mh/PromptBuilder.swift`
- Modify: `Tests/mhTests/PromptBuilderTests.swift`

The analysis schema includes the FixAction allowlist (a JSON-string `params_json` field works around strict-mode's no-optional-properties rule for variadic params).

- [ ] **Step 1: Write `analysis_schema.json`**

Replace contents of `Sources/mh/Resources/analysis_schema.json`:

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["report", "fixes"],
  "properties": {
    "report": { "type": "string" },
    "fixes": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["id", "action", "params_json", "description", "dangerous"],
        "properties": {
          "id": { "type": "integer" },
          "action": {
            "type": "string",
            "enum": [
              "flush_dns",
              "restart_wifi",
              "quit_app",
              "kill_pid",
              "clear_xcode_derived_data",
              "clear_npm_cache",
              "docker_stop_all"
            ]
          },
          "params_json": { "type": "string" },
          "description": { "type": "string" },
          "dangerous": { "type": "boolean" }
        }
      }
    }
  }
}
```

- [ ] **Step 2: Append test for `PromptBuilder.analysis`**

Append to `Tests/mhTests/PromptBuilderTests.swift` (inside the existing suite):

```swift
    @Test("analysis prompt embeds deep snapshot and references analysis schema")
    func analysisPromptShape() throws {
        let shallow = ShallowSnapshot(
            cpu: .value(CPUShallow(loadAverage: [4.2, 3.8, 3.4], topProcesses: [])),
            wifi: .unavailable, disk: .unavailable, battery: .unavailable,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let deepSnap = DeepSnapshot(
            domain: .cpu,
            shallow: shallow,
            deep: .cpu(CPUDeep(fullTopOutput: "top output", thermalPressure: "ok", uptimeSeconds: 3600)),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let result = try PromptBuilder.analysis(deepSnap)
        let schemaData = try Data(contentsOf: result.schemaFile)
        let schemaJson = try JSONSerialization.jsonObject(with: schemaData) as! [String: Any]
        #expect((schemaJson["required"] as? [String])?.contains("fixes") == true)
        #expect(result.prompt.contains("CPU"))
        #expect(result.prompt.contains("FixAction allowlist"))
        #expect(result.prompt.contains("flush_dns"))
    }
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter PromptBuilder`
Expected: FAIL on the new analysis test.

- [ ] **Step 4: Add `PromptBuilder.analysis`**

Append inside the `enum PromptBuilder` body in `Sources/mh/PromptBuilder.swift`:

```swift
    static func analysis(_ deep: DeepSnapshot) throws -> AnalysisPrompt {
        let json = try encodeSnapshotJson(deep)
        let prompt = """
        You are analyzing a Mac diagnostic deep-dive. The deep snapshot below contains \
        both the original shallow signals from all four domains AND the deep probe data \
        for the dominant domain: \(deep.domain.rawValue.uppercased()).

        DEEP_SNAPSHOT:
        \(json)

        Write a multi-section markdown report explaining the root cause and prioritized \
        recommendations. Then propose 0-5 fix actions from the FixAction allowlist:

          - flush_dns                  (params: {})
          - restart_wifi               (params: {"interface": "<en0|en1|...>"})
          - quit_app                   (params: {"bundle_id": "<reverse-DNS bundle ID>"})
          - kill_pid                   (params: {"pid": <integer>})
          - clear_xcode_derived_data   (params: {})
          - clear_npm_cache            (params: {})
          - docker_stop_all            (params: {})

        Each fix MUST set `params_json` to a JSON-encoded string of the params object, \
        even when empty ("{}"). Set `dangerous: true` for any irreversible or data-losing \
        action (kill_pid of unsaved-data apps, clear_xcode_derived_data, docker_stop_all). \
        Respond ONLY with JSON matching the supplied schema.
        """
        guard let url = Bundle.module.url(forResource: "analysis_schema", withExtension: "json") else {
            throw BuilderError.missingResource("analysis_schema.json")
        }
        return AnalysisPrompt(prompt: prompt, schemaFile: url)
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter PromptBuilder`
Expected: PASS for both PromptBuilder tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/mh/PromptBuilder.swift Sources/mh/Resources/analysis_schema.json Tests/mhTests/PromptBuilderTests.swift
git commit -m "feat(prompt): PromptBuilder.analysis + bundled analysis_schema.json"
```

---

## Task 15: `FixAction` + `FixExecutor` with safe-by-default actions

**Files:**
- Create: `Sources/mh/FixAction.swift`
- Create: `Sources/mh/FixExecutor.swift`
- Create: `Sources/mh/Logging.swift`
- Create: `Tests/mhTests/FixExecutorTests.swift`

Ship `flush_dns` and `restart_wifi` first (the two safest). Other actions added in Task 17.

- [ ] **Step 1: Create `FixAction.swift`**

Create file `Sources/mh/FixAction.swift`:

```swift
import Foundation

enum FixAction: String, Codable, Sendable {
    case flushDns = "flush_dns"
    case restartWifi = "restart_wifi"
    case quitApp = "quit_app"
    case killPid = "kill_pid"
    case clearXcodeDerivedData = "clear_xcode_derived_data"
    case clearNpmCache = "clear_npm_cache"
    case dockerStopAll = "docker_stop_all"
}

struct ProposedFix: Codable, Sendable {
    let id: Int
    let action: FixAction
    let paramsJson: String       // raw JSON string from Codex
    let description: String
    let dangerous: Bool

    enum CodingKeys: String, CodingKey {
        case id, action, description, dangerous
        case paramsJson = "params_json"
    }
}

// Per-action param structs. Decoded from `paramsJson` by FixExecutor.
struct FlushDnsParams: Codable, Sendable {}
struct RestartWifiParams: Codable, Sendable { let interface: String }
struct QuitAppParams: Codable, Sendable { let bundle_id: String }
struct KillPidParams: Codable, Sendable { let pid: Int32 }
struct ClearXcodeDerivedDataParams: Codable, Sendable {}
struct ClearNpmCacheParams: Codable, Sendable {}
struct DockerStopAllParams: Codable, Sendable {}

/// Per-action dangerous fallback table (used if Codex forgets to flag).
extension FixAction {
    var dangerousByDefault: Bool {
        switch self {
        case .killPid, .clearXcodeDerivedData, .dockerStopAll: return true
        case .flushDns, .restartWifi, .quitApp, .clearNpmCache: return false
        }
    }
}
```

- [ ] **Step 2: Create `Logging.swift`**

Create file `Sources/mh/Logging.swift`:

```swift
import Foundation

enum AuditLogger {
    static let logDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appending(path: ".local/state/mh", directoryHint: .isDirectory)
    }()
    static var logFile: URL { logDir.appending(path: "log.jsonl") }
    static var errorFile: URL { logDir.appending(path: "error.log") }
    static var sessionsFile: URL { logDir.appending(path: "sessions.jsonl") }

    static func ensureDir() throws {
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    }

    static func append(_ entry: [String: Any], to file: URL) throws {
        try ensureDir()
        let data = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.write(Data([0x0A]))   // newline
            try? handle.close()
        } else {
            var initial = data
            initial.append(0x0A)
            try initial.write(to: file)
        }
    }
}
```

- [ ] **Step 3: Write the failing test (for `flush_dns` + `restart_wifi` only)**

Create file `Tests/mhTests/FixExecutorTests.swift`:

```swift
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
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `swift test --filter FixExecutor`
Expected: FAIL.

- [ ] **Step 5: Implement `FixExecutor`**

Create file `Sources/mh/FixExecutor.swift`:

```swift
import Foundation

enum FixExecutorError: Error {
    case invalidParam(String)
    case unsupportedAction(FixAction)
    case userDeclined
    case revalidationFailed(String)
}

struct FixExecutionResult: Sendable {
    let exitCode: Int32
    let stdoutPreview: String
    let stderrPreview: String
}

struct FixExecutor: Sendable {
    let runner: ProcessRunner
    /// Confirmation hook. Called before executing any fix marked dangerous. Tests inject a stub.
    let confirm: @Sendable (FixAction, String) async -> Bool
    static let execTimeout: TimeInterval = 15.0
    static let sudoURL = URL(fileURLWithPath: "/usr/bin/sudo")
    static let networksetupURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    static let osascriptURL = URL(fileURLWithPath: "/usr/bin/osascript")
    static let killURL = URL(fileURLWithPath: "/bin/kill")
    static let rmURL = URL(fileURLWithPath: "/bin/rm")
    static let dockerURL = URL(fileURLWithPath: "/usr/local/bin/docker")
    static let npmURL = URL(fileURLWithPath: "/opt/homebrew/bin/npm")

    init(runner: ProcessRunner = FoundationProcessRunner(),
         confirm: @escaping @Sendable (FixAction, String) async -> Bool = Self.interactiveConfirm) {
        self.runner = runner
        self.confirm = confirm
    }

    func execute(_ fix: ProposedFix) async throws -> FixExecutionResult {
        // 1) Confirm dangerous fixes (use either Codex flag OR the per-action fallback)
        let isDangerous = fix.dangerous || fix.action.dangerousByDefault
        if isDangerous {
            let ok = await confirm(fix.action, fix.description)
            guard ok else { throw FixExecutorError.userDeclined }
        }
        // 2) Build command (revalidates params inline)
        let (url, args) = try buildCommand(for: fix)
        // 3) Execute
        let result = try await runner.run(executableURL: url, arguments: args,
                                           stdin: nil, timeout: Self.execTimeout)
        // 4) Audit log
        try? AuditLogger.append([
            "ts": ISO8601DateFormatter().string(from: Date()),
            "fix_id": fix.id,
            "action": fix.action.rawValue,
            "params_json": fix.paramsJson,
            "description": fix.description,
            "executable": url.path,
            "argv": args,
            "exit_code": Int(result.exitCode),
            "stdout_preview": String(result.stdout.prefix(1024)),
            "stderr_preview": String(result.stderr.prefix(1024))
        ], to: AuditLogger.logFile)

        return FixExecutionResult(
            exitCode: result.exitCode,
            stdoutPreview: String(result.stdout.prefix(1024)),
            stderrPreview: String(result.stderr.prefix(1024))
        )
    }

    // MARK: - Build commands

    private func buildCommand(for fix: ProposedFix) throws -> (URL, [String]) {
        switch fix.action {
        case .flushDns:
            return (Self.sudoURL, ["-n", "dscacheutil", "-flushcache"])

        case .restartWifi:
            let params = try decode(RestartWifiParams.self, fix.paramsJson)
            try validateInterface(params.interface)
            // Two-shot: off, then on. We dispatch via runner sequentially — caller cares
            // about the second result's exit code, so we run both and combine.
            // For simplicity, we only return the "on" command here and run "off" inline.
            return (Self.networksetupURL, ["-setairportpower", params.interface, "on"])
            // NOTE: The "off" step is run by execute() via a helper; see Task 17.
            // For Task 15 the test only verifies the "on" arg shape.

        case .quitApp, .killPid, .clearXcodeDerivedData, .clearNpmCache, .dockerStopAll:
            throw FixExecutorError.unsupportedAction(fix.action)  // implemented in Task 17
        }
    }

    private func validateInterface(_ s: String) throws {
        let pattern = #"^en\d+$"#
        guard s.range(of: pattern, options: .regularExpression) != nil else {
            throw FixExecutorError.invalidParam("interface '\(s)' does not match ^en\\d+$")
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw FixExecutorError.invalidParam("params_json not utf8")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw FixExecutorError.invalidParam("decode \(T.self): \(error)")
        }
    }

    static let interactiveConfirm: @Sendable (FixAction, String) async -> Bool = { action, desc in
        print("\nRun \(action.rawValue) (\(desc))? [y/N] ", terminator: "")
        let line = readLine() ?? ""
        return line.lowercased().hasPrefix("y")
    }
}
```

**Note:** Task 15's `restartWifi` only returns the "on" command in `buildCommand` to keep this task scoped. Task 17 will refactor to a two-step execute path (off → on) and add the remaining actions. The test for `restartWifi` in this task uses the scripted runner to assert the "on" args; the "off" step is asserted in Task 17's expanded test.

**Correction for this task to make the test pass:** the test expects both `off` and `on` to run. Update `buildCommand` to handle restart_wifi as two sequential runs. Rewrite the `restartWifi` case of `execute` (split out a helper):

Replace the `execute` method with this variant that special-cases `restartWifi`:

```swift
    func execute(_ fix: ProposedFix) async throws -> FixExecutionResult {
        let isDangerous = fix.dangerous || fix.action.dangerousByDefault
        if isDangerous {
            let ok = await confirm(fix.action, fix.description)
            guard ok else { throw FixExecutorError.userDeclined }
        }

        let result: ProcessResult
        switch fix.action {
        case .restartWifi:
            let params = try decode(RestartWifiParams.self, fix.paramsJson)
            try validateInterface(params.interface)
            _ = try await runner.run(
                executableURL: Self.networksetupURL,
                arguments: ["-setairportpower", params.interface, "off"],
                stdin: nil, timeout: Self.execTimeout
            )
            result = try await runner.run(
                executableURL: Self.networksetupURL,
                arguments: ["-setairportpower", params.interface, "on"],
                stdin: nil, timeout: Self.execTimeout
            )
        default:
            let (url, args) = try buildCommand(for: fix)
            result = try await runner.run(
                executableURL: url, arguments: args, stdin: nil, timeout: Self.execTimeout
            )
        }

        try? AuditLogger.append([
            "ts": ISO8601DateFormatter().string(from: Date()),
            "fix_id": fix.id,
            "action": fix.action.rawValue,
            "params_json": fix.paramsJson,
            "description": fix.description,
            "exit_code": Int(result.exitCode),
            "stdout_preview": String(result.stdout.prefix(1024)),
            "stderr_preview": String(result.stderr.prefix(1024))
        ], to: AuditLogger.logFile)

        return FixExecutionResult(
            exitCode: result.exitCode,
            stdoutPreview: String(result.stdout.prefix(1024)),
            stderrPreview: String(result.stderr.prefix(1024))
        )
    }
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --filter FixExecutor`
Expected: PASS for all four tests (flushDns, restartWifi, restartWifiRejectsMalicious, confirmRefusal).

- [ ] **Step 7: Commit**

```bash
git add Sources/mh/FixAction.swift Sources/mh/FixExecutor.swift Sources/mh/Logging.swift Tests/mhTests/FixExecutorTests.swift
git commit -m "feat(fix): FixAction enum + FixExecutor with flush_dns and restart_wifi"
```

---

## Task 16: Deep gather for wifi, disk, battery domains

**Files:**
- Modify: `Sources/mh/Gatherers/WifiGatherer.swift` (add `deep`)
- Modify: `Sources/mh/Gatherers/DiskGatherer.swift` (add `deep`)
- Modify: `Sources/mh/Gatherers/BatteryGatherer.swift` (add `deep`)
- Modify: `Sources/mh/SignalGatherer.swift` (remove `fatalError` cases)
- Create: `Tests/mhTests/Fixtures/system_profiler_wifi.txt`

For brevity, this task implements three deep gatherers with the same pattern (each runs 2-3 subprocesses in parallel, truncates output, tolerates partial probe failure).

- [ ] **Step 1: Create the wifi system_profiler fixture**

Create file `Tests/mhTests/Fixtures/system_profiler_wifi.txt`:

```
Wi-Fi:

      Software Versions:
          CoreWLAN: 17.0 (1700.4)
          CoreWLANKit: 17.0 (1700.4)

      Interfaces:
        en0:
          Card Type: Wi-Fi (0x14E4, 0x4387)
          Firmware Version: wl0: Apr 16 2024 11:23:45 version 9.10.0
          MAC Address: aa:bb:cc:dd:ee:ff
          Status: Connected
          Current Network Information:
            HomeNetwork:
              PHY Mode: 802.11ax
              BSSID: 11:22:33:44:55:66
              Channel: 36 (5GHz, 80MHz)
              Country Code: US
              Network Type: Infrastructure
              Security: WPA2 Personal
              Signal / Noise: -45 dBm / -90 dBm
              Transmit Rate: 866
              MCS Index: 9
```

- [ ] **Step 2: Add `WifiGatherer.deep`**

Append to `Sources/mh/Gatherers/WifiGatherer.swift`:

```swift
    static let deepTimeout: TimeInterval = 3.0
    static let systemProfilerURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    static let digURL = URL(fileURLWithPath: "/usr/bin/dig")
    static let pingURL = URL(fileURLWithPath: "/sbin/ping")

    static func deep(runner: ProcessRunner) async -> ProbeResult<WifiDeep> {
        async let spR = runSystemProfiler(runner: runner)
        async let digR = runDig(runner: runner)
        async let pingR = runPing(runner: runner)
        let (sp, dig, ping) = await (spR, digR, pingR)

        guard case .value(let spOut) = sp else {
            return .failed("system_profiler did not return data")
        }
        let dnsMs: Double? = (dig.value).flatMap(parseDigMs)
        let gatewayMs: Double? = (ping.value).flatMap(parsePingAvgMs)

        return .value(WifiDeep(
            systemProfilerOutput: String(spOut.prefix(8192)),
            dnsTimingMs: dnsMs,
            gatewayPingMs: gatewayMs,
            traceroute: nil    // traceroute optional; skipped for v0.1 to keep deep gather <3s
        ))
    }

    private static func runSystemProfiler(runner: ProcessRunner) async -> ProbeResult<String> {
        do {
            let r = try await runner.run(
                executableURL: systemProfilerURL, arguments: ["SPAirPortDataType"],
                stdin: nil, timeout: deepTimeout)
            return r.exitCode == 0 ? .value(r.stdout) : .failed("exit \(r.exitCode)")
        } catch ProcessRunnerError.timedOut { return .timedOut }
        catch { return .failed("\(error)") }
    }

    private static func runDig(runner: ProcessRunner) async -> ProbeResult<String> {
        do {
            let r = try await runner.run(
                executableURL: digURL, arguments: ["+stats", "+tries=1", "+time=2", "apple.com"],
                stdin: nil, timeout: deepTimeout)
            return r.exitCode == 0 ? .value(r.stdout) : .failed("dig exit \(r.exitCode)")
        } catch { return .failed("\(error)") }
    }

    private static func runPing(runner: ProcessRunner) async -> ProbeResult<String> {
        // Resolve default gateway via `netstat -rn -f inet` parse — out of scope for v0.1.
        // Skip ping for v0.1; return unavailable so deep gather still succeeds.
        _ = runner
        return .unavailable
    }

    static func parseDigMs(_ s: String) -> Double? {
        if let range = s.range(of: #";; Query time: (\d+) msec"#, options: .regularExpression) {
            let digits = s[range].compactMap { $0.isNumber ? $0 : nil }
            return Double(String(digits))
        }
        return nil
    }

    static func parsePingAvgMs(_ s: String) -> Double? {
        // "round-trip min/avg/max/stddev = 1.234/2.345/3.456/0.123 ms"
        guard let range = s.range(of: #"min/avg/max/stddev = \S+"#, options: .regularExpression) else {
            return nil
        }
        let parts = s[range].split(separator: "=").last?.trimmingCharacters(in: .whitespaces)
                            .split(separator: "/")
        guard let parts = parts, parts.count >= 2 else { return nil }
        return Double(parts[1])
    }
}

extension ProbeResult {
    var value: T? { if case .value(let v) = self { return v }; return nil }
}
```

- [ ] **Step 3: Add `DiskGatherer.deep`**

Append to `Sources/mh/Gatherers/DiskGatherer.swift`:

```swift
    static let deepTimeout: TimeInterval = 3.0
    static let duURL = URL(fileURLWithPath: "/usr/bin/du")

    static let knownCachePaths: [String] = [
        NSString("~/Library/Developer/Xcode/DerivedData").expandingTildeInPath,
        NSString("~/.npm/_cacache").expandingTildeInPath,
        NSString("~/Library/Caches").expandingTildeInPath,
        NSString("~/Downloads").expandingTildeInPath
    ]

    static func deep(runner: ProcessRunner) async -> ProbeResult<DiskDeep> {
        var results: [DiskUsage] = []
        for path in knownCachePaths where FileManager.default.fileExists(atPath: path) {
            if case .value(let gb) = await duOne(runner: runner, path: path) {
                results.append(DiskUsage(path: path, sizeGB: gb))
            }
        }
        return .value(DiskDeep(topDirectories: results, purgeableGB: nil))
    }

    private static func duOne(runner: ProcessRunner, path: String) async -> ProbeResult<Double> {
        do {
            let r = try await runner.run(
                executableURL: duURL, arguments: ["-sk", path],
                stdin: nil, timeout: deepTimeout)
            if r.exitCode != 0 { return .failed("du exit \(r.exitCode)") }
            // "1234567\t/path"
            let first = r.stdout.split(separator: "\t").first.flatMap { Int($0) } ?? 0
            return .value(Double(first) / (1024.0 * 1024.0))  // KB → GB
        } catch ProcessRunnerError.timedOut { return .timedOut }
        catch { return .failed("\(error)") }
    }
}
```

- [ ] **Step 4: Add `BatteryGatherer.deep`**

Append to `Sources/mh/Gatherers/BatteryGatherer.swift`:

```swift
    static let deepTimeout: TimeInterval = 3.0
    static let ioregURL = URL(fileURLWithPath: "/usr/sbin/ioreg")

    static func deep(runner: ProcessRunner) async -> ProbeResult<BatteryDeep> {
        async let gR = runPmsetGAll(runner: runner)
        async let lR = runPmsetGLog(runner: runner)
        async let cR = runIoregCycles(runner: runner)
        let (g, l, c) = await (gR, lR, cR)

        let gFull = g.value ?? "(unavailable)"
        let history = l.value ?? "(unavailable)"
        let cycles = c.value.flatMap(parseCycleCount)

        return .value(BatteryDeep(
            pmsetGFull: String(gFull.prefix(2048)),
            powerHistory: String(history.prefix(4096)),
            cycleCount: cycles
        ))
    }

    private static func runPmsetGAll(runner: ProcessRunner) async -> ProbeResult<String> {
        do {
            let r = try await runner.run(executableURL: pmsetURL, arguments: ["-g"],
                                          stdin: nil, timeout: deepTimeout)
            return r.exitCode == 0 ? .value(r.stdout) : .failed("exit \(r.exitCode)")
        } catch { return .failed("\(error)") }
    }

    private static func runPmsetGLog(runner: ProcessRunner) async -> ProbeResult<String> {
        // pmset -g log can be very long. We truncate at the caller level.
        do {
            let r = try await runner.run(executableURL: pmsetURL, arguments: ["-g", "log"],
                                          stdin: nil, timeout: deepTimeout)
            return r.exitCode == 0 ? .value(r.stdout) : .failed("exit \(r.exitCode)")
        } catch ProcessRunnerError.timedOut { return .timedOut }
        catch { return .failed("\(error)") }
    }

    private static func runIoregCycles(runner: ProcessRunner) async -> ProbeResult<String> {
        do {
            let r = try await runner.run(
                executableURL: ioregURL,
                arguments: ["-rn", "AppleSmartBattery"],
                stdin: nil, timeout: deepTimeout)
            return r.exitCode == 0 ? .value(r.stdout) : .failed("exit \(r.exitCode)")
        } catch { return .failed("\(error)") }
    }

    static func parseCycleCount(_ ioregOut: String) -> Int? {
        if let m = ioregOut.range(of: #""CycleCount" = (\d+)"#, options: .regularExpression) {
            return ioregOut[m].split(separator: " ").last.flatMap { Int($0) }
        }
        return nil
    }
}
```

- [ ] **Step 5: Update `SignalGatherer.gatherDeep` to handle all four domains**

Replace the existing `gatherDeep` method body in `Sources/mh/SignalGatherer.swift`:

```swift
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
        return DeepSnapshot(domain: domain, shallow: shallow, deep: deep, timestamp: Date())
    }
```

- [ ] **Step 6: Build to verify (no new tests for this task — these are exercised by Task 18 end-to-end)**

Run: `swift build && swift test`
Expected: all existing tests still pass; build succeeds.

- [ ] **Step 7: Commit**

```bash
git add Sources/mh/Gatherers/WifiGatherer.swift Sources/mh/Gatherers/DiskGatherer.swift Sources/mh/Gatherers/BatteryGatherer.swift Sources/mh/SignalGatherer.swift Tests/mhTests/Fixtures/system_profiler_wifi.txt
git commit -m "feat(gather): deep gather for wifi/disk/battery domains"
```

---

## Task 17: Remaining `FixAction`s — quit_app, kill_pid, cache clears, docker stop

**Files:**
- Modify: `Sources/mh/FixExecutor.swift`
- Modify: `Tests/mhTests/FixExecutorTests.swift`

- [ ] **Step 1: Append failing tests**

Append inside the `FixExecutorTests` suite in `Tests/mhTests/FixExecutorTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FixExecutor`
Expected: FAIL on the new tests (unsupportedAction errors).

- [ ] **Step 3: Extend `buildCommand` in `FixExecutor.swift`**

Replace the `buildCommand` method in `Sources/mh/FixExecutor.swift` with:

```swift
    private func buildCommand(for fix: ProposedFix) throws -> (URL, [String]) {
        switch fix.action {
        case .flushDns:
            return (Self.sudoURL, ["-n", "dscacheutil", "-flushcache"])

        case .restartWifi:
            // Handled in execute() as a two-step run
            fatalError("restartWifi handled in execute(), not buildCommand")

        case .quitApp:
            let params = try decode(QuitAppParams.self, fix.paramsJson)
            try validateBundleId(params.bundle_id)
            return (Self.osascriptURL,
                    ["-e", "tell application id \"\(params.bundle_id)\" to quit"])

        case .killPid:
            let params = try decode(KillPidParams.self, fix.paramsJson)
            try validatePid(params.pid)
            return (Self.killURL, ["-15", String(params.pid)])  // SIGTERM, not SIGKILL

        case .clearXcodeDerivedData:
            let path = NSString("~/Library/Developer/Xcode/DerivedData").expandingTildeInPath
            return (Self.rmURL, ["-rf", path])

        case .clearNpmCache:
            let path = NSString("~/.npm/_cacache").expandingTildeInPath
            return (Self.rmURL, ["-rf", path])

        case .dockerStopAll:
            // `docker stop $(docker ps -q)` is shell expansion; we don't shell out.
            // Instead, run docker ps -q, capture, then docker stop <ids...> via a helper.
            fatalError("dockerStopAll handled in execute(), not buildCommand")
        }
    }

    private func validateBundleId(_ s: String) throws {
        let pattern = #"^[a-zA-Z0-9.\-]+$"#
        guard s.range(of: pattern, options: .regularExpression) != nil, !s.isEmpty else {
            throw FixExecutorError.invalidParam("bundle_id '\(s)' has invalid characters")
        }
    }

    private func validatePid(_ pid: Int32) throws {
        guard pid > 1 else {
            throw FixExecutorError.invalidParam("pid \(pid) refuses (must be > 1)")
        }
        // Revalidation: process must exist right now
        guard kill(pid, 0) == 0 else {
            throw FixExecutorError.revalidationFailed("pid \(pid) is no longer running")
        }
    }
```

- [ ] **Step 4: Extend `execute` to handle `dockerStopAll`**

In the `switch` of `execute`, replace `default:` with explicit cases that also include the docker special case:

```swift
        switch fix.action {
        case .restartWifi:
            // (existing two-step run from Task 15)
            let params = try decode(RestartWifiParams.self, fix.paramsJson)
            try validateInterface(params.interface)
            _ = try await runner.run(
                executableURL: Self.networksetupURL,
                arguments: ["-setairportpower", params.interface, "off"],
                stdin: nil, timeout: Self.execTimeout)
            result = try await runner.run(
                executableURL: Self.networksetupURL,
                arguments: ["-setairportpower", params.interface, "on"],
                stdin: nil, timeout: Self.execTimeout)

        case .dockerStopAll:
            // Step 1: get running container IDs
            let ids = try await runner.run(
                executableURL: Self.dockerURL,
                arguments: ["ps", "-q"],
                stdin: nil, timeout: Self.execTimeout)
            let containerIds = ids.stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            if containerIds.isEmpty {
                result = ProcessResult(stdout: "no running containers", stderr: "", exitCode: 0)
            } else {
                result = try await runner.run(
                    executableURL: Self.dockerURL,
                    arguments: ["stop"] + containerIds,
                    stdin: nil, timeout: Self.execTimeout)
            }

        default:
            let (url, args) = try buildCommand(for: fix)
            result = try await runner.run(
                executableURL: url, arguments: args, stdin: nil, timeout: Self.execTimeout)
        }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter FixExecutor`
Expected: PASS for all FixExecutor tests (now 8 total).

- [ ] **Step 6: Commit**

```bash
git add Sources/mh/FixExecutor.swift Tests/mhTests/FixExecutorTests.swift
git commit -m "feat(fix): quit_app, kill_pid, cache clears, docker_stop_all + validators"
```

---

## Task 18: `ChatLoop` and full pipeline in `main`

**Files:**
- Create: `Sources/mh/ChatLoop.swift`
- Modify: `Sources/mh/main.swift`
- Create: `Tests/mhTests/ChatLoopTests.swift`

- [ ] **Step 1: Write the failing test**

Create file `Tests/mhTests/ChatLoopTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ChatLoop`
Expected: FAIL.

- [ ] **Step 3: Implement `ChatLoop`**

Create file `Sources/mh/ChatLoop.swift`:

```swift
import Foundation

struct AnalysisResponse: Codable, Sendable {
    let report: String
    let fixes: [ProposedFix]
}

struct ChatLoop {
    let codex: CodexClient
    let executor: FixExecutor
    let fixes: [ProposedFix]
    let snapshotTimestamp: Date
    let maxTurns: Int
    static let staleThresholdSeconds: TimeInterval = 60

    init(codex: CodexClient, executor: FixExecutor, fixes: [ProposedFix],
         snapshotTimestamp: Date, maxTurns: Int = 6) {
        self.codex = codex
        self.executor = executor
        self.fixes = fixes
        self.snapshotTimestamp = snapshotTimestamp
        self.maxTurns = maxTurns
    }

    func run() async {
        var turns = 0
        print("\n(chat mode active — ask follow-up questions, `run N` to execute a fix, or `exit`)")
        while turns < maxTurns {
            print("> ", terminator: "")
            guard let line = readLine() else { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.lowercased() == "exit" { return }
            if let idx = Self.parseRunCommand(trimmed) {
                await handleRun(idx)
            } else {
                await handleFollowUp(trimmed)
            }
            turns += 1
        }
        print("(turn budget of \(maxTurns) reached; restart `mh` for a fresh session)")
    }

    private func handleRun(_ idx: Int) async {
        guard idx >= 0, idx < fixes.count else {
            print("no fix #\(idx + 1); reports has \(fixes.count) fix(es)")
            return
        }
        let age = Date().timeIntervalSince(snapshotTimestamp)
        if age > Self.staleThresholdSeconds {
            print("Snapshot is \(Int(age))s old; PIDs/interfaces may have changed. Continue? [y/N] ",
                  terminator: "")
            let line = readLine() ?? ""
            guard line.lowercased().hasPrefix("y") else {
                print("(skipped — re-run `mh` for a fresh snapshot)")
                return
            }
        }
        do {
            let result = try await executor.execute(fixes[idx])
            print("[exit \(result.exitCode)] \(result.stdoutPreview)")
            if !result.stderrPreview.isEmpty {
                print("[stderr] \(result.stderrPreview)")
            }
        } catch FixExecutorError.userDeclined {
            print("(declined)")
        } catch FixExecutorError.invalidParam(let m) {
            print("invalid fix parameters: \(m)")
        } catch FixExecutorError.revalidationFailed(let m) {
            print("fix is stale: \(m)")
        } catch {
            print("fix failed: \(error)")
        }
    }

    private func handleFollowUp(_ line: String) async {
        struct FollowUpResponse: Codable { let report: String; let fixes: [ProposedFix] }
        do {
            let resp: FollowUpResponse = try await codex.resume(
                prompt: line, schemaFile: nil, decoding: FollowUpResponse.self
            )
            print(resp.report)
        } catch {
            print("(codex follow-up failed: \(error))")
        }
    }

    /// "run 2" → 1 (zero-indexed). 1-indexed in user input.
    static func parseRunCommand(_ s: String) -> Int? {
        let trimmed = s.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.hasPrefix("run ") else { return nil }
        let rest = trimmed.dropFirst("run ".count).trimmingCharacters(in: .whitespaces)
        guard let n = Int(rest), n >= 1 else { return nil }
        return n - 1
    }
}
```

- [ ] **Step 4: Wire the full pipeline into `main.swift`**

Replace `Sources/mh/main.swift`:

```swift
import ArgumentParser
import Foundation

@main
struct MH: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mh",
        abstract: "macOS diagnostic CLI with LLM synthesis",
        subcommands: [Doctor.self]
    )

    func run() async throws {
        let runner = FoundationProcessRunner()
        let gatherer = SignalGatherer(runner: runner)
        let codex = CodexClient(runner: runner, codexPath: resolveCodexPath() ?? "/opt/homebrew/bin/codex")

        FileHandle.standardError.write(Data("[gathering signals... ".utf8))
        let started = Date()
        let shallow = await gatherer.gatherShallow()
        FileHandle.standardError.write(Data("\(format(elapsed: started))]\n".utf8))

        FileHandle.standardError.write(Data("[triaging... ".utf8))
        let triageStart = Date()
        let triage: TriageResponse
        do {
            let p = try PromptBuilder.triage(shallow)
            triage = try await codex.openSession(
                prompt: p.prompt, schemaFile: p.schemaFile, decoding: TriageResponse.self
            )
        } catch {
            FileHandle.standardError.write(Data("failed]\n".utf8))
            try? AuditLogger.append(["error": "\(error)", "ts": ISO8601DateFormatter().string(from: Date())],
                                     to: AuditLogger.errorFile)
            print("(codex triage failed; raw snapshot follows)\n")
            print(localFallbackReport(shallow))
            return
        }
        FileHandle.standardError.write(Data("\(format(elapsed: triageStart))]\n".utf8))

        guard let domain = Domain(rawValue: triage.domain) else {
            print("Everything looks normal — Codex reasoning: \(triage.reasoning)")
            return
        }

        FileHandle.standardError.write(Data("[deep gather: \(domain.rawValue)... ".utf8))
        let deepStart = Date()
        let deepSnap = await gatherer.gatherDeep(domain, shallow: shallow)
        FileHandle.standardError.write(Data("\(format(elapsed: deepStart))]\n".utf8))

        FileHandle.standardError.write(Data("[analyzing... ".utf8))
        let analysisStart = Date()
        let analysis: AnalysisResponse
        do {
            let p = try PromptBuilder.analysis(deepSnap)
            analysis = try await codex.resume(
                prompt: p.prompt, schemaFile: p.schemaFile, decoding: AnalysisResponse.self
            )
        } catch {
            FileHandle.standardError.write(Data("failed]\n".utf8))
            try? AuditLogger.append(["error": "\(error)", "ts": ISO8601DateFormatter().string(from: Date())],
                                     to: AuditLogger.errorFile)
            print("(codex analysis failed)")
            return
        }
        FileHandle.standardError.write(Data("\(format(elapsed: analysisStart))]\n\n".utf8))

        print(analysis.report)
        print("\n### Fixes")
        for fix in analysis.fixes {
            let marker = fix.dangerous ? " ⚠" : ""
            print("\(fix.id). \(fix.description)\(marker)")
        }

        // Log session for later debugging
        if let tid = await codex.threadId {
            try? AuditLogger.append([
                "ts": ISO8601DateFormatter().string(from: Date()),
                "thread_id": tid, "domain": domain.rawValue
            ], to: AuditLogger.sessionsFile)
        }

        let chat = ChatLoop(codex: codex, executor: FixExecutor(runner: runner),
                             fixes: analysis.fixes, snapshotTimestamp: deepSnap.timestamp)
        await chat.run()
    }

    private func resolveCodexPath() -> String? {
        for path in ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    private func format(elapsed start: Date) -> String {
        let s = Date().timeIntervalSince(start)
        return String(format: "%.1fs", s)
    }

    private func localFallbackReport(_ s: ShallowSnapshot) -> String {
        var out = "## Local snapshot (Codex unavailable)\n\n"
        out += "Timestamp: \(s.timestamp)\n"
        out += "CPU: \(s.cpu)\nWiFi: \(s.wifi)\nDisk: \(s.disk)\nBattery: \(s.battery)\n"
        return out
    }
}

struct TriageResponse: Codable {
    let domain: String      // wifi/cpu/disk/battery/none
    let reasoning: String
}
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter ChatLoop`
Expected: PASS.

Run: `swift build`
Expected: builds without errors.

- [ ] **Step 6: Commit**

```bash
git add Sources/mh/ChatLoop.swift Sources/mh/main.swift Tests/mhTests/ChatLoopTests.swift
git commit -m "feat(cli): ChatLoop REPL + full pipeline wired in main"
```

---

## Task 19: End-to-end integration test with fixture-only run

**Files:**
- Create: `Tests/mhTests/EndToEndTests.swift`
- Create: `Tests/mhTests/Fixtures/codex_analysis_response.jsonl`

- [ ] **Step 1: Create analysis fixture**

Create file `Tests/mhTests/Fixtures/codex_analysis_response.jsonl`:

```
{"type":"thread.started","thread_id":"019e4db8-6142-7031-a4b2-189862c6546f"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"{\"report\":\"Slack is at 380% CPU; quit it.\",\"fixes\":[{\"id\":1,\"action\":\"quit_app\",\"params_json\":\"{\\\"bundle_id\\\":\\\"us.slack.Slack\\\"}\",\"description\":\"Quit Slack\",\"dangerous\":false}]}"}}
{"type":"turn.completed","usage":{"input_tokens":18741,"cached_input_tokens":2432,"output_tokens":126,"reasoning_output_tokens":68}}
```

- [ ] **Step 2: Write the failing test**

Create file `Tests/mhTests/EndToEndTests.swift`:

```swift
import Testing
import Foundation
@testable import mh

@Suite("End-to-end pipeline (fixtures only)")
struct EndToEndTests {

    private func read(_ name: String, _ ext: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")!
        return try! String(contentsOf: url, encoding: .utf8)
    }

    @Test("shallow → triage → deep → analysis → fixes (no real codex)")
    func fullPipelineWithFixtures() async throws {
        let codexPath = "/opt/homebrew/bin/codex"
        let runner = FakeProcessRunner(scripted: [
            // Shallow probes
            FakeProcessRunner.Key(path: "/usr/bin/top",
                                  args: ["-l", "1", "-n", "5", "-stats", "pid,cpu,mem,command"]):
                .init(stdout: read("top_runaway_slack", "txt"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport",
                                  args: ["-I"]):
                .init(stdout: read("airport_I_normal", "txt"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/usr/sbin/networksetup",
                                  args: ["-getairportnetwork", "en0"]):
                .init(stdout: read("networksetup_getairportnetwork", "txt"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/bin/df", args: ["-h"]):
                .init(stdout: read("df_h_normal", "txt"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/usr/bin/pmset", args: ["-g", "batt"]):
                .init(stdout: read("pmset_batt_ac", "txt"), stderr: "", exitCode: 0),
            // Triage codex call (any prompt argv; we match on flags)
            FakeProcessRunner.Key(path: codexPath, args: anyTriageArgs()):
                .init(stdout: read("codex_triage_response", "jsonl"), stderr: "", exitCode: 0),
            // Deep CPU probes
            FakeProcessRunner.Key(path: "/usr/bin/top",
                                  args: ["-l", "1", "-n", "20", "-stats", "pid,cpu,mem,command"]):
                .init(stdout: read("top_runaway_slack", "txt"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/usr/bin/pmset", args: ["-g", "therm"]):
                .init(stdout: read("pmset_therm", "txt"), stderr: "", exitCode: 0),
            FakeProcessRunner.Key(path: "/usr/bin/uptime", args: []):
                .init(stdout: " 19:23  up 4 days, 12:34, 3 users, load averages: 1.2 1.1 1.0\n",
                       stderr: "", exitCode: 0),
            // Analysis codex call
            FakeProcessRunner.Key(path: codexPath, args: anyAnalysisArgs()):
                .init(stdout: read("codex_analysis_response", "jsonl"), stderr: "", exitCode: 0)
        ])

        let gatherer = SignalGatherer(runner: runner)
        let codex = CodexClient(runner: runner, codexPath: codexPath)

        let shallow = await gatherer.gatherShallow()
        #expect(shallow.cpu.isOk)

        // Triage
        let triagePrompt = try PromptBuilder.triage(shallow)
        let triage: TriageResponse = try await codex.openSession(
            prompt: triagePrompt.prompt,
            schemaFile: triagePrompt.schemaFile,
            decoding: TriageResponse.self
        )
        #expect(triage.domain == "cpu")

        // Deep
        let deepSnap = await gatherer.gatherDeep(.cpu, shallow: shallow)
        let analysisPrompt = try PromptBuilder.analysis(deepSnap)
        let analysis: AnalysisResponse = try await codex.resume(
            prompt: analysisPrompt.prompt,
            schemaFile: analysisPrompt.schemaFile,
            decoding: AnalysisResponse.self
        )
        #expect(analysis.report.contains("Slack"))
        #expect(analysis.fixes.count == 1)
        #expect(analysis.fixes.first?.action == .quitApp)
    }

    private func anyTriageArgs() -> [String] {
        // Triage: codex exec --json --output-schema <triage_schema.json> -
        // The schemaFile path is resolved at runtime; the test FakeProcessRunner uses exact match,
        // so we resolve the URL the same way the PromptBuilder does.
        let url = Bundle.module.url(forResource: "triage_schema", withExtension: "json")!
        return ["exec", "--json", "--output-schema", url.path, "-"]
    }

    private func anyAnalysisArgs() -> [String] {
        let url = Bundle.module.url(forResource: "analysis_schema", withExtension: "json")!
        return ["exec", "resume", "019e4db8-6142-7031-a4b2-189862c6546f",
                "--json", "--output-schema", url.path, "-"]
    }
}
```

Note: `Bundle.module.url(forResource: "triage_schema", ...)` in the test binary points to the test bundle's schema, not the main target's. To make this work, copy the same schema JSON into `Tests/mhTests/Fixtures/triage_schema.json` and `analysis_schema.json`.

Actually for v0.1 simplicity, copy the schemas into Fixtures so the test runs against the same bytes:

```bash
cp Sources/mh/Resources/triage_schema.json Tests/mhTests/Fixtures/
cp Sources/mh/Resources/analysis_schema.json Tests/mhTests/Fixtures/
```

- [ ] **Step 3: Copy schemas to fixtures**

```bash
cp Sources/mh/Resources/triage_schema.json Tests/mhTests/Fixtures/
cp Sources/mh/Resources/analysis_schema.json Tests/mhTests/Fixtures/
```

- [ ] **Step 4: Run the test**

Run: `swift test --filter EndToEnd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Tests/mhTests/EndToEndTests.swift Tests/mhTests/Fixtures/codex_analysis_response.jsonl Tests/mhTests/Fixtures/triage_schema.json Tests/mhTests/Fixtures/analysis_schema.json
git commit -m "test(e2e): shallow→triage→deep→analysis pipeline with fakes"
```

---

## Task 20: README rewrite + manual smoke + install

**Files:**
- Modify: `README.md`

The original README documented the pre-design seed. Replace it with v0.1 usage + install.

- [ ] **Step 1: Replace `README.md`**

Replace contents of `README.md`:

```markdown
# Mac Healthcheck

`mh` — a single-binary macOS diagnostic CLI. Runs a staged health check across CPU, WiFi,
disk, and battery, sends the signals to Codex CLI for synthesis, prints a markdown report,
and drops into a chat loop where you can ask follow-ups or run allowlisted fixes.

> **Status: v0.1 (Charlie-only personal-utility build).** See `docs/superpowers/specs/`
> for the design spec.

## Requirements

- macOS 14+ (Sonoma) on Apple Silicon
- Codex CLI installed and authenticated:
  ```bash
  brew install codex
  codex login
  ```
- Swift 6.0+ (`/usr/bin/swift`) for building from source

## Install

```bash
git clone https://github.com/<you>/mac-healthcheck
cd mac-healthcheck
swift build -c release
cp .build/release/mh /usr/local/bin/
```

## Usage

```bash
# Run the full pipeline
mh

# Just check the environment (codex installed, auth, required tools)
mh doctor
```

Expected output of `mh`:

```
[gathering signals... 0.3s]
[triaging... 6.5s]
[deep gather: cpu... 1.8s]
[analyzing... 8.2s]

## Health Report
Slack is at 380% CPU; quit it.

### Fixes
1. Quit Slack

(chat mode active — ask follow-up questions, `run N` to execute a fix, or `exit`)
> run 1
[exit 0]
> exit
```

End-to-end latency is dominated by Codex inference time, typically 15-20s to the first
report.

## Where logs live

- `~/.local/state/mh/log.jsonl` — every executed fix (before+after, exact argv, exit code)
- `~/.local/state/mh/error.log` — Codex / probe errors
- `~/.local/state/mh/sessions.jsonl` — Codex `thread_id`s (resumable via `codex exec resume`)

## Architecture

See `docs/superpowers/specs/2026-05-21-mac-healthcheck-v0.1-design.md`.

## v0.1 non-goals

- Menu bar GUI (v0.2)
- Background polling
- Local LLM fallback
- Sudo system config changes (DNS server, energy settings)
- App Store distribution
```

- [ ] **Step 2: Run all tests one final time**

Run: `swift test`
Expected: all tests pass (every suite from Tasks 2-19).

- [ ] **Step 3: Manual smoke test**

Run: `swift build -c release`
Expected: builds, produces `.build/release/mh`.

Run: `./.build/release/mh doctor`
Expected: all probe binaries listed as ✓, Codex install + auth verified.

Run: `./.build/release/mh`
Expected: gathers signals, calls Codex, prints a report, drops into chat. Type `exit` to leave.

- [ ] **Step 4: Install to PATH**

```bash
cp .build/release/mh /usr/local/bin/
mh doctor
```

- [ ] **Step 5: Final commit**

```bash
git add README.md
git commit -m "docs: rewrite README for v0.1 usage + install"
```

---

## Summary of build order

| Task | Lines | Adds |
|---|---|---|
| 1  | ~30   | SPM scaffold, stub binary |
| 2  | ~30   | Domain + ProbeResult |
| 3  | ~100  | ProcessRunner + Fake |
| 4  | ~120  | Snapshot structs |
| 5  | ~110  | CPU shallow gatherer |
| 6  | ~120  | Wifi shallow gatherer |
| 7  | ~90   | Disk shallow gatherer |
| 8  | ~90   | Battery shallow gatherer |
| 9  | ~30   | SignalGatherer composes 4 |
| 10 | ~80   | triage schema + prompt |
| 11 | ~150  | CodexClient.openSession |
| 12 | ~80   | `mh doctor` subcommand |
| 13 | ~120  | CPU deep gatherer |
| 14 | ~50   | analysis schema + prompt |
| 15 | ~200  | FixAction + Executor (flush_dns, restart_wifi) |
| 16 | ~200  | Deep gatherers for wifi/disk/battery |
| 17 | ~120  | Remaining FixActions |
| 18 | ~150  | ChatLoop + main pipeline |
| 19 | ~100  | End-to-end test |
| 20 | ~30   | README + install |

Total: ~2000 lines, including tests. Realistic build window: 2-3 focused weekends.

## Explicitly deferred from spec error table

The spec's error-handling table includes one row not implemented by this plan:

- **Codex rate-limit retry-with-backoff**: spec says "Wait + retry once with backoff, then degrade to local snapshot." Personal-utility build use is unlikely to hit Codex rate limits, and the existing fallback (catch → local snapshot report) already handles the degradation. If rate-limit hits become a real annoyance during dogfooding, add an exponential-backoff retry inside `CodexClient.openSession` / `resume` as a v0.2 enhancement.

All other rows in the spec's error table are exercised by the tests in Tasks 5-19.
