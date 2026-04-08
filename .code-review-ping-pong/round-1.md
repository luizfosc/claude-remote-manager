---
protocol: code-review-ping-pong
type: review
round: 1
date: "2026-04-07"
reviewer: "Codex"
commit_sha: "5e8cb03"
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
  - "enable-agent.sh"
  - "disable-agent.sh"
  - "bootstrap.sh"
score: 6
verdict: "CONTINUE"
issues:
  - id: "1.1"
    severity: "HIGH"
    title: "Hard restart keeps stale dedup state"
    file: "core/bus/hard-restart.sh"
    line: "34-42"
    suggestion: "Delete `${CRM_ROOT}/state/${AGENT}.dedup` together with the crash/session markers before reloading launchd."
  - id: "1.2"
    severity: "HIGH"
    title: "Wrapper refresh path also preserves dedup state"
    file: "core/scripts/agent-wrapper.sh"
    line: "306-319"
    suggestion: "Clear `${AGENT}.dedup` anywhere the wrapper tears down and relaunches Claude or fast-checker."
  - id: "1.3"
    severity: "HIGH"
    title: "Frozen detector resets its own stale timer every passive-check cycle"
    file: "core/scripts/fast-checker.sh"
    line: "791-843"
    suggestion: "Use separate hashes/state for active vs passive frozen detection, or compute the same hash in both paths."
  - id: "1.4"
    severity: "MEDIUM"
    title: "Soft frozen nudge fires after only 120 seconds"
    file: "core/scripts/fast-checker.sh"
    line: "99-100"
    suggestion: "Raise the threshold or make it configurable so long-running tool calls are not interrupted prematurely."
  - id: "1.5"
    severity: "MEDIUM"
    title: "Busy auto-reply is sent before dedup/injection succeeds"
    file: "core/scripts/fast-checker.sh"
    line: "603-606"
    suggestion: "Only send `Got it, processing...` after the message survives dedup and is actually queued for Claude."
  - id: "1.6"
    severity: "LOW"
    title: "Non-text Telegram media bypass pending-message safeguards"
    file: "core/scripts/fast-checker.sh"
    line: "620-659"
    suggestion: "Apply the same pending/busy tracking to photo, audio, voice, and video-note handlers, and remove the duplicate `document` branch."
---

# Code Ping-Pong — Round 1 Review

## 🎯 Score: 6/10 — CONTINUE

---

## Issues

### 🟠 HIGH

> Issues that cause incorrect behavior or significant quality problems.

#### Issue 1.1 — Hard restart keeps stale dedup state
- **File:** `core/bus/hard-restart.sh`
- **Line:** 34-42
- **Code:**
  ```bash
  # Reset crash counter so launchd doesn't throttle
  rm -f "${LOG_DIR}/.crash_count_today"
  
  # Write force-fresh marker so agent-wrapper.sh uses STARTUP_PROMPT (no --continue)
  mkdir -p "${CRM_ROOT}/state"
  touch "${CRM_ROOT}/state/${AGENT}.force-fresh"
  
  # Clear context tracking state so new session starts fresh
  rm -f "${CRM_ROOT}/state/${AGENT}.session-start"
  ```
- **Problem:** O restart “fresh” remove apenas crash/session metadata, mas preserva `~/.claude-remote/<instance>/state/${AGENT}.dedup`. Depois do relaunch, a primeira mensagem legítima com o mesmo payload ainda bate no hash antigo e é descartada em `fast-checker.sh`, exatamente o cenário descrito em `session.md`.
- **Suggestion:**
  ```bash
  rm -f "${LOG_DIR}/.crash_count_today"
  mkdir -p "${CRM_ROOT}/state"
  touch "${CRM_ROOT}/state/${AGENT}.force-fresh"
  rm -f \
      "${CRM_ROOT}/state/${AGENT}.session-start" \
      "${CRM_ROOT}/state/${AGENT}.dedup"
  ```

