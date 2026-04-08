---
protocol: code-review-ping-pong
type: review
round: 4
date: "2026-04-08"
reviewer: "Claude Opus"
commit_sha: "6846ef7"
branch: "main"
based_on_fix: "round-3.md"
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
score: 7
verdict: "CONTINUE"
issues:
  - id: "4.1"
    severity: "CRITICAL"
    title: "Nenhuma proteção contra múltiplos agentes com mesmo BOT_TOKEN"
    file: "enable-agent.sh"
    line: "91-144"
    suggestion: "Na ativação, verificar se outro agente já habilitado usa o mesmo BOT_TOKEN. Abortar com erro se detectar conflito."
  - id: "4.2"
    severity: "HIGH"
    title: "disable-agent.sh não mata fast-checker nem limpa state"
    file: "disable-agent.sh"
    line: "20-37"
    suggestion: "Matar fast-checker (pkill + rm pid/lock), limpar dedup, offset e session-start do agente desabilitado."
  - id: "4.3"
    severity: "HIGH"
    title: "check-telegram.sh perde offset em erro de rede"
    file: "core/bus/check-telegram.sh"
    line: "42-62"
    suggestion: "Quando getUpdates retorna ok:false, não emitir __OFFSET__. Atualmente, se a resposta falhar, NEW_OFFSET fica vazio e tudo funciona, mas se a API retornar parcial com result[-1] válido, o offset avança sem mensagens terem sido processadas."
  - id: "4.4"
    severity: "HIGH"
    title: "Race condition no context threshold safety net"
    file: "core/scripts/fast-checker.sh"
    line: "394-398"
    suggestion: "O subshell que faz o safety net captura CONTEXT_RESTART_TRIGGERED por valor (fork). Mudanças no loop principal não são visíveis ao subshell. Se Claude fizer self-restart, o subshell ainda executará do_hard_restart após 3min. Usar um arquivo marker em vez de variável bash."
  - id: "4.5"
    severity: "MEDIUM"
    title: "hard-restart.sh usa launchctl unload/load (deprecated no macOS 13+)"
    file: "core/bus/hard-restart.sh"
    line: "48"
    suggestion: "Usar `launchctl bootout gui/$(id -u)/<label>` e `launchctl bootstrap gui/$(id -u) <plist>` que são os comandos modernos. O mesmo vale para enable-agent.sh:60, disable-agent.sh:25, e generate-launchd.sh:106-107."
  - id: "4.6"
    severity: "MEDIUM"
    title: "send-telegram.sh Markdown parse falha silenciosamente"
    file: "core/bus/send-telegram.sh"
    line: "88-91"
    suggestion: "Quando parse_mode=Markdown e a mensagem tem caracteres especiais não escapados (_, *, etc.), o Telegram retorna erro 400 e a mensagem é PERDIDA silenciosamente (exit 1 sem retry). Adicionar fallback: se sendMessage com Markdown falhar, reenviar sem parse_mode."
  - id: "4.7"
    severity: "MEDIUM"
    title: "Typing indicator continua após agent ficar idle entre polls"
    file: "core/scripts/fast-checker.sh"
    line: "784-848"
    suggestion: "HUMAN_MSG_PENDING só reseta quando is_agent_idle() retorna true. Se o agente responde via send-telegram.sh (Bash tool) mas NÃO volta ao prompt '>' imediatamente (ex: executa mais tools), o typing indicator fica ativo indefinidamente. Detectar chamadas a send-telegram.sh no pane como sinal de resposta enviada."
  - id: "4.8"
    severity: "LOW"
    title: "bootstrap.sh não verifica dependências jq e tmux"
    file: "bootstrap.sh"
    line: "27-34"
    suggestion: "Adicionar jq e tmux à checagem de dependências. Ambos são obrigatórios para agent-wrapper.sh e fast-checker.sh."
  - id: "4.9"
    severity: "LOW"
    title: "caffeinate process leak se agent-wrapper morre por SIGKILL"
    file: "core/scripts/agent-wrapper.sh"
    line: "213"
    suggestion: "`caffeinate -is -w $$` segue o PID do wrapper. Se o wrapper receber SIGKILL (não catchable), caffeinate fica órfão. Considerar escrever o PID do caffeinate e limpá-lo no graceful_shutdown."
  - id: "4.10"
    severity: "LOW"
    title: "Dedup file cresce indefinidamente durante sessões muito longas"
    file: "core/scripts/fast-checker.sh"
    line: "267-269"
    suggestion: "O tail -100 trunca para 100 entradas, mas roda a CADA injeção. Em sessões com muitas mensagens, o pattern read-tail-write gera I/O desnecessário. Truncar apenas quando o arquivo exceder 200 linhas (check com wc -l primeiro)."
