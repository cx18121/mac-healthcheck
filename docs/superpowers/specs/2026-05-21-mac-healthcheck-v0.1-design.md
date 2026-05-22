# Mac Healthcheck v0.1 — Design

**Status:** approved for implementation (pending user review of this doc)
**Date:** 2026-05-21
**Form factor:** Swift CLI (single binary), command name `mh`
**Audience:** Charlie (personal-utility build); not yet aimed at distribution

---

## One-paragraph product description

`mh` is a macOS command-line diagnostic tool. Running `mh` with no arguments performs a
staged health check: it gathers cheap cross-system signals (CPU, wifi, disk, battery),
sends them to Codex CLI for triage, then deep-gathers the dominant domain and produces a
multi-section markdown analysis with prioritized recommendations. After the report
prints, `mh` drops into an interactive chat loop where the user can ask follow-up
questions or invoke `run N` to execute one of the proposed fixes (from a fixed allowlist,
confirmation-gated).

---

## Goals

1. **Validate the synthesis thesis**: in real daily use, does an LLM produce useful root-cause
   explanations from heterogeneous Mac diagnostic signals? Without this, the entire
   project direction is wrong.
2. **Ship in a focused build window**: one weekend of focused work, scope-controlled to
   prevent endless polishing.
3. **Replace `top` / `airport` / Activity Monitor** in Charlie's workflow for at least 5
   instances during the first week of dogfooding.

## Non-goals (explicitly out of scope for v0.1)

- Menu bar GUI (deferred to v0.2; current build is CLI-only).
- Background polling / always-on monitoring.
- App Store distribution; notarization.
- Local LLM fallback (Ollama).
- Multiple users / sharing the binary.
- Sudo-required system configuration changes (DNS server, energy settings).
- File deletions outside `~/Library/Caches` and `~/Library/Developer`.
- `mh wifi`, `mh cpu`, etc. surface-specific subcommands (deferred to v0.2 aliases).

---

## Architecture

```
mh
 ↓ [t=0]
preflight: codex installed? authed? tty interactive?
 ↓ [~50ms]
gatherShallow() — parallel, each probe ≤ 500ms timeout
 ├─ df -h                                           → DiskShallow
 ├─ pmset -g batt                                   → BatteryShallow
 ├─ top -l 1 -n 5 -stats pid,cpu,mem,command        → CPUShallow
 └─ networksetup + airport -I                       → WifiShallow
 ↓ [~300-500ms]
codex exec --json --output-schema triage_schema.json (NEW session)
   → capture thread_id from first JSONL event
   → parse final agent_message JSON: { domain, reasoning }
 ↓ [~6-7s including Codex cold start]
if domain == "none": print "Everything looks normal" + exit 0

gatherDeep(domain) — parallel where possible, each probe ≤ 3s timeout
   e.g., wifi: system_profiler SPAirPortDataType, dig +stats, ping gateway, traceroute -m 5
 ↓ [~1-3s]
codex exec resume <thread_id> --json --output-schema analysis_schema.json
   → returns { report: markdown, fixes: [{ id, action, params_json, description, dangerous }] }
 ↓ [~7-10s]
print report + numbered fix list (total time to first report: ~15-20s)
 ↓
chat loop:
   read line
   if line matches "run \d+":
       fix = fixes[N]
       revalidate(fix)               — PID alive? bundle id resolves? interface up?
       if fix.dangerous: extra confirmation prompt
       (executableURL, argv) = build(fix)
       run Process, capture stdout/stderr, audit-log
       print outcome
   else:
       codex exec resume <thread_id> <line>   — NO snapshot re-send
       print response
   loop until 'exit' / Ctrl-D / max_turns (default 6)
```

Total snapshot-to-report latency: **~15-20s**. This is dominated by Codex subprocess cold
start and model inference time, not signal gathering. Real-time progress indicators are
required for acceptable UX:

```
[gathering signals... 0.3s]
[triaging... 6.5s]
[deep gather: cpu... 1.8s]
[analyzing... 8.2s]

## Health Report
...
```

---

## Components

Six Swift source files. Each component has one responsibility, a clear interface, and is
independently unit-testable.

### 1. `Domain.swift` + `ProbeResult.swift` — shared types

```swift
enum Domain: String, Codable {
    case wifi, cpu, disk, battery
}

enum ProbeResult<T> {
    case value(T)
    case unavailable    // binary not installed (e.g., docker missing)
    case timedOut       // hit the per-probe timeout
    case failed(String) // ran, but stderr non-empty or unexpected output
}
```

