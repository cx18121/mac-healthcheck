# Mac Healthcheck

Native macOS menu bar app that answers "why is my Mac misbehaving right now?" in one sentence of plain English, with optional one-click fix. LLM-powered root-cause synthesis over heterogeneous system signals (CPU/RAM/wifi/disk/battery/processes).

> **Status: seed.** Scaffolded 2026-05-21 from the cxkb seed. No code yet. **Needs a design pass before coding.** Pick up here.

## The thesis

Traditional perf monitors dump numbers. The synthesis step ("you have 6 Chrome tabs playing video AND Time Machine is running AND you're on a congested 2.4GHz channel — that's why your call is choppy") is exactly what LLMs are good at. The diagnostic surface is too heterogeneous for rule-based logic.

This app is the synthesis layer over native diagnostic APIs.

## Before writing code: design pass

The scope ambiguity here is real. **Don't open Xcode yet.** Resolve these first:

### 1. Surface scope for v0.1

The original seed lists 7 surfaces (CPU/RAM, wifi, disk, battery, mystery processes, browser, one-click fixes). All of them at once is too much. Pick the smallest one that already feels useful daily. Recommended candidates:
- **Just wifi triage** — channel scan + DNS lookup + gateway-vs-ISP latency. Useful daily, tractable, exercises the LLM-synthesis core.
- **Just disk space** — "what's eating my disk" with the actual culprits (Xcode DerivedData, npm caches, Docker, big Downloads). Useful weekly.
- **Just CPU/RAM hogs** — "what's slow + why" with named patterns ("Slack emoji cache bug, common after long uptime").

Pick one for v0.1. Add others later.

### 2. Polling shape

- **On-demand only** — user clicks menu bar icon, app reads signals, calls LLM, shows result. Burns one LLM call per query. Cheap. No background process logic.
- **Background poll** — daemon watches signals, surfaces a notification when something crosses a threshold. Cooler but burns tokens and needs careful threshold design.

Recommend on-demand for v0.1. Background is a later add.

### 3. Model choice

- Claude API (Haiku probably enough for this) — best quality, requires network + API key + cost.
- Local model (Ollama / Llama.cpp + a small model) — privacy, offline, free, but quality drop.
- Hybrid (try local first, fallback to API on low-confidence) — natural fit for [Charlie's eventual ELM Router idea](~/Documents/cxkb/topics/Idea Pool 2.md). Defer.

Recommend Claude API (Haiku 4.5) for v0.1.

### 4. Distribution

App Store sandbox limits IOKit access — that's a dealbreaker for this app's core capabilities. Skip App Store. Direct-download notarized DMG.

## Native APIs to know

| Surface | API |
|---|---|
| CPU/RAM/processes | `proc_pidinfo`, `host_statistics`, `sysctl` |
| Wifi | `CoreWLAN` framework, `airport scan`, `dig`, `traceroute` |
| Disk | `NSFileManager` + known-cache path scan |
| Battery | `IOPMCopyCPUPowerStatus`, IOKit power-source registry |
| System events | `os_log` stream, `log show` |

## Why native (not Electron)

IOKit, sysctl, CoreWLAN, system events, Accessibility — all native-only. Menu bar UX (NSStatusItem) is the right surface.

## Working name candidates

Doctor, Pulse, Triage, Why?, Mac Healthcheck. Codename only — pick at design pass.

## References

- Full project page: `~/Documents/cxkb/projects/Mac Healthcheck.md`
- Source idea capture: `~/Documents/cxkb/raw/Idea - Mac Health Agent.md`
- Sibling diagnostics cluster: `~/School/cs_misc/autoperf/`, `~/School/cs_misc/gatekeeper/`, `~/School/cs_misc/cve-intel/`, `~/School/cs_misc/vulnscan/`

## When this is "done enough"

v0.1 ships when Charlie hits one of his chosen surfaces (wifi/disk/CPU) in real life and reaches for *this* app instead of `top` / `airport` / Activity Monitor.

## Suggested next step in this terminal

```
# In Claude Code:
/gsd:discuss-phase
# or
/gsd:new-project
```

Resolve the four design questions above before touching Swift.