#### Issue 1.2 — Wrapper refresh path also preserves dedup state
- **File:** `core/scripts/agent-wrapper.sh`
- **Line:** 306-319
- **Code:**
  ```bash
  # Kill old fast-checker and start fresh one
  # Remove PID lock so the new instance can acquire it
  rm -f "${CRM_ROOT}/state/${AGENT}.fast-checker.pid"
  rm -rf "${CRM_ROOT}/state/${AGENT}.fast-checker.lock"
  pkill -f "fast-checker.sh ${AGENT} " 2>/dev/null || true
  sleep 1
  if [[ -f "${TEMPLATE_ROOT}/core/scripts/fast-checker.sh" ]]; then
      bash "${TEMPLATE_ROOT}/core/scripts/fast-checker.sh" "${AGENT}" "${TMUX_SESSION}" "${AGENT_DIR}" "${TEMPLATE_ROOT}" \
          >> "${LOG_DIR}/fast-checker.log" 2>&1 &
      FAST_PID=$!
  fi
  
  tmux send-keys -t "${TMUX_SESSION}:0.0" \
      "cd '${LAUNCH_DIR}' && claude --continue --dangerously-skip-permissions ${MODEL_FLAG}${EXTRA_FLAGS_STR} '${CONTINUE_PROMPT}'" Enter
  ```
- **Problem:** O problema de dedup não acontece só no hard restart explícito. O wrapper mata e recria o `fast-checker` no refresh de sessão, e o caminho `enable-agent.sh --restart` também só faz unload/load do plist. Em ambos os casos, `${AGENT}.dedup` continua vivo, então o próximo polling reaproveita hashes velhos e pode silenciar mensagens após restart manual, watchdog ou session refresh.
- **Suggestion:**
  ```bash
  rm -f \
      "${CRM_ROOT}/state/${AGENT}.fast-checker.pid" \
      "${CRM_ROOT}/state/${AGENT}.dedup"
  rm -rf "${CRM_ROOT}/state/${AGENT}.fast-checker.lock"
  ```

#### Issue 1.3 — Frozen detector resets its own stale timer every passive-check cycle
- **File:** `core/scripts/fast-checker.sh`
- **Line:** 791-843
- **Code:**
  ```bash
  CURRENT_PANE=$(tmux capture-pane -t "${TMUX_SESSION}:0.0" -p 2>/dev/null | tail -10)
  CURRENT_HASH=$(printf '%s' "$CURRENT_PANE" | shasum 2>/dev/null | cut -d' ' -f1 || echo "")
  if [[ "$CURRENT_HASH" != "$LAST_PANE_HASH" ]]; then
      LAST_PANE_HASH="$CURRENT_HASH"
      PANE_STALE_SINCE=$NOW_TS
  fi
  ...
  CURRENT_PANE_HASH=$(printf '%s' "$CURRENT_PANE" | shasum -a 256 2>/dev/null | cut -d' ' -f1)
  if [[ "$CURRENT_PANE_HASH" != "$LAST_PANE_HASH" ]]; then
      LAST_PANE_HASH="$CURRENT_PANE_HASH"
      PANE_UNCHANGED_SINCE=$NOW_TS
      PASSIVE_FROZEN_TRIGGERED=false
  fi
  ```
- **Problem:** Os dois detectores compartilham `LAST_PANE_HASH`, mas calculam hashes diferentes sobre janelas diferentes (`tail -10` + SHA-1 no fluxo ativo, `tail -20` + SHA-256 no fluxo passivo). A cada rodada passiva, `LAST_PANE_HASH` muda de formato; na iteração seguinte do fluxo ativo, isso aparenta “progresso” e reseta `PANE_STALE_SINCE`. Na prática, o timer do frozen detector com mensagem humana pendente pode nunca atingir 120s/300s.
- **Suggestion:**
  ```bash
  ACTIVE_PANE_HASH=""
  PASSIVE_PANE_HASH=""
  
  current_active_hash=$(printf '%s' "$CURRENT_PANE" | shasum -a 256 | cut -d' ' -f1)
  current_passive_hash=$(printf '%s' "$CURRENT_PANE_FULL" | shasum -a 256 | cut -d' ' -f1)
  ```

### 🟡 MEDIUM

> Code style, readability, maintainability, or minor performance issues.

#### Issue 1.4 — Soft frozen nudge fires after only 120 seconds
- **File:** `core/scripts/fast-checker.sh`
- **Line:** 99-100
- **Code:**
  ```bash
  FROZEN_SOFT_NUDGE_SECONDS=120   # soft nudge (Ctrl+C + re-prompt) after 2 min
  FROZEN_RESTART_MAX_SECONDS=300  # hard-restart if agent busy for 5+ min with pending human msg
  ```
- **Problem:** Dois minutos é curto demais para tarefas normais do Claude Code como leitura de árvore grande, rede, testes ou chamadas MCP demoradas. O resultado é exatamente o falso positivo já diagnosticado: `Ctrl+C` e “reply now” em execuções saudáveis, degradando confiabilidade e gerando nudges desnecessários ao usuário.
- **Suggestion:**
  ```bash
  FROZEN_SOFT_NUDGE_SECONDS=$(jq -r '.frozen_soft_nudge_seconds // 600' "${AGENT_DIR}/config.json" 2>/dev/null || echo "600")
  FROZEN_RESTART_MAX_SECONDS=$(jq -r '.frozen_restart_max_seconds // 900' "${AGENT_DIR}/config.json" 2>/dev/null || echo "900")
  ```

