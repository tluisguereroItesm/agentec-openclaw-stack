#!/usr/bin/env bash
# staging-smoke-e2e.sh — smoke E2E para staging con MCP Python
# Verifica: gateway, mcp python /health, tools/list, tools/call
# Uso: ./scripts/staging-smoke-e2e.sh [--dry-run]

set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTEC_ROOT="$(cd "$STACK_DIR/.." && pwd)"

# shellcheck source=./lib-env.sh
source "$STACK_DIR/scripts/lib-env.sh"

if [ -f "$STACK_DIR/.env" ]; then
  load_env_file "$STACK_DIR/.env"
fi

ENV_NAME="${AGENTEC_ENV:-unknown}"
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
MCP_PY_PORT="${AGENTEC_MCP_PY_PORT:-3102}"
MCP_TOKEN="${AGENTEC_MCP_AUTH_TOKEN:-}"
INPUT_PATH="${AGENTEC_ROOT}/agentec-tools/tools/web-login-playwright/input.json"
OPENCLAW_JSON="${OPENCLAW_CONFIG_DIR:-$HOME/.openclaw}/openclaw.json"

if [ "$ENV_NAME" != "staging" ]; then
  echo "[WARN] AGENTEC_ENV=$ENV_NAME (esperado: staging)."
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "[DRY-RUN] Haría smoke staging contra gateway:$GATEWAY_PORT y MCP Python:$MCP_PY_PORT"
  exit 0
fi

[ -n "$MCP_TOKEN" ] || { echo "[FAIL] AGENTEC_MCP_AUTH_TOKEN vacío"; exit 1; }
[ -f "$INPUT_PATH" ] || { echo "[FAIL] input de prueba no encontrado: $INPUT_PATH"; exit 1; }
[ -f "$OPENCLAW_JSON" ] || { echo "[FAIL] openclaw.json no encontrado: $OPENCLAW_JSON"; exit 1; }

if ! grep -q 'agentec-mcp-server-py:3100/mcp' "$OPENCLAW_JSON"; then
  echo "[WARN] openclaw.json no parece apuntar a MCP Python (revisa scripts/staging-switch-to-python-mcp.sh)"
fi

curl -sf "http://localhost:${GATEWAY_PORT}/healthz" >/dev/null
curl -sf "http://localhost:${MCP_PY_PORT}/health" >/dev/null

echo "[OK] Health gateway y MCP Python"

LIST_PAYLOAD='{"jsonrpc":"2.0","id":"staging-list","method":"tools/list","params":{}}'
CALL_ARGS="$(cat "$INPUT_PATH")"
CALL_PAYLOAD="{\"jsonrpc\":\"2.0\",\"id\":\"staging-call\",\"method\":\"tools/call\",\"params\":{\"name\":\"web_login_playwright\",\"arguments\":$CALL_ARGS}}"

post_mcp() {
  local payload="$1"
  curl -sf -X POST "http://localhost:${MCP_PY_PORT}/mcp" \
    -H "Authorization: Bearer $MCP_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload"
}

LIST_RESULT="$(post_mcp "$LIST_PAYLOAD")"
CALL_RESULT="$(post_mcp "$CALL_PAYLOAD")"

python3 - <<'PY' "$LIST_RESULT" "$CALL_RESULT"
import json, sys
list_result = json.loads(sys.argv[1])
call_result = json.loads(sys.argv[2])

errors = []

tools = [t.get('name') for t in list_result.get('result', {}).get('tools', []) if isinstance(t, dict)]
if 'web_login_playwright' not in tools:
    errors.append('tools/list no incluye web_login_playwright')

content = call_result.get('result', {}).get('content', [])
payload = {}
if content and isinstance(content, list) and isinstance(content[0], dict):
    txt = content[0].get('text', '')
    try:
        payload = json.loads(txt) if txt else {}
    except json.JSONDecodeError:
        payload = {}

if not payload.get('success', False):
    errors.append('tools/call no regresó success=true')

for key in ['message', 'screenshotPath', 'resultPath']:
    if key not in payload:
        errors.append(f'tools/call sin campo esperado: {key}')

if errors:
    print('[FAIL] Smoke staging falló')
    for e in errors:
        print(' -', e)
    print('[DEBUG] call payload:', json.dumps(payload, ensure_ascii=False))
    sys.exit(1)

print('[OK] Smoke staging E2E completo')
print('[INFO] tools_count:', len(tools))
print('[INFO] call_backend:', payload.get('backend'))
PY

echo "[OK] Staging smoke finalizado"
