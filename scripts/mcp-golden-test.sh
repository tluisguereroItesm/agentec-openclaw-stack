#!/usr/bin/env bash
# mcp-golden-test.sh — golden tests Node vs Python para web_login_playwright
# Uso: ./scripts/mcp-golden-test.sh

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
ARTIFACTS_DIR="${AGENTEC_ARTIFACTS_DIR:-$AGENTEC_ROOT/artifacts}"
INPUT_PATH="${AGENTEC_ROOT}/agentec-tools/tools/web-login-playwright/input.json"
MAX_DELTA_MS="${AGENTEC_GOLDEN_MAX_LATENCY_DELTA_MS:-3000}"
MAX_RATIO="${AGENTEC_GOLDEN_MAX_PY_TO_NODE_RATIO:-2.5}"

[ -n "$TOKEN" ] || fail "AGENTEC_MCP_AUTH_TOKEN no está definido en .env"
[ -f "$INPUT_PATH" ] || fail "No existe input de prueba: $INPUT_PATH"

mkdir -p "$ARTIFACTS_DIR"

NODE_URL="http://localhost:${NODE_PORT}/mcp"
PY_URL="http://localhost:${PY_PORT}/mcp"

LIST_PAYLOAD='{"jsonrpc":"2.0","id":"golden-list","method":"tools/list","params":{}}'
CALL_ARGS="$(cat "$INPUT_PATH")"
CALL_PAYLOAD="{\"jsonrpc\":\"2.0\",\"id\":\"golden-call\",\"method\":\"tools/call\",\"params\":{\"name\":\"web_login_playwright\",\"arguments\":$CALL_ARGS}}"

post_mcp_timed() {
  local url="$1"
  local payload="$2"
  curl -sS -X POST "$url" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    -w "\n__HTTP__:%{http_code}\n__TIME__:%{time_total}"
}

echo "[golden] tools/list Node..."
RAW_NODE_LIST="$(post_mcp_timed "$NODE_URL" "$LIST_PAYLOAD")"

echo "[golden] tools/list Python..."
RAW_PY_LIST="$(post_mcp_timed "$PY_URL" "$LIST_PAYLOAD")"

echo "[golden] tools/call Node..."
RAW_NODE_CALL="$(post_mcp_timed "$NODE_URL" "$CALL_PAYLOAD")"

echo "[golden] tools/call Python..."
RAW_PY_CALL="$(post_mcp_timed "$PY_URL" "$CALL_PAYLOAD")"

python3 - <<'PY' "$RAW_NODE_LIST" "$RAW_PY_LIST" "$RAW_NODE_CALL" "$RAW_PY_CALL" "$ARTIFACTS_DIR" "$MAX_DELTA_MS" "$MAX_RATIO"
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path


def split_raw(raw: str) -> tuple[str, int, float]:
    parts = raw.split("\n__HTTP__:")
    if len(parts) != 2:
        raise ValueError("Response parse error (missing HTTP marker)")
    body = parts[0]
    http_and_time = parts[1].split("\n__TIME__:")
    if len(http_and_time) != 2:
        raise ValueError("Response parse error (missing TIME marker)")
    http = int(http_and_time[0].strip())
    t_total = float(http_and_time[1].strip())
    return body, http, t_total


def parse_mcp_body(body: str) -> dict:
    return json.loads(body)


def tool_names(resp: dict) -> list[str]:
    tools = resp.get("result", {}).get("tools", [])
    return sorted([t.get("name") for t in tools if isinstance(t, dict) and isinstance(t.get("name"), str)])


def call_payload(resp: dict) -> dict:
    content = resp.get("result", {}).get("content", [])
    text = ""
    if content and isinstance(content, list) and isinstance(content[0], dict):
        text = content[0].get("text", "")
    if not text:
        return {}
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        return {}
    return parsed if isinstance(parsed, dict) else {}


def host_artifact_path(path_value: str, artifacts_dir: Path) -> Path:
    # Node/Python suelen devolver rutas dentro del contenedor: /app/artifacts/...
    if path_value.startswith("/app/artifacts/"):
        rel = path_value.removeprefix("/app/artifacts/")
        return artifacts_dir / rel
    return Path(path_value)