#### Issue 1.5 — Busy auto-reply is sent before dedup/injection succeeds
- **File:** `core/scripts/fast-checker.sh`
- **Line:** 603-606
- **Code:**
  ```bash
  # Auto-reply when agent is busy processing
  if ! is_agent_idle; then
      auto_reply_busy "${CHAT_ID}"
  fi
  HUMAN_MSG_PENDING=true
  ```
- **Problem:** O auto-reply acontece durante a montagem do `MESSAGE_BLOCK`, antes de `inject_messages` rodar e antes do dedup decidir se a mensagem será descartada. Se o hash já existir ou a injeção falhar, o usuário recebe “Got it, processing...” mas nada chega ao Claude. O mesmo padrão reaparece no handler de texto em `fast-checker.sh:686-689`.
- **Suggestion:**
  ```bash
  pending_busy_ack_chat_id="${CHAT_ID}"
  pending_busy_ack_required=true
  
  if inject_messages "$MESSAGE_BLOCK"; then
      [[ "$pending_busy_ack_required" == "true" ]] && auto_reply_busy "$pending_busy_ack_chat_id"
  fi
  ```

### 🟢 LOW

> Nitpicks, suggestions, and nice-to-haves.

#### Issue 1.6 — Non-text Telegram media bypass pending-message safeguards
- **File:** `core/scripts/fast-checker.sh`
- **Line:** 620-659
- **Code:**
  ```bash
  elif [[ "$TYPE" == "photo" ]]; then
      IMAGE_PATH=$(echo "$line" | jq -r '.image_path // ""' 2>/dev/null || echo "")
      MESSAGE_BLOCK+="=== TELEGRAM PHOTO from ${FROM} (chat_id:${CHAT_ID}) ===
  ...
  elif [[ "$TYPE" == "voice" || "$TYPE" == "audio" ]]; then
      AUDIO_PATH=$(echo "$line" | jq -r '.file_path // ""' 2>/dev/null || echo "")
  ...
  elif [[ "$TYPE" == "video_note" ]]; then
      VIDEO_PATH=$(echo "$line" | jq -r '.file_path // ""' 2>/dev/null || echo "")
  ```
- **Problem:** Somente texto e o primeiro branch de `document` marcam `HUMAN_MSG_PENDING` e disparam `auto_reply_busy`. Foto, áudio, voz e video note são injetados sem os mesmos guardrails, então um agente travado não recebe typing indicator nem restart heuristics para esses inputs. Além disso, há um segundo `elif [[ "$TYPE" == "document" ]]` morto em `631-643`, sinal de fluxo duplicado e inconsistente.
- **Suggestion:**
  ```bash
  mark_human_message_pending() {
      HUMAN_MSG_PENDING=true
      HUMAN_MSG_CHAT_ID="${CHAT_ID}"
      HUMAN_MSG_PENDING_SINCE=$(date +%s)
  }
  
  # Call this helper for document/photo/voice/audio/video_note/text before appending to MESSAGE_BLOCK.
  ```

---

## Regressions

> Issues introduced by fixes from the previous round. Leave empty if first round or no regressions.

- none

---

## ✅ What Is Good

> Explicitly list things that are well-implemented. The fixer must NOT change these.

- `core/scripts/generate-launchd.sh:28-52` faz detecção explícita de `claude`, `node` e `pyenv shims`, evitando o problema clássico de `launchd` subir com PATH incorreto.
- `core/bus/hook-permission-telegram.sh:25-27` falha em modo deny-by-default quando faltam credenciais, o que é a postura segura correta para um hook bloqueante.
- `core/bus/send-telegram.sh:46-49` centraliza o envio via `_telegram-curl.sh`, reduzindo risco de vazar token em traces dos scripts chamadores.
- `core/scripts/agent-wrapper.sh:120-151` preserva settings do projeto e sobrepõe apenas o necessário do agente, o que é uma boa escolha para compatibilidade com hooks/permissões existentes.

---

## 📊 Summary

- **Total issues:** 6
- **By severity:** 🔴 0 CRITICAL, 🟠 3 HIGH, 🟡 2 MEDIUM, 🟢 1 LOW
- **Regressions from previous round:** none
- **Next action:** Fix issues and request new review
