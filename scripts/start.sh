#!/usr/bin/env bash
# start.sh — Arranque normal del stack (tras bootstrap ya realizado)
# Uso: ./scripts/start.sh

set -euo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=./lib-env.sh
source "$STACK_DIR/scripts/lib-env.sh"

if ! ensure_supported_runtime; then
  echo "[FAIL] Ejecuta start.sh desde Linux/macOS o WSL2 (Ubuntu)."
  exit 1
fi

echo "Levantando agentec-openclaw-stack..."

cd "$STACK_DIR"

if [ -f ".env" ]; then
  load_env_file "$STACK_DIR/.env"
fi

normalize_path_var "OPENCLAW_CONFIG_DIR" "$STACK_DIR" "../.openclaw"
normalize_path_var "OPENCLAW_WORKSPACE_DIR" "$STACK_DIR" "../.openclaw/workspace"
normalize_path_var "AGENTEC_ARTIFACTS_DIR" "$STACK_DIR" "../artifacts"
normalize_path_var "AGENTEC_SKILLS_DIR" "$STACK_DIR" "../agentec-skills/skills"
normalize_path_var "AGENTEC_TOOLS_DIR" "$STACK_DIR" "../agentec-tools/tools"
normalize_path_var "AGENTEC_STACK_CONFIG_DIR" "$STACK_DIR" "./config"
normalize_path_var "AGENTEC_GRAPH_TOKEN_STORE_DIR" "$STACK_DIR" "../.agentec-graph-tokens"

OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-$HOME/.openclaw}"
STACK_CONFIG_DIR="${AGENTEC_STACK_CONFIG_DIR:-$STACK_DIR/config}"
MODEL_PRIMARY="${OPENCLAW_MODEL_PRIMARY:-openrouter/meta-llama/llama-3.3-70b-instruct:free}"
MCP_SERVER_URL_INTERNAL="${AGENTEC_MCP_SERVER_URL_INTERNAL:-http://agentec-mcp-server:3000/mcp}"
MCP_AUTH_TOKEN="${AGENTEC_MCP_AUTH_TOKEN:-}"

mkdir -p "$STACK_CONFIG_DIR"
if [ -f "$STACK_DIR/.env" ]; then
  cp "$STACK_DIR/.env" "$STACK_CONFIG_DIR/stack.env"
fi

ensure_openclaw_local_config "$OPENCLAW_CONFIG_DIR" "$MODEL_PRIMARY" "$MCP_SERVER_URL_INTERNAL" "$MCP_AUTH_TOKEN"

docker compose up -d

if [ "${AGENTEC_SHADOW_MODE:-0}" = "1" ]; then
  echo "Shadow mode activo: levantando agentec-mcp-server-py..."
  docker compose --profile shadow up -d agentec-mcp-server-py
fi

GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
MCP_PORT="${AGENTEC_MCP_PORT:-3002}"
MCP_PY_PORT="${AGENTEC_MCP_PY_PORT:-3102}"

wait_for_gateway() {
  local max_wait="$1"
  local waited=0

  until curl -sf "http://localhost:$GATEWAY_PORT/healthz" &>/dev/null; do
    sleep 2
    waited=$((waited + 2))
    if [ "$waited" -ge "$max_wait" ]; then
      return 1
    fi
  done
  return 0
}

echo "Esperando gateway en puerto $GATEWAY_PORT..."
if ! wait_for_gateway 60; then
  echo "[WARN] Gateway no respondió a tiempo. Reintentando con rutas portables de fallback..."

  export OPENCLAW_CONFIG_DIR="$(resolve_path "../.openclaw" "$STACK_DIR")"
  export OPENCLAW_WORKSPACE_DIR="$(resolve_path "../.openclaw/workspace" "$STACK_DIR")"

  ensure_openclaw_local_config "$OPENCLAW_CONFIG_DIR" "$MODEL_PRIMARY" "$MCP_SERVER_URL_INTERNAL" "$MCP_AUTH_TOKEN"
  docker compose up -d --force-recreate openclaw-gateway

  if ! wait_for_gateway 60; then
    echo "[FAIL] Gateway no respondió después del fallback"
    docker compose logs --tail=60 openclaw-gateway
    exit 1
  fi
fi

echo "[OK] Stack levantado — gateway: http://localhost:$GATEWAY_PORT"
echo "[OK] MCP Node: http://localhost:$MCP_PORT/health"
if [ "${AGENTEC_SHADOW_MODE:-0}" = "1" ]; then
  echo "[OK] MCP Python (shadow): http://localhost:$MCP_PY_PORT/health"
  echo "[INFO] Para comparar Node vs Python: ./scripts/mcp-shadow-compare.sh"
fi