raw_node_list, raw_py_list, raw_node_call, raw_py_call, artifacts_dir_arg, max_delta_arg, max_ratio_arg = sys.argv[1:8]
artifacts_dir = Path(artifacts_dir_arg)
max_delta_ms = int(max_delta_arg)
max_ratio = float(max_ratio_arg)

errors: list[str] = []
warnings: list[str] = []

node_list_body, node_list_http, node_list_time = split_raw(raw_node_list)
py_list_body, py_list_http, py_list_time = split_raw(raw_py_list)
node_call_body, node_call_http, node_call_time = split_raw(raw_node_call)
py_call_body, py_call_http, py_call_time = split_raw(raw_py_call)

if node_list_http != 200:
    errors.append(f"Node tools/list HTTP {node_list_http}")
if py_list_http != 200:
    errors.append(f"Python tools/list HTTP {py_list_http}")
if node_call_http != 200:
    errors.append(f"Node tools/call HTTP {node_call_http}")
if py_call_http != 200:
    errors.append(f"Python tools/call HTTP {py_call_http}")

node_list = parse_mcp_body(node_list_body)
py_list = parse_mcp_body(py_list_body)
node_call = parse_mcp_body(node_call_body)
py_call = parse_mcp_body(py_call_body)

node_tools = tool_names(node_list)
py_tools = tool_names(py_list)
if node_tools != py_tools:
    errors.append(f"tools/list diverge: node={node_tools} py={py_tools}")

node_tool = call_payload(node_call)
py_tool = call_payload(py_call)

for key in ["success", "message", "screenshotPath", "resultPath"]:
    if key not in node_tool:
        errors.append(f"Node tools/call missing key: {key}")
    if key not in py_tool:
        errors.append(f"Python tools/call missing key: {key}")

if node_tool.get("success") != py_tool.get("success"):
    errors.append(
        f"tools/call success diverge: node={node_tool.get('success')} py={py_tool.get('success')}"
    )

for side, payload in [("node", node_tool), ("python", py_tool)]:
    for path_key in ["screenshotPath", "resultPath"]:
        raw_path = payload.get(path_key)
        if isinstance(raw_path, str) and raw_path:
            candidate = host_artifact_path(raw_path, artifacts_dir)
            if not candidate.exists():
                warnings.append(f"{side} {path_key} not found on host: {candidate}")

node_ms = round(node_call_time * 1000, 2)
py_ms = round(py_call_time * 1000, 2)
delta_ms = round(abs(py_ms - node_ms), 2)
ratio = round((py_ms / node_ms), 3) if node_ms > 0 else None

if delta_ms > max_delta_ms:
    warnings.append(f"latency delta high: {delta_ms}ms > {max_delta_ms}ms")
if ratio is not None and ratio > max_ratio:
    warnings.append(f"python/node latency ratio high: {ratio} > {max_ratio}")

report = {
    "timestamp": int(time.time()),
    "tools_list": {
        "node": node_tools,
        "python": py_tools,
        "equal": node_tools == py_tools,
        "node_http": node_list_http,
        "python_http": py_list_http,
        "node_ms": round(node_list_time * 1000, 2),
        "python_ms": round(py_list_time * 1000, 2),
    },
    "tools_call": {
        "node_http": node_call_http,
        "python_http": py_call_http,
        "node_success": node_tool.get("success"),
        "python_success": py_tool.get("success"),
        "node_message": node_tool.get("message"),
        "python_message": py_tool.get("message"),
        "node_ms": node_ms,
        "python_ms": py_ms,
        "delta_ms": delta_ms,
        "ratio_py_over_node": ratio,
    },
    "warnings": warnings,
    "errors": errors,
}

report_path = artifacts_dir / f"golden-report-{report['timestamp']}.json"
report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")

if errors:
    print("[FAIL] Golden test con errores críticos")
    for e in errors:
        print(" -", e)
    print("[INFO] report:", report_path)
    sys.exit(1)

if warnings:
    print("[WARN] Golden test pasó con advertencias")
    for w in warnings:
        print(" -", w)
else:
    print("[OK] Golden test sin divergencias")

print("[INFO] report:", report_path)
PY

ok "Golden test Node vs Python finalizado"
