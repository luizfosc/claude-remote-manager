---
protocol: code-review-ping-pong
type: fix
round: 6
date: "2026-04-08"
fixer: "Claude Opus"
commit_sha: "pending"
branch: "main"
based_on_review: "round-6.md"
files_changed:
  - "enable-agent.sh"
  - "core/bus/send-telegram.sh"
fixes:
  - issue_id: "6.1"
    status: "fixed"
  - issue_id: "6.2"
    status: "fixed"
---

# Code Ping-Pong — Round 6 Fix Report

## Fixes Implemented

### 🟠 6.1 HIGH — Token conflict guard now covers --restart path

**What:** Moved the entire BOT_TOKEN conflict detection block to **before** the `--restart` early-exit branch. Both `enable` and `restart` now validate that no other enabled agent shares the same token.

**Where:** `enable-agent.sh:46-68` (moved up from lines 70-94)

**Before:** Token check was at line 70, but `--restart` exits at line 67 — never reaching validation.  
**After:** Token check runs at line 46, before both the restart branch (line 70) and the normal enable path.

---

### 🟠 6.2 HIGH — Markdown fallback preserves reply_markup

**What:** The fallback retry now checks if `KEYBOARD` is set. When present, it rebuilds a JSON payload with `reply_markup` but without `parse_mode`, preserving inline buttons. When absent, it falls back to plain text as before.

**Where:** `core/bus/send-telegram.sh:100-113`

**Before:** Fallback always used `-d chat_id` + `--data-urlencode text` without `reply_markup`, breaking all keyboard-based flows (permission approval, AskUserQuestion, etc.).  
**After:** Two-branch fallback — with keyboard (JSON payload preserving `reply_markup`) and without (plain text).

---

## Validation

```
$ bash -n enable-agent.sh       → OK
$ bash -n core/bus/send-telegram.sh → OK
```

## 📊 Summary

- **Fixed:** 2 (2 HIGH)
- **Regressions introduced:** none
- **Files changed:** 2
