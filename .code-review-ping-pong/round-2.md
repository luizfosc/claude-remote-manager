---
protocol: code-review-ping-pong
type: review
round: 2
date: "2026-04-07"
reviewer: "Codex"
commit_sha: "5e8cb03"
branch: "main"
based_on_fix: "round-1-fixed.md"
files_in_scope:
  - "core/scripts/fast-checker.sh"
  - "core/scripts/agent-wrapper.sh"
  - "core/scripts/crash-alert.sh"
  - "core/scripts/generate-launchd.sh"
  - "core/bus/hard-restart.sh"
  - "core/bus/hook-permission-telegram.sh"
  - "core/bus/send-telegram.sh"
  - "enable-agent.sh"
  - "disable-agent.sh"
  - "bootstrap.sh"
score: 9
verdict: "CONTINUE"
issues:
  - id: "2.1"
    severity: "HIGH"
    title: "Duplicate messages still trigger the post-injection busy ack path"
    file: "core/scripts/fast-checker.sh"
    line: "263-265,738-743"
    suggestion: "Make `inject_messages` distinguish `injected` from `dedup-skipped`, and only send auto-replies / increment counters for real injections."
---

# Code Ping-Pong — Round 2 Review

## 🎯 Score: 9/10 — CONTINUE

---

## Issues

### 🟠 HIGH

> Issues that cause incorrect behavior or significant quality problems.

#### Issue 2.1 — Duplicate messages still trigger the post-injection busy ack path
- **File:** `core/scripts/fast-checker.sh`
- **Line:** 263-265, 738-743
- **Code:**
  ```bash
  if [[ -f "$DEDUP_FILE" ]] && grep -qxF "$msg_hash" "$DEDUP_FILE" 2>/dev/null; then
      log "Dedup: skipping duplicate (hash: ${msg_hash:0:8})"
      return 0
  fi
  ...
  if inject_messages "$MESSAGE_BLOCK"; then
      INJECT_COUNT=$((INJECT_COUNT + 1))
      if [[ -n "${PENDING_BUSY_ACK_CHAT_ID:-}" ]] && ! is_agent_idle; then
          auto_reply_busy "$PENDING_BUSY_ACK_CHAT_ID"
      fi
  fi
  ```
- **Problem:** O fix do round 1 moveu o auto-reply para depois de `inject_messages`, mas `inject_messages` continua retornando sucesso (`0`) quando descarta uma mensagem por dedup. Com isso, o chamador ainda entra no bloco “successful injection”, incrementa `INJECT_COUNT` e pode mandar `Got it, processing...` para uma mensagem que acabou de ser ignorada como duplicata. Ou seja: o bug 1.5 continua reproduzível no caminho de dedup.
- **Suggestion:**
  ```bash
  inject_messages() {
      ...
      if duplicate; then
          return 10  # explicit dedup-skipped status
      fi
      ...
      return 0
  }
  
  inject_messages "$MESSAGE_BLOCK"
  inject_status=$?
  if [[ $inject_status -eq 0 ]]; then
      INJECT_COUNT=$((INJECT_COUNT + 1))
      auto_reply_busy ...
  elif [[ $inject_status -eq 10 ]]; then
      PENDING_BUSY_ACK_CHAT_ID=""
  fi
  ```

---

## Regressions

> Issues introduced by fixes from the previous round. Leave empty if first round or no regressions.

- none

---

## ✅ What Is Good

> Explicitly list things that are well-implemented. The fixer must NOT change these.

- `core/bus/hard-restart.sh:37-45` agora limpa `session-start` e `dedup` juntos, o que fecha corretamente o problema de estado stale em restarts fresh.
- `core/scripts/agent-wrapper.sh:306-333` cobre tanto o refresh da sessão quanto o startup inicial com limpeza de dedup, evitando depender de um único caminho de relaunch.
- `core/scripts/fast-checker.sh:99-106` tornou os thresholds de frozen detection configuráveis por `config.json`, com defaults bem mais realistas para workload de Claude Code.
- `core/scripts/fast-checker.sh:792-845` separa `ACTIVE_PANE_HASH` e `PASSIVE_PANE_HASH`, removendo a contaminação entre os dois detectores de congelamento.
- Os 10 arquivos do escopo continuam com sintaxe shell válida; `bash -n` passou para todos.

---

## 📊 Summary

- **Total issues:** 1
- **By severity:** 🔴 0 CRITICAL, 🟠 1 HIGH, 🟡 0 MEDIUM, 🟢 0 LOW
- **Regressions from previous round:** none
- **Next action:** Fix issues and request new review