Every signal-gathering function returns `ProbeResult<T>`, never throws. A partial snapshot
is always constructible.

### 2. `SignalGatherer.swift` — two-mode gatherer

```swift
struct ShallowSnapshot {
    let cpu: ProbeResult<CPUShallow>        // top processes, load avg
    let wifi: ProbeResult<WifiShallow>      // SSID, RSSI, channel, link rate
    let disk: ProbeResult<DiskShallow>      // %full per mount
    let battery: ProbeResult<BatteryShallow> // %charge, AC state, recent drain
    let timestamp: Date
}

struct DeepSnapshot {
    let domain: Domain
    let shallow: ShallowSnapshot   // included for cross-domain context
    let deep: DeepData             // domain-specific richer probes
    let timestamp: Date
}

actor SignalGatherer {
    func gatherShallow() async -> ShallowSnapshot {
        async let cpu = CPUGatherer.shallow()       // top -l 1 -n 5
        async let wifi = WifiGatherer.shallow()     // networksetup, airport -I
        async let disk = DiskGatherer.shallow()     // df -h
        async let battery = BatteryGatherer.shallow() // pmset -g batt
        return await ShallowSnapshot(...)
    }

    func gatherDeep(_ domain: Domain, shallow: ShallowSnapshot) async -> DeepSnapshot
}
```

Each gatherer enforces its own timeout via `Task` cancellation. Internal subprocess calls
use `Process` with `executableURL` + argv arrays, never `/bin/sh -c`.

### 3. `PromptBuilder.swift` — prompt + schema constructor

```swift
struct TriagePrompt {
    let prompt: String
    let schemaFile: URL  // path to triage_schema.json on disk
}

struct AnalysisPrompt {
    let prompt: String
    let schemaFile: URL  // path to analysis_schema.json on disk
}

enum PromptBuilder {
    static func triage(_ snapshot: ShallowSnapshot) -> TriagePrompt
    static func analysis(_ deep: DeepSnapshot) -> AnalysisPrompt
}
```

**Schemas live in resources** (`Sources/mh/Resources/triage_schema.json` and `analysis_schema.json`).
They are bundled with the binary at build time and extracted to a temp path at runtime
for `codex exec --output-schema` to consume.

**Strict-mode rules** for every schema (enforced by OpenAI Structured Outputs):
- Every nested object MUST declare `additionalProperties: false`.
- `required` MUST include every key in `properties` — there are no optional fields.
- Variadic params handled via a string field `params_json` that the consumer parses.

### 4. `CodexClient.swift` — subprocess wrapper

```swift
struct CodexResponse<T: Decodable> {
    let value: T
    let threadId: String
}

actor CodexClient {
    private(set) var threadId: String?

    /// Start a new conversation. Returns parsed structured response + captures threadId.
    func openSession<T: Decodable>(
        prompt: String,
        schemaFile: URL,
        decoding: T.Type
    ) async throws -> T

    /// Continue an existing conversation. Schema can be overridden per turn.
    func resume<T: Decodable>(
        prompt: String,
        schemaFile: URL?,
        decoding: T.Type
    ) async throws -> T
}
```

**Implementation details:**
- Spawns `codex exec [resume <thread_id>] --json --output-schema <path>` with prompt via
  stdin (avoids argv length limits — confirmed needed via spike, prompts can be ~20KB).
- Parses JSONL output line-by-line:
  - First event `{"type":"thread.started","thread_id":"<uuid>"}` → capture thread ID
  - Final `{"type":"item.completed","item":{"type":"agent_message","text":"<JSON>"}}` → parse text as `T`
  - `{"type":"error",...}` → throw with message
- Per-call timeout: 30s. Above that, kill subprocess, surface error.
- Caller can pass `schemaFile: nil` on resume to inherit the previous schema (sticky behavior, confirmed in spike).

### 5. `FixExecutor.swift` — allowlisted, validated, audited