---

# Code Ping-Pong — Round 4 Review

## 🎯 Score: 7/10 — CONTINUE

Nova sessão de review com escopo expandido (adicionados check-telegram.sh e _telegram-curl.sh). Foco em robustez do fluxo Telegram e prevenção de conflitos de token.

---

## Issues

### 🔴 4.1 CRITICAL — Nenhuma proteção contra múltiplos agentes com mesmo BOT_TOKEN

**Arquivo:** `enable-agent.sh:91-144`

O sistema permite habilitar múltiplos agentes com o mesmo `BOT_TOKEN` sem qualquer aviso. Isso causa uma disputa destrutiva: ambos fazem polling em `getUpdates` com offsets independentes, recebem a mesma mensagem, ambos respondem, e o Telegram pode desconectar um deles.

**Impacto real:** Isso estava acontecendo em produção com `claudecode_fosc` e `claudecode_fosc_bot`.

**Fix sugerido:**

```bash
# Em enable-agent.sh, antes de gerar o plist, após carregar o .env do agente:
if [[ -n "${BOT_TOKEN:-}" ]]; then
    ENABLED_FILE="${CRM_ROOT}/config/enabled-agents.json"
    for other_dir in "${TEMPLATE_ROOT}/agents"/*/; do
        other=$(basename "$other_dir")
        [[ "$other" == "$AGENT" || "$other" == "agent-template" ]] && continue
        other_enabled=$(jq -r ".\"${other}\".enabled // false" "$ENABLED_FILE" 2>/dev/null)
        [[ "$other_enabled" != "true" ]] && continue
        other_token=$(grep '^BOT_TOKEN=' "${other_dir}/.env" 2>/dev/null | cut -d= -f2)
        if [[ "$other_token" == "$BOT_TOKEN" ]]; then
            echo "ERROR: Agent '${other}' already uses this BOT_TOKEN and is enabled."
            echo "Disable it first (./disable-agent.sh ${other}) or use a different token."
            exit 1
        fi
    done
fi
```

---

### 🟠 4.2 HIGH — disable-agent.sh não mata fast-checker nem limpa state

**Arquivo:** `disable-agent.sh:20-37`

O script descarrega o launchd e mata o tmux, mas:
- O fast-checker continua rodando (foi iniciado pelo wrapper, não pelo launchd)
- PID file, lock dir, dedup, offset e session-start ficam residuais
- Se o agente for re-habilitado, pode herdar state stale

**Fix sugerido:**

```bash
# Após matar tmux (linha 31), adicionar:

# Kill fast-checker
FC_PIDFILE="${CRM_ROOT}/state/${AGENT}.fast-checker.pid"
if [[ -f "$FC_PIDFILE" ]]; then
    FC_PID=$(cat "$FC_PIDFILE" 2>/dev/null || echo "")
    [[ -n "$FC_PID" ]] && kill "$FC_PID" 2>/dev/null || true
    rm -f "$FC_PIDFILE"
fi
rm -rf "${CRM_ROOT}/state/${AGENT}.fast-checker.lock"
pkill -f "fast-checker.sh ${AGENT} " 2>/dev/null || true

# Clean state
rm -f "${CRM_ROOT}/state/${AGENT}.dedup"
rm -f "${CRM_ROOT}/state/${AGENT}.session-start"
rm -f "${CRM_ROOT}/state/${AGENT}.stats.json"
```

---

### 🟠 4.3 HIGH — check-telegram.sh pode avançar offset em resposta parcial

**Arquivo:** `core/bus/check-telegram.sh:42-62`

