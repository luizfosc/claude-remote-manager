---
protocol: code-review-ping-pong
type: review
round: 5
date: "2026-04-08"
reviewer: "Codex"
commit_sha: "6846ef7"
branch: "main"
based_on_fix: null
files_in_scope:
  - "core/scripts/fast-checker.sh"
  - "core/scripts/agent-wrapper.sh"
  - "core/scripts/crash-alert.sh"
  - "core/scripts/generate-launchd.sh"
  - "core/bus/hard-restart.sh"
  - "core/bus/hook-permission-telegram.sh"
  - "core/bus/send-telegram.sh"
  - "core/bus/check-telegram.sh"
  - "core/bus/_telegram-curl.sh"
  - "enable-agent.sh"
  - "disable-agent.sh"
  - "bootstrap.sh"
score: 6
verdict: "CONTINUE"
issues:
  - id: "5.1"
    severity: "CRITICAL"
    title: "Activation still allows two enabled agents to share the same polling token"
    file: "enable-agent.sh"
    line: 91
    suggestion: "Before enabling or restarting an agent, scan other enabled agents' `.env` files for duplicate `BOT_TOKEN` values and abort on conflict."
  - id: "5.2"
    severity: "HIGH"
    title: "Disabling an agent leaves the Telegram poller and state behind"
    file: "disable-agent.sh"
    line: 22
    suggestion: "Kill the fast-checker explicitly and remove its pid/lock, dedup, offset, and session marker files during disable."
  - id: "5.3"
    severity: "HIGH"
    title: "Telegram transport has no client-side timeouts, so one hung curl can freeze the poll loop"
    file: "core/bus/_telegram-curl.sh"
    line: 18
    suggestion: "Add strict curl timeouts and retry policy in the shared helper, e.g. `--connect-timeout` and `--max-time`, so polling cannot block indefinitely."
  - id: "5.4"
    severity: "HIGH"
    title: "Media updates are acknowledged even when the file download failed"
    file: "core/bus/check-telegram.sh"
    line: 95
    suggestion: "Only emit photo/document/audio/voice/video payloads after `telegram_file_download` succeeds and the local file exists; otherwise keep the offset uncommitted for retry or emit a structured failure."
  - id: "5.5"
    severity: "HIGH"
    title: "Context-threshold safety net still races against the main loop"
    file: "core/scripts/fast-checker.sh"
    line: 398
    suggestion: "Replace the forked-shell boolean check with a filesystem marker or another shared state that both processes can observe."
---

# Code Ping-Pong — Round 5 Review

## 🎯 Score: 6/10 — CONTINUE

## Issues

### 🔴 CRITICAL

#### Issue 5.1 — Activation still allows two enabled agents to share the same polling token
- **File:** `enable-agent.sh`
- **Line:** 91
- **Code:** `ENV_FILE="${AGENT_DIR}/.env"` followed by Telegram MCP setup only
- **Problem:** The production incident from the session notes is still reproducible. `enable-agent.sh` reads agent env state, but it never checks whether another enabled agent already uses the same `BOT_TOKEN` for the bus poller. Offsets remain per-agent (`core/bus/check-telegram.sh` uses `.telegram-offset-${ME}`), not per token, so two enabled agents with the same token will both poll `getUpdates`, race each other, and can duplicate or lose replies.
- **Suggestion:** Before enabling or restarting, iterate other enabled agents, read their `.env`, compare `BOT_TOKEN`, and abort with a conflict error if the token is already in use.

### 🟠 HIGH

#### Issue 5.2 — Disabling an agent leaves the Telegram poller and state behind
- **File:** `disable-agent.sh`
- **Line:** 22
- **Code:** `launchctl unload ...` then `tmux kill-session ...` with no fast-checker cleanup
- **Problem:** Round 4 was right here. Disabling only unloads launchd and kills tmux. It never kills the standalone `fast-checker.sh` process or clears `${AGENT}.fast-checker.pid`, `${AGENT}.fast-checker.lock`, `${AGENT}.dedup`, `.telegram-offset-${AGENT}`, or `${AGENT}.session-start`. That leaves a window where the agent is reported "disabled" but its poller can still run, and stale state is carried into the next enable.
- **Suggestion:** Explicitly kill `fast-checker.sh`, remove its pid/lock files, and clear Telegram/dedup/session state on disable.

#### Issue 5.3 — Telegram transport has no client-side timeouts, so one hung curl can freeze the poll loop
- **File:** `core/bus/_telegram-curl.sh`
- **Line:** 18
- **Code:** `curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/${method}" "$@"`
- **Problem:** This path is used by polling, replies, callback handling, permissions, and crash alerts. None of the shared helper calls set `--connect-timeout`, `--max-time`, or retry flags. If DNS stalls, TCP hangs, or Telegram keeps the socket open longer than expected, `check-telegram.sh` can block inside `telegram_api_get`, which freezes the main `fast-checker.sh` loop and stops both message ingestion and recovery logic.
- **Suggestion:** Centralize conservative curl timeouts and retry behavior in `_telegram-curl.sh` so every Telegram operation fails fast instead of hanging the daemon.

#### Issue 5.4 — Media updates are acknowledged even when the file download failed
- **File:** `core/bus/check-telegram.sh`
- **Line:** 95
- **Code:** `telegram_file_download "${FILE_PATH}" "${LOCAL_FILE}" 2>/dev/null || true`
- **Problem:** For photos, documents, audio, voice, and video notes, the script ignores download failure and still emits a payload that points to a local file path. `fast-checker.sh` can then inject that message successfully and commit the Telegram offset, even though the file was never downloaded. The user sees a broken local path and the original Telegram media update is lost forever because it will not be retried.
- **Suggestion:** Treat file download as part of successful processing: emit the message only when the download succeeds and the file exists, otherwise leave the update pending or surface a structured error that prevents offset commit.

#### Issue 5.5 — Context-threshold safety net still races against the main loop
- **File:** `core/scripts/fast-checker.sh`
- **Line:** 398
- **Code:** `( sleep 180; if [[ "$CONTEXT_RESTART_TRIGGERED" == "true" ]]; then`
- **Problem:** This round-4 finding is also valid. The delayed subshell captures `CONTEXT_RESTART_TRIGGERED` by value when it forks. If the main loop later clears or changes restart state, the subshell will not observe it. After 180 seconds, it can still force `do_hard_restart` even though the intended self-restart path already ran.
- **Suggestion:** Use a shared marker file under `${CRM_ROOT}/state/` for the pending restart flag and clear it from the actual restart path.

## ⚠️ Regressions
- None from `round-4.md` being fixed, because there is no `round-4-fixed.md` yet.
- I do challenge one part of round 4: issue 4.3 is directionally correct about offset safety, but the stronger, reproducible bug in the current tree is the media-download path in `check-telegram.sh`, where offsets can be committed after a failed file fetch.

## ✅ What Is Good
- `bash -n` passes for every shell script in the declared scope, so there are no obvious syntax regressions in the review target.
- `fast-checker.sh` still has the right high-level offset contract: it commits the offset only after successful injection, which is the correct boundary for text messages.
- The watchdog logic in `agent-wrapper.sh` is materially better than a naive one-shot launcher; it does attempt to revive a dead `fast-checker` and clean stale pid/lock state on restart paths.
- Telegram helper usage is at least centralized now through `_telegram-curl.sh`, which makes the timeout and retry hardening straightforward to implement in one place.

## 📊 Summary
- Total: 5, 🔴 CRITICAL: 1, 🟠 HIGH: 4, 🟡 MEDIUM: 0, 🟢 LOW: 0
- Regressions: none