```swift
enum FixAction: String, Codable {
    case flushDns = "flush_dns"
    case restartWifi = "restart_wifi"
    case quitApp = "quit_app"
    case killPid = "kill_pid"
    case clearXcodeDerivedData = "clear_xcode_derived_data"
    case clearNpmCache = "clear_npm_cache"
    case dockerStopAll = "docker_stop_all"
}

struct ProposedFix: Codable {
    let id: Int
    let action: FixAction
    let paramsJson: String      // raw JSON string from Codex, parsed below
    let description: String
    let dangerous: Bool
}

// Action-specific param structs. `decodeParams(paramsJson, for: action)` dispatches
// on `action` and decodes the JSON string into the right type. Strict charset/range
// validators run inside each struct's decoder.
struct FlushDnsParams: Codable {}                              // no params
struct RestartWifiParams: Codable { let interface: String }    // validated against /^en\d+$/
struct QuitAppParams: Codable { let bundleId: String }         // validated /^[a-zA-Z0-9.-]+$/
struct KillPidParams: Codable { let pid: Int32 }               // validated > 1 (never init), and process exists
struct ClearXcodeDerivedDataParams: Codable {}                 // no params; path is hardcoded
struct ClearNpmCacheParams: Codable {}                         // no params
struct DockerStopAllParams: Codable {}                         // no params

struct FixExecutor {
    func execute(_ fix: ProposedFix, force: Bool = false) async throws -> ExecutionResult {
        let params = try decodeParams(fix.paramsJson, for: fix.action)
        try await revalidate(fix.action, params: params)
        if fix.dangerous && !force {
            try await confirmInteractively()
        }
        let (url, args) = buildCommand(fix.action, params: params)
        let result = try await runProcess(executableURL: url, arguments: args)
        try auditLog(fix: fix, params: params, command: (url, args), result: result)
        return result
    }
}
```

**Hard rules:**
- `buildCommand` is a `switch` over `FixAction`. No string interpolation of user input.
  Example:
  ```swift
  case .flushDns:
      return (URL(fileURLWithPath: "/usr/bin/sudo"),
              ["dscacheutil", "-flushcache"])
  case .quitApp:
      let bundleId = params.bundleId  // already validated as `[a-zA-Z0-9.-]+`
      return (URL(fileURLWithPath: "/usr/bin/osascript"),
              ["-e", "tell application id \"\(bundleId)\" to quit"])
  ```
  The `quitApp` case is the closest to interpolation. It is acceptable because `bundleId`
  is regex-validated to bundle-id charset before reaching this point, and `osascript -e`
  is the only osascript variant we use (no `-l JavaScript`).
- `revalidate` runs immediately before execution. PID alive? Bundle id resolves to a
  running app? Interface present? If not, refuse with stale-state message.
- Audit log path: `~/.local/state/mh/log.jsonl`. Each line: proposed fix, validated params,
  exact executable + argv, exit code, stdout/stderr first 1KB, timestamps before and
  after.
- Dangerous fixes (`kill_pid`, `docker_stop_all`, `clear_xcode_derived_data`,
  `clear_npm_cache`) require explicit `y` confirmation even at Tier-1. Codex sets the
  `dangerous` boolean; if Codex ever forgets to mark something dangerous, we fall back to
  a per-action default table.

### 6. `ChatLoop.swift` — REPL

```swift
@main
struct MH: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mh",
        abstract: "macOS diagnostic CLI with LLM synthesis",
        subcommands: [Doctor.self]   // `mh doctor` runs preflight checks only
    )

    func run() async throws {
        try preflight()                                    // codex installed/authed/tty
        let shallow = await SignalGatherer().gatherShallow()
        let codex = CodexClient()
        let triage = try await codex.openSession(
            prompt: PromptBuilder.triage(shallow).prompt,
            schemaFile: bundledSchema("triage"),
            decoding: TriageResponse.self
        )
        if triage.domain == "none" {
            print("Everything looks normal."); return
        }
        let deep = await SignalGatherer().gatherDeep(triage.domain, shallow: shallow)
        let analysis = try await codex.resume(
            prompt: PromptBuilder.analysis(deep).prompt,
            schemaFile: bundledSchema("analysis"),
            decoding: AnalysisResponse.self
        )
        renderReport(analysis)
        try await ChatLoop(codex: codex, executor: FixExecutor(),
                           fixes: analysis.fixes).run()
    }
}

actor ChatLoop {
    func run() async {
        var turns = 0
        while turns < maxTurns, let line = readLine() {
            if line == "exit" { return }
            if let n = parseRunCommand(line) {
                await handleFix(n)        // routes to FixExecutor.execute
            } else {
                await handleFollowUp(line) // routes to codex.resume
            }
            turns += 1
        }
        if turns >= maxTurns {
            print("(turn budget reached; restart `mh` for a fresh session)")
        }
    }
}
```