O offset é calculado a partir de `result[-1].update_id + 1` e emitido via fd3. Se a API retornar `ok:true` mas com resultados parciais (timeout de rede, resposta truncada), o jq pode extrair um update_id de dados incompletos, avançando o offset e pulando mensagens.

**Fix sugerido:**

```bash
# Após verificar .ok (linha 45), adicionar validação de integridade:
RESULT_COUNT=$(echo "${RESPONSE}" | jq '.result | length' 2>/dev/null || echo "0")
if [[ "${RESULT_COUNT}" -eq 0 ]]; then
    exit 0
fi
```

E na emissão do offset (linha 60-61), validar que NEW_OFFSET é numérico:

```bash
if [[ -n "${NEW_OFFSET}" ]] && [[ "${NEW_OFFSET}" =~ ^[0-9]+$ ]]; then
    echo "__OFFSET__:${NEW_OFFSET}" >&3 2>/dev/null || echo "__OFFSET__:${NEW_OFFSET}" >&2 2>/dev/null || true
fi
```

---

### 🟠 4.4 HIGH — Race condition no safety net do context threshold

**Arquivo:** `core/scripts/fast-checker.sh:394-398`

```bash
( sleep 180; if [[ "$CONTEXT_RESTART_TRIGGERED" == "true" ]]; then
    ...
fi ) &
```

O subshell herda o valor de `CONTEXT_RESTART_TRIGGERED` por **cópia** no momento do fork. Se Claude fizer o self-restart e o loop principal alterar a variável, o subshell **não verá** a alteração. Após 3 minutos, ele sempre executará `do_hard_restart` — fazendo um restart duplo.

**Fix sugerido:** Usar um arquivo marker em vez de variável:

```bash
CONTEXT_RESTART_MARKER="${CRM_ROOT}/state/${AGENT}.context-restart-pending"
touch "$CONTEXT_RESTART_MARKER"

( sleep 180; if [[ -f "$CONTEXT_RESTART_MARKER" ]]; then
    log "CONTEXT_THRESHOLD: Claude did not self-restart in 3min — forcing"
    do_hard_restart "forced: context threshold"
fi ) &
```

E em `hard-restart.sh`, limpar o marker:
```bash
rm -f "${CRM_ROOT}/state/${AGENT}.context-restart-pending"
```

---

### 🟡 4.5 MEDIUM — launchctl unload/load deprecated no macOS 13+

**Arquivos:** `hard-restart.sh:48`, `enable-agent.sh:60`, `disable-agent.sh:25`, `generate-launchd.sh:106-107`

`launchctl load/unload` são deprecated desde macOS Ventura. Os comandos modernos são:
- `launchctl bootstrap gui/$(id -u) <plist>`
- `launchctl bootout gui/$(id -u)/<label>`

**Nota:** Os comandos antigos ainda funcionam no macOS 15, mas podem ser removidos em versões futuras. Baixa urgência, mas vale a migração.

---

### 🟡 4.6 MEDIUM — Mensagem perdida quando Markdown parse falha

**Arquivo:** `core/bus/send-telegram.sh:88-91`

Se a mensagem contém caracteres como `_`, `[`, ou `*` que quebram o Markdown parser do Telegram, a API retorna 400 e o script faz `exit 1`. A mensagem é **permanentemente perdida** — nenhum retry acontece.

**Fix sugerido:**

```bash
# Após o bloco de envio sem keyboard (linhas 88-91), adicionar fallback:
if ! echo "${RESPONSE}" | jq -e '.ok' > /dev/null 2>&1; then
    # Retry without Markdown parse mode
    RESPONSE=$(telegram_api_post "sendMessage" \
        -d chat_id="${CHAT_ID}" \
        --data-urlencode "text=${MESSAGE}")
fi
```

---

### 🟡 4.7 MEDIUM — Typing indicator não reseta após agent responder

**Arquivo:** `core/scripts/fast-checker.sh:784-848`

`HUMAN_MSG_PENDING` só reseta quando `is_agent_idle()` retorna true (prompt `>` visível). Mas após o agente enviar a resposta via `send-telegram.sh`, ele frequentemente executa mais ferramentas antes de voltar ao idle. O typing indicator continua ativo por minutos após a resposta já ter sido entregue.

