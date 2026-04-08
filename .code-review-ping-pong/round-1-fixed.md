---
protocol: code-review-ping-pong
type: fix
round: 1
date: "2026-04-07"
fixer: "Claude Code"
review_file: "round-1.md"
commit_sha_before: "5e8cb03"
branch: "main"
git_diff_stat: "4 files changed, 37 insertions(+), 31 deletions(-)"
files_changed:
  - "core/bus/hard-restart.sh"
  - "core/scripts/agent-wrapper.sh"
  - "core/scripts/fast-checker.sh"
original_score: 6
issues_fixed: 6
issues_skipped: 0
issues_total: 6
quality_checks:
  lint: "N/A"
  typecheck: "N/A"
  test: "N/A"
fixes:
  - id: "1.1"
    status: "FIXED"
    deviation: "none"
  - id: "1.2"
    status: "FIXED"
    deviation: "Also cleared dedup in the initial fast-checker startup path and in the do_hard_restart() fallback within fast-checker.sh (anti-whack-a-mole)"
  - id: "1.3"
    status: "FIXED"
    deviation: "Used ACTIVE_PANE_HASH and PASSIVE_PANE_HASH instead of the suggested variable names, and standardized both to SHA-256"
  - id: "1.4"
    status: "FIXED"
    deviation: "none — used exact suggestion with jq config.json fallback"
  - id: "1.5"
    status: "FIXED"
    deviation: "Used PENDING_BUSY_ACK_CHAT_ID pattern instead of pending_busy_ack_required flag — simpler, same effect. Auto-reply sent after inject_messages succeeds."
  - id: "1.6"
    status: "FIXED"
    deviation: "Used inline tracking instead of a helper function — fewer moving parts for a bash script. Removed duplicate document branch entirely."
---

# Code Ping-Pong — Round 1 Fix Report

**Review:** `round-1.md` (score: 6/10)
**Git base:** `5e8cb03` on `main`
**Changes:**
```
 core/bus/hard-restart.sh      |  3 +++
 core/scripts/agent-wrapper.sh |  4 ++-
 core/scripts/fast-checker.sh  | 61 ++++++++++++++++++++++---------------------
 4 files changed, 37 insertions(+), 31 deletions(-)
```

---

## Fixes Applied

### Fix for Issue 1.1 — Hard restart keeps stale dedup state
- **Status:** FIXED
- **File:** `core/bus/hard-restart.sh`
- **What changed:** Added `rm -f "${CRM_ROOT}/state/${AGENT}.dedup"` after the existing session-start cleanup, so hard-restart now clears all stale state including dedup hashes.
- **Deviation from suggestion:** None

### Fix for Issue 1.2 — Wrapper refresh path also preserves dedup state
- **Status:** FIXED
- **Files:** `core/scripts/agent-wrapper.sh`, `core/scripts/fast-checker.sh`
- **What changed:** Added dedup cleanup in three locations: (1) the session refresh path in agent-wrapper.sh where fast-checker is killed/restarted, (2) the initial fast-checker startup path in agent-wrapper.sh, and (3) the `do_hard_restart()` fallback in fast-checker.sh that directly manipulates launchctl.
- **Deviation from suggestion:** Extended the fix beyond the single location cited — grepped for all restart/refresh paths that could leave stale dedup (anti-whack-a-mole).

### Fix for Issue 1.3 — Frozen detector resets its own stale timer every passive-check cycle
- **Status:** FIXED
- **File:** `core/scripts/fast-checker.sh`
- **What changed:** Split `LAST_PANE_HASH` into two independent variables: `ACTIVE_PANE_HASH` (used by the active frozen detector with `tail -10`) and `PASSIVE_PANE_HASH` (used by the passive detector with `tail -20`). Both now use SHA-256 consistently, eliminating the hash format mismatch that caused cross-contamination.
- **Deviation from suggestion:** Used `ACTIVE_PANE_HASH`/`PASSIVE_PANE_HASH` naming (clearer than the suggested names). Also standardized both to SHA-256.

### Fix for Issue 1.4 — Soft frozen nudge fires after only 120 seconds
- **Status:** FIXED
- **File:** `core/scripts/fast-checker.sh`
- **What changed:** Both `FROZEN_SOFT_NUDGE_SECONDS` and `FROZEN_RESTART_MAX_SECONDS` are now read from `config.json` via jq, with defaults of 600s (10 min) and 900s (15 min) respectively. This is 5x and 3x the previous hardcoded values.
- **Deviation from suggestion:** None — used the exact pattern suggested.

### Fix for Issue 1.5 — Busy auto-reply is sent before dedup/injection succeeds
- **Status:** FIXED
- **File:** `core/scripts/fast-checker.sh`
- **What changed:** Removed `auto_reply_busy()` calls from inside the message parsing loop (both document and text handlers). Instead, set `PENDING_BUSY_ACK_CHAT_ID` during parsing. After `inject_messages` succeeds on line 745, the auto-reply is sent only if the agent is still busy. On injection failure, the variable is cleared without sending.
- **Deviation from suggestion:** Used a single `PENDING_BUSY_ACK_CHAT_ID` variable instead of a separate boolean flag — simpler, same behavior.

### Fix for Issue 1.6 — Non-text Telegram media bypass pending-message safeguards
- **Status:** FIXED
- **File:** `core/scripts/fast-checker.sh`
- **What changed:** Added `HUMAN_MSG_PENDING=true`, `HUMAN_MSG_CHAT_ID`, `HUMAN_MSG_PENDING_SINCE`, and `PENDING_BUSY_ACK_CHAT_ID` tracking to photo, voice/audio, and video_note handlers. Removed the duplicate `document` branch (lines 631-643) entirely — the first document handler at line 600 already covers the functionality.
- **Deviation from suggestion:** Used inline tracking per handler instead of a shared helper function — keeps the bash script simpler with fewer function indirections.

---

## Skipped Issues

None — all 6 issues fixed.

---

## Additional Improvements

- Standardized hash algorithm to SHA-256 across both active and passive frozen detection (previously mixed SHA-1 and SHA-256).
- Extended dedup cleanup to the `do_hard_restart()` fallback path in fast-checker.sh, which was not cited in the review but had the same bug pattern.

---

## Quality Checks

| Check | Result | Notes |
|-------|--------|-------|
| `bash -n` (syntax) | PASS | All 3 modified scripts pass bash syntax check |
| `npm run lint` | N/A | No linter configured (bash scripts) |
| `npm run typecheck` | N/A | No type checker (bash scripts) |
| `npm test` | N/A | No test suite |

---

## Summary

- **Issues fixed:** 6 of 6
- **Issues skipped:** 0
- **Quality checks:** bash syntax PASS on all modified files
- **Next action:** Request reviewer to run REVIEW for round 2
