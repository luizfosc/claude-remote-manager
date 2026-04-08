#!/usr/bin/env bash
# disable-agent.sh - Disable a Claude Remote Manager agent
# Usage: disable-agent.sh <agent_name>

set -euo pipefail

TEMPLATE_ROOT="$(cd "$(dirname "$0")" && pwd)"

# Load instance ID
REPO_ENV="${TEMPLATE_ROOT}/.env"
if [[ -f "${REPO_ENV}" ]]; then
    CRM_INSTANCE_ID=$(grep '^CRM_INSTANCE_ID=' "${REPO_ENV}" | cut -d= -f2)
fi
CRM_INSTANCE_ID="${CRM_INSTANCE_ID:-default}"
CRM_ROOT="${HOME}/.claude-remote/${CRM_INSTANCE_ID}"

AGENT="${1:?Usage: disable-agent.sh <agent_name>}"
ENABLED_FILE="${CRM_ROOT}/config/enabled-agents.json"

echo "Disabling ${AGENT}..."

# Unload launchd plist
PLIST="${HOME}/Library/LaunchAgents/com.claude-remote.${CRM_INSTANCE_ID}.${AGENT}.plist"
if [[ -f "${PLIST}" ]]; then
    launchctl unload "${PLIST}" 2>/dev/null || true
    echo "  launchd: unloaded"
fi

# Kill tmux session if running
TMUX_SESSION="crm-${CRM_INSTANCE_ID}-${AGENT}"
tmux kill-session -t "${TMUX_SESSION}" 2>/dev/null || true

# Kill fast-checker process (started by wrapper, not launchd)
FC_PIDFILE="${CRM_ROOT}/state/${AGENT}.fast-checker.pid"
if [[ -f "$FC_PIDFILE" ]]; then
    FC_PID=$(cat "$FC_PIDFILE" 2>/dev/null || echo "")
    [[ -n "$FC_PID" ]] && kill "$FC_PID" 2>/dev/null || true
    rm -f "$FC_PIDFILE"
fi
rm -rf "${CRM_ROOT}/state/${AGENT}.fast-checker.lock"
pkill -f "fast-checker.sh ${AGENT} " 2>/dev/null || true
echo "  fast-checker: killed"

# Clean state files to prevent stale data on re-enable
rm -f "${CRM_ROOT}/state/${AGENT}.dedup"
rm -f "${CRM_ROOT}/state/${AGENT}.session-start"
rm -f "${CRM_ROOT}/state/${AGENT}.stats.json"
rm -f "${CRM_ROOT}/state/${AGENT}.context-restart-pending"
rm -f "${CRM_ROOT}/state/.telegram-offset-${AGENT}"
echo "  state: cleaned"

# Update enabled status
if [[ -f "${ENABLED_FILE}" ]]; then
    jq ".\"${AGENT}\".enabled = false" "${ENABLED_FILE}" > "${ENABLED_FILE}.tmp"
    mv "${ENABLED_FILE}.tmp" "${ENABLED_FILE}"
fi

echo "  status: disabled"
echo ""
echo "${AGENT} is now disabled. Its configuration is preserved."
echo "Re-enable with: ./enable-agent.sh ${AGENT}"