**Conversation turn budget:** default `maxTurns = 6`. Empirically (from spike), this keeps
total per-session token cost in a reasonable range (~80K input tokens by turn 6) before
diminishing returns from accumulated context.

---

## Data flow

See "Architecture" above for the diagram. Key flow properties:

1. **Two LLM calls per `mh` invocation** (triage + analysis), plus N follow-up calls.
2. **Conversation state lives in Codex**, not in `mh`. We only pass the `thread_id`. This
   means crash recovery doesn't preserve state — acceptable for v0.1.
3. **`thread_id` is logged to `~/.local/state/mh/sessions.jsonl`** so the user can manually
   resume past sessions via `codex exec resume <id>` if they want to debug their own tool
   usage. Not surfaced in v0.1 UX.
4. **Deep gather always uses the shallow snapshot as context** — Codex's analysis prompt
   includes the original shallow data plus the new deep data, so cross-domain awareness is
   preserved (e.g., "your CPU is hot AND wifi is on 2.4GHz; analyzing wifi but noting CPU").

---

## Error handling

The principle: every external operation can fail. Failure degrades gracefully, never crashes.

| Failure | Behavior | Exit code |
|---|---|---|
| `codex` binary not in PATH | Print `brew install codex` (or npm path), exit 2 | 2 |
| `codex` not authenticated | Print `codex login`, exit 2 | 2 |
| Codex network failure during call | Print local shallow snapshot as fallback report, exit 0 | 0 |
| Codex returns schema-violating JSON | Log raw output to `~/.local/state/mh/error.log`, print: "LLM returned malformed response; here's what I gathered locally:" + snapshot summary | 0 |
| Codex rate limit | Wait + retry once with backoff, then degrade to local snapshot | 0 |
| Codex subprocess timeout (30s) | Kill subprocess, fall through to local snapshot | 0 |
| Probe binary missing | `ProbeResult.unavailable`, included in snapshot | n/a |
| Probe timeout (500ms shallow, 3s deep) | `ProbeResult.timedOut`, included in snapshot | n/a |
| Probe non-zero exit | `ProbeResult.failed(stderr)`, included in snapshot | n/a |
| Fix revalidation fails (PID gone) | Print "Target no longer exists (snapshot ~Ns old); re-run `mh`?" | n/a |
| Fix execution fails | Log full stderr + exit code; print user-friendly error | n/a |
| `sudo` needed but not in sudoers cache | Refuse; tell user to run the command manually | n/a |
| Snapshot stale (>60s) at `run N` time | Warn: "Snapshot is Ns old; results may be stale. Continue? [y/N]" | n/a |

**`mh doctor` subcommand**: runs all environment checks (codex install, auth, common
probe tools) and reports. Lets the user debug the tool itself without running a diagnostic.

---

## Testing strategy

Tests encode *why* behavior matters, not just what (per repo CLAUDE.md Rule 5).

**Unit tests** (Swift Testing or XCTest):

| Component | What's tested | How |
|---|---|---|
| `SignalGatherer` | Each gatherer returns correct `ProbeResult` for success / missing binary / timeout / malformed output | Inject mock `Process` runner returning fixture stdout/stderr/exit codes |
| `PromptBuilder` | Generated prompt matches golden file; emitted schema passes strict-mode validation | Snapshot tests + JSON-schema lint |
| `CodexClient` | `thread_id` is captured from first JSONL event; resume call doesn't re-send original prompt; schema violations surface as typed errors | Inject fake codex subprocess returning scripted JSONL |
| `FixExecutor` | Each `FixAction` produces correct `(executableURL, argv)`; revalidation refuses on stale PIDs / missing bundles; dangerous fixes require confirmation; param payloads with shell-special chars cannot escape argv boundary | Inject fake `Process` runner, assert exact arg arrays |
| `ChatLoop` | "run 2" routes to `FixExecutor.execute(fixes[1])`; freeform routes to `codex.resume`; "exit" terminates cleanly; maxTurns is enforced | Drive stdin via pipe, assert stdout |

**Integration test**: `tests/fixtures/` contains real captured outputs (`top.txt`,
`system_profiler.txt`, `df.txt`, etc.). One end-to-end test replays fixtures through the
full pipeline up to (but not calling) Codex, and asserts the constructed prompt matches a
golden file.

