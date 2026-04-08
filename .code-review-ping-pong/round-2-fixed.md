---
protocol: code-review-ping-pong
type: fix
round: 2
date: "2026-04-07"
fixer: "Claude Code"
review_file: "round-2.md"
commit_sha_before: "5e8cb03"
branch: "main"
git_diff_stat: "4 files changed, 53 insertions(+), 33 deletions(-)"
files_changed:
  - "core/scripts/fast-checker.sh"
original_score: 9
issues_fixed: 1
issues_skipped: 0
issues_total: 1
quality_checks:
  lint: "N/A"
  typecheck: "N/A"
  test: "N/A"
fixes:
  - id: "2.1"
    status: "FIXED"
    deviation: "Also reset HUMAN_MSG_PENDING and HUMAN_MSG_PENDING_SINCE on dedup-skip to prevent frozen detector from triggering on phantom pending messages"
---

# Code Ping-Pong — Round 2 Fix Report

**Review:** `round-2.md` (score: 9/10)
**Git base:** `5e8cb03` on `main`
**Changes:**
```
 core/scripts/fast-checker.sh  | 79 +++++++++++++++++++++++++------------------
 1 file changed (in this round)
```

---

## Fixes Applied

### Fix for Issue 2.1 — Duplicate messages still trigger the post-injection busy ack path
- **Status:** FIXED
- **File:** `core/scripts/fast-checker.sh`
- **What changed:** Two changes:
  1. `inject_messages()` now returns `10` (instead of `0`) when dedup skips a message, distinguishing it from successful injection (`0`) and failure (`1`).
  2. The caller now captures `$?` into `inject_status` and handles three cases:
     - `0` — real injection: increment counter, send auto-reply, commit offset
     - `10` — dedup-skipped: clear pending ack, reset `HUMAN_MSG_PENDING`, advance offset silently (no auto-reply, no inject count)
     - other — injection failed: defer offset, clear pending ack
- **Deviation from suggestion:** Also reset `HUMAN_MSG_PENDING` and `HUMAN_MSG_PENDING_SINCE` on dedup-skip to prevent the frozen detector from firing on phantom pending messages that were never actually injected.

---

## Skipped Issues

None.

---

## Quality Checks

| Check | Result | Notes |
|-------|--------|-------|
| `bash -n` (syntax) | PASS | fast-checker.sh passes syntax check |
| `npm run lint` | N/A | No linter (bash scripts) |
| `npm run typecheck` | N/A | No type checker (bash scripts) |
| `npm test` | N/A | No test suite |

---

## Summary

- **Issues fixed:** 1 of 1
- **Issues skipped:** 0
- **Quality checks:** bash syntax PASS
- **Next action:** Request reviewer to run REVIEW for round 3
