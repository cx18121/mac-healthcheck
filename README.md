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
