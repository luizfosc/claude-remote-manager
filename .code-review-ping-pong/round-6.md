---
protocol: code-review-ping-pong
type: review
round: 6
date: "2026-04-08"
reviewer: "Codex"
commit_sha: "5c7dd1f"
branch: "main"
based_on_fix: "round-5-fixed.md"
files_in_scope:
  - "enable-agent.sh"
  - "disable-agent.sh"
  - "core/bus/_telegram-curl.sh"
  - "core/bus/check-telegram.sh"
  - "core/bus/send-telegram.sh"
  - "core/bus/hard-restart.sh"
  - "core/scripts/fast-checker.sh"
  - "bootstrap.sh"
  - "core/bus/hook-permission-telegram.sh"
score: 8
verdict: "CONTINUE"
issues:
  - id: "6.1"
    severity: "HIGH"
    title: "Duplicate-token guard is bypassed on --restart"
    file: "enable-agent.sh"
    line: 51
    suggestion: "Run the BOT_TOKEN conflict check before the early `--restart` exit path, or share the validation in a helper used by both enable and restart."
  - id: "6.2"
    severity: "HIGH"
    title: "Markdown fallback drops inline keyboards and breaks Telegram approval flows"
    file: "core/bus/send-telegram.sh"
    line: 101
    suggestion: "When retrying after a Markdown parse failure, preserve `reply_markup` for keyboard-based messages instead of falling back to plain text without buttons."
---

# Code Ping-Pong — Round 6 Review

## 🎯 Score: 8/10 — CONTINUE

## Issues

### 🟠 HIGH

#### Issue 6.1 — Duplicate-token guard is bypassed on --restart
- **File:** `enable-agent.sh`
- **Line:** 51
- **Code:** `if [[ "${RESTART}" == "true" ]]; then ... exit 0` before the new token-conflict block
- **Problem:** The new duplicate-token protection only runs in the normal enable path. `./enable-agent.sh <agent> --restart` returns through the early restart branch before reaching the new validation at lines 70-94, so an already-enabled conflicting agent can still be restarted into the same destructive polling race the fix was meant to prevent.
- **Suggestion:** Move the BOT_TOKEN conflict check above the `RESTART` branch or factor it into a shared function that both enable and restart call before reloading launchd.

#### Issue 6.2 — Markdown fallback drops inline keyboards and breaks Telegram approval flows
- **File:** `core/bus/send-telegram.sh`
- **Line:** 101
- **Code:** `RESPONSE=$(telegram_api_post "sendMessage" -d chat_id="${CHAT_ID}" --data-urlencode "text=${MESSAGE}")`
- **Problem:** The fallback for fix 4.6 retries failed Markdown messages as plain text, but it discards `reply_markup`. That regresses keyboard-driven flows that depend on `send-telegram.sh`, especially `core/bus/hook-permission-telegram.sh:107-115`, which sends Approve/Deny buttons through this helper. On any Markdown parse error, the retry succeeds without buttons, leaving the user with a permission prompt they cannot answer and causing an eventual timeout/auto-deny.
- **Suggestion:** Preserve the keyboard in the fallback path. For messages with `KEYBOARD`, rebuild the JSON payload without `parse_mode` but with the original `reply_markup`.

## ⚠️ Regressions
- Yes. Fix 4.6 introduced a functional regression in keyboard-based Telegram messages: Markdown fallback now succeeds, but interactive approval buttons are lost.
- The rest of the round-5 fixes largely hold: timeout hardening, disable cleanup, media download gating, safety-net marker usage, and bootstrap dependency checks all validate against the current tree.

## ✅ What Is Good
- The duplicate-token protection logic itself is correct for fresh enables; it scans enabled agents and compares `BOT_TOKEN` values before activating a new poller.
- `disable-agent.sh` now cleans the fast-checker pid/lock and Telegram state, which closes the stale-poller problem from round 5.
- `_telegram-curl.sh` now centralizes request timeouts, which materially reduces the chance of the Telegram loop hanging forever on one network call.
- The media-download fix is structurally sound: `check-telegram.sh` no longer treats a failed file fetch as a successful update, and `fast-checker.sh` suppresses offset commits when a `download_error` is present.
- `bash -n` still passes for all reviewed shell scripts in scope.

## 📊 Summary
- Total: 2, 🔴 CRITICAL: 0, 🟠 HIGH: 2, 🟡 MEDIUM: 0, 🟢 LOW: 0
- Regressions: 1
