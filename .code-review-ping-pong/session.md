# Ping-Pong Session

## Scope
- files:
  - core/scripts/fast-checker.sh
  - core/scripts/agent-wrapper.sh
  - core/scripts/crash-alert.sh
  - core/scripts/generate-launchd.sh
  - core/bus/hard-restart.sh
  - core/bus/hook-permission-telegram.sh
  - core/bus/send-telegram.sh
  - core/bus/check-telegram.sh
  - core/bus/_telegram-curl.sh
  - enable-agent.sh
  - disable-agent.sh
  - bootstrap.sh

## Goals
- Verificar integridade do fluxo completo do bot Telegram (polling → injeção → resposta)
- Identificar bugs que causam desconexão ou perda de mensagens
- Garantir que múltiplos agentes com mesmo token sejam detectados/prevenidos
- Verificar robustez de crash recovery e restart paths
- Garantir que offset tracking, dedup e auto-reply funcionem corretamente
- Código production-ready e resiliente

## Constraints
- Não modificar a estrutura de diretórios do projeto
- Manter compatibilidade com launchd no macOS (Darwin)
- Scripts devem continuar funcionando em bash/zsh no macOS

## Known Bugs (diagnosticados)
1. **Dois agentes com mesmo BOT_TOKEN** — `claudecode_fosc` e `claudecode_fosc_bot` compartilhavam o mesmo token, causando disputa no polling de `getUpdates`. Offset files separados por agente faziam ambos receberem a mesma mensagem.