**Manual validation criteria for v0.1 done:**
- Used daily for one week.
- At least 3 separate occasions where the report explained something Charlie did not
  already know.
- Zero unintended auto-fix executions across the week.
- Charlie reaches for `mh` instead of `top` / `airport` / Activity Monitor at least 5
  times.

**Out of test scope:**
- Real Codex API behavior (out of scope; the subprocess boundary is what we control).
- Real network conditions (manual).
- macOS version variance (manual on whatever Charlie is running).

---

## Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| LLM synthesis is not actually useful in practice (the core thesis fails) | Medium | Project pivots | Validate with one week of daily use before adding any v0.2 scope |
| ~15-20s latency feels too slow to reach for | Medium | Tool gets abandoned | Real-time progress indicators between stages; consider caching last snapshot for follow-up Qs |
| Codex CLI changes flag semantics or output format | Low | One-time port work | Pin to `codex-cli` version range in README; integration test catches breakage |
| Codex auto-marks dangerous fix as non-dangerous | Low | Unintended execution | Per-action default `dangerous` table in `FixExecutor` overrides; never trust LLM-set flag alone for `kill_pid` / `docker_stop_all` / cache-clear |
| Param injection via crafted Codex output | Low | Shell escape | Strict param decoding (typed Swift structs, no `Any`); param validators with charset whitelists; `Process` with `executableURL` + argv (never `/bin/sh -c`) |
| Conversation context grows past Codex limits | Medium | Errors in long sessions | `maxTurns = 6` budget; print "restart `mh` for fresh session" message |
| User runs `mh` without `codex login` | High (first-run) | Confusing failure | `mh doctor` subcommand; preflight check on every invocation |
| `quitApp` osascript edge cases (localized app names, malformed bundle ids) | Low | Wrong app quits or no-op | Bundle-id charset validator before reaching osascript; runtime check that bundle id resolves to a running app |

---

## Open questions (resolve before or during implementation)

1. **Schema file distribution**: Bundled as resources via `swift package`, or embedded as
   Swift string literals? Resources are cleaner but require manifest entries.
2. **Output rendering**: Markdown report goes to terminal — render with ANSI styling
   (bold/colors via something like `swift-markdown-ui`-equivalent for CLIs) or print raw?
   Probably raw for v0.1.
3. **Audit log location**: `~/.local/state/mh/log.jsonl` follows XDG; alternative is
   `~/Library/Logs/mh/`. XDG chosen for v0.1; reconsider before v0.2.
4. **Empty/none case**: What does `mh` print when triage returns `"none"`? Current spec
   says "Everything looks normal." — could be improved with a "here's what looked fine"
   summary. Defer to first dogfood pass.

---

## Out of scope for v0.1 (explicit)

- Menu bar GUI (v0.2)
- Background polling
- Local LLM fallback
- Subscription sharing / multi-user
- App Store distribution
- Sudo system config changes (DNS server, energy)
- Custom fix definitions / user-extensible allowlist
- `mh wifi` / `mh cpu` / `mh disk` / `mh battery` surface aliases (v0.2)
- Persistent cross-session memory (`thread_id` is logged but not surfaced)
- Telemetry / usage metrics
- Multi-shell completion scripts

---

## v0.1 build order (high-level, not the implementation plan)

This section sketches an order; the actual implementation plan will be produced by the
`writing-plans` skill after this spec is approved.

1. `Domain.swift`, `ProbeResult.swift` — foundational types.
2. `SignalGatherer.shallow()` for one domain (start with CPU) — exercise the `ProbeResult`
   pattern end-to-end against real `top` output.
3. `PromptBuilder.triage()` + bundled `triage_schema.json` — exercise the schema rules.
4. `CodexClient.openSession()` — first real Codex integration; captures `thread_id`,
   returns typed response.
5. `mh doctor` subcommand — gives Charlie a debugging surface before the full pipeline
   exists.
6. Extend `SignalGatherer.shallow()` to all 4 domains.
7. `SignalGatherer.gatherDeep()` for CPU domain.
8. `PromptBuilder.analysis()` + bundled `analysis_schema.json`.
9. `CodexClient.resume()`.
10. `FixExecutor` with first two `FixAction`s (`flushDns`, `restartWifi` — safest).
11. `ChatLoop` — wire it all together.
12. Add remaining `FixAction`s with revalidators.
13. Extend deep gather to wifi, disk, battery.
14. End-to-end manual test → ship.