**Fix sugerido:** No bloco de monitoramento (linha ~785), adicionar detecção de envio:

```bash
if [[ "$HUMAN_MSG_PENDING" == "true" ]]; then
    # Check if agent already replied via Telegram
    PANE_TEXT=$(tmux capture-pane -t "${TMUX_SESSION}:0.0" -p 2>/dev/null | tail -20)
    if echo "$PANE_TEXT" | grep -q "send-telegram.sh"; then
        HUMAN_MSG_PENDING=false
        HUMAN_MSG_PENDING_SINCE=0
        FROZEN_NUDGE_SENT=0
        ACTIVE_PANE_HASH=""
        PANE_STALE_SINCE=0
        LAST_ACTIVITY=""
    elif ! is_agent_idle; then
        # ... existing frozen detection logic ...
    fi
fi
```

**Nota:** `extract_activity()` já detecta `send-telegram.sh` e faz `return 1` para não streamar, mas não usa essa informação para resetar o pending state.

---

### 🟢 4.8 LOW — bootstrap.sh não verifica jq e tmux

**Arquivo:** `bootstrap.sh:27-34`

O bootstrap verifica `git` e `claude` mas não `jq` e `tmux`, que são obrigatórios para o sistema funcionar.

**Fix:** Adicionar à checagem:

```bash
command -v jq >/dev/null 2>&1 || MISSING="${MISSING} jq"
command -v tmux >/dev/null 2>&1 || MISSING="${MISSING} tmux"
```

---

### 🟢 4.9 LOW — caffeinate process leak

**Arquivo:** `core/scripts/agent-wrapper.sh:213`

`caffeinate -is -w $$` segue o PID do wrapper. SIGTERM é tratado por `graceful_shutdown`, mas SIGKILL não pode ser capturado. Se o wrapper morrer por SIGKILL, caffeinate fica órfão até o Mac reiniciar.

**Fix sugerido:** Salvar PID e matar no shutdown:

```bash
caffeinate -is -w $$ &
CAFFEINATE_PID=$!

# No graceful_shutdown():
kill ${CAFFEINATE_PID} 2>/dev/null || true
```

---

### 🟢 4.10 LOW — Dedup file truncation roda em toda injeção

**Arquivo:** `core/scripts/fast-checker.sh:267-269`

O `tail -100` roda em cada `inject_messages()`, mesmo quando o arquivo tem menos de 100 linhas. O pattern `grep | tail > tmp && mv` a cada mensagem gera I/O desnecessário.

**Fix sugerido:**

```bash
LINE_COUNT=$(wc -l < "$DEDUP_FILE" 2>/dev/null | tr -d ' ')
if [[ "${LINE_COUNT:-0}" -gt 200 ]]; then
    grep -v '^$' "$DEDUP_FILE" 2>/dev/null | tail -100 > "${DEDUP_FILE}.tmp" && mv "${DEDUP_FILE}.tmp" "$DEDUP_FILE"
fi
```

---

## Regressions

> Issues introduced since round-3.

- none (commit 6846ef7 fix changes are solid)

---

## ✅ What Is Good

- `core/scripts/fast-checker.sh` singleton lock com mkdir (linhas 38-54) é elegante e POSIX-portable
- Dedup com SHA256 + rolling window (linhas 245-269) é robusto para crash recovery
- Offset commit **pós-injeção** via fd3 (check-telegram.sh:53-61 + fast-checker.sh:748-753) garante atomicidade
- `_telegram-curl.sh` protege o token contra trace leaks com `set +x` em subshell
- `hook-permission-telegram.sh` — design limpo com inline keyboard + polling por arquivo
- Frozen detection em dois estágios (soft nudge → hard restart) com thresholds configuráveis
- Passive frozen detection independente de human messages (linhas 850-868)
- Kill switch pattern (linhas 410-416) permite pausar agente sem desabilitar

---

## 📊 Summary

- **Total issues:** 10
- **By severity:** 🔴 1 CRITICAL, 🟠 3 HIGH, 🟡 3 MEDIUM, 🟢 3 LOW
- **Regressions from previous round:** none
- **Next action:** Fix issues 4.1-4.4 (CRITICAL + HIGH) first, then address MEDIUMs
