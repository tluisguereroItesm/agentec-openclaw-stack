#!/usr/bin/env bash
# mcp-shadow-compare.sh — compara responses entre MCP Node y MCP Python
# Uso: ./scripts/mcp-shadow-compare.sh

set -euo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTEC_ROOT="$(cd "$STACK_DIR/.." && pwd)"

# shellcheck source=./lib-env.sh
source "$STACK_DIR/scripts/lib-env.sh"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

cd "$STACK_DIR"

if [ -f ".env" ]; then
    load_env_file "$STACK_DIR/.env"
fi

NODE_PORT="${AGENTEC_MCP_PORT:-3002}"
PY_PORT="${AGENTEC_MCP_PY_PORT:-3102}"
TOKEN="${AGENTEC_MCP_AUTH_TOKEN:-}"
INPUT_PATH="${AGENTEC_ROOT}/agentec-tools/tools/web-login-playwright/input.json"

[ -n "$TOKEN" ] || fail "AGENTEC_MCP_AUTH_TOKEN no está definido en .env"
[ -f "$INPUT_PATH" ] || fail "No existe input de prueba: $INPUT_PATH"

NODE_URL="http://localhost:${NODE_PORT}/mcp"
PY_URL="http://localhost:${PY_PORT}/mcp"

LIST_PAYLOAD='{"jsonrpc":"2.0","id":"shadow-list","method":"tools/list","params":{}}'
CALL_ARGS="$(cat "$INPUT_PATH")"
CALL_PAYLOAD="{\"jsonrpc\":\"2.0\",\"id\":\"shadow-call\",\"method\":\"tools/call\",\"params\":{\"name\":\"web_login_playwright\",\"arguments\":$CALL_ARGS}}"

post_mcp() {
  local url="$1"
  local payload="$2"
  curl -sf -X POST "$url" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload"
}

echo "Comparando tools/list (Node vs Python)..."
NODE_LIST="$(post_mcp "$NODE_URL" "$LIST_PAYLOAD")"
PY_LIST="$(post_mcp "$PY_URL" "$LIST_PAYLOAD")"

echo "Comparando tools/call (Node vs Python)..."
NODE_CALL="$(post_mcp "$NODE_URL" "$CALL_PAYLOAD")"
PY_CALL="$(post_mcp "$PY_URL" "$CALL_PAYLOAD")"

python3 - <<'PY' "$NODE_LIST" "$PY_LIST" "$NODE_CALL" "$PY_CALL"
import json
import sys

node_list = json.loads(sys.argv[1])
py_list = json.loads(sys.argv[2])
node_call = json.loads(sys.argv[3])
py_call = json.loads(sys.argv[4])

errors = []

def tool_names(resp):
    return sorted([t.get("name") for t in resp.get("result", {}).get("tools", []) if isinstance(t, dict)])

node_tools = tool_names(node_list)
py_tools = tool_names(py_list)

if node_tools != py_tools:
    errors.append(f"tools/list diverge: node={node_tools} py={py_tools}")

def call_success(resp):
    txt = ""
    content = resp.get("result", {}).get("content", [])
    if content and isinstance(content, list) and isinstance(content[0], dict):
        txt = content[0].get("text", "")
    try:
        parsed = json.loads(txt) if txt else {}
    except json.JSONDecodeError:
        parsed = {}
    return bool(parsed.get("success")), parsed

node_ok, node_parsed = call_success(node_call)
py_ok, py_parsed = call_success(py_call)

if node_ok != py_ok:
    errors.append(f"tools/call success diverge: node={node_ok} py={py_ok}")

if errors:
    print("[FAIL] Shadow compare encontró diferencias:")
    for e in errors:
        print(" -", e)
    print("[INFO] node_call:", json.dumps(node_parsed, ensure_ascii=False))
    print("[INFO] py_call:", json.dumps(py_parsed, ensure_ascii=False))
    sys.exit(1)

print("[OK] Shadow compare sin divergencias críticas")
print("[INFO] tools:", node_tools)
print("[INFO] node_call_success:", node_ok)
print("[INFO] py_call_success:", py_ok)
PY

ok "Comparación shadow completada"
