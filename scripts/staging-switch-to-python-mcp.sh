#!/usr/bin/env bash
# staging-switch-to-python-mcp.sh — asegura que staging use MCP Python en openclaw.json
# Uso: ./scripts/staging-switch-to-python-mcp.sh [--dry-run]

set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=./lib-env.sh
source "$STACK_DIR/scripts/lib-env.sh"

if [ -f "$STACK_DIR/.env" ]; then
  load_env_file "$STACK_DIR/.env"
fi

ENV_NAME="${AGENTEC_ENV:-unknown}"
OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-$HOME/.openclaw}"
OPENCLAW_JSON="${OPENCLAW_CONFIG_DIR}/openclaw.json"
MCP_URL="${AGENTEC_MCP_SERVER_URL_INTERNAL:-http://agentec-mcp-server-py:3100/mcp}"
MCP_TOKEN="${AGENTEC_MCP_AUTH_TOKEN:-}"

if [ "$ENV_NAME" != "staging" ]; then
  echo "[WARN] AGENTEC_ENV=$ENV_NAME (esperado: staging). Continúo igualmente."
fi

if [ ! -f "$OPENCLAW_JSON" ]; then
  echo "[FAIL] No existe $OPENCLAW_JSON"
  exit 1
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "[DRY-RUN] Actualizaría openclaw.json con MCP URL: $MCP_URL"
  exit 0
fi

python3 - <<'PY' "$OPENCLAW_JSON" "$MCP_URL" "$MCP_TOKEN"
import json, sys
path, mcp_url, token = sys.argv[1:4]
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)

servers = data.setdefault('mcp', {}).setdefault('servers', {})
agentec = servers.setdefault('agentec', {})
agentec['url'] = mcp_url
agentec['transport'] = 'streamable-http'
headers = agentec.setdefault('headers', {})
if token:
    headers['Authorization'] = f'Bearer {token}'

with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
print('[OK] openclaw.json actualizado para MCP Python staging')
PY

echo "[OK] Switch de staging a MCP Python completado"
