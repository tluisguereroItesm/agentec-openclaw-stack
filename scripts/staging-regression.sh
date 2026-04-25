#!/usr/bin/env bash
# staging-regression.sh — regresión funcional sobre MCP Python en staging
# Uso: ./scripts/staging-regression.sh [--dry-run]

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
MCP_PY_PORT="${AGENTEC_MCP_PY_PORT:-3102}"
MCP_TOKEN="${AGENTEC_MCP_AUTH_TOKEN:-}"
INPUT_PATH="${AGENTEC_ROOT}/agentec-tools/tools/web-login-playwright/input.json"
ARTIFACTS_DIR="${AGENTEC_ARTIFACTS_DIR:-$AGENTEC_ROOT/artifacts}"
LIST_ITERS="${AGENTEC_REGRESSION_ITERATIONS_LIST:-10}"
CALL_ITERS="${AGENTEC_REGRESSION_ITERATIONS_CALL:-10}"
MAX_ERROR_RATE="${AGENTEC_REGRESSION_MAX_ERROR_RATE:-0.05}"

if [ "$DRY_RUN" = "1" ]; then
  echo "[DRY-RUN] staging-regression sobre puerto $MCP_PY_PORT"
  echo "[DRY-RUN] list_iters=$LIST_ITERS call_iters=$CALL_ITERS max_error_rate=$MAX_ERROR_RATE"
  exit 0
fi

[ "$ENV_NAME" = "staging" ] || echo "[WARN] AGENTEC_ENV=$ENV_NAME (esperado: staging)"
[ -n "$MCP_TOKEN" ] || { echo "[FAIL] AGENTEC_MCP_AUTH_TOKEN vacío"; exit 1; }
[ -f "$INPUT_PATH" ] || { echo "[FAIL] input no encontrado: $INPUT_PATH"; exit 1; }
mkdir -p "$ARTIFACTS_DIR"

python3 - <<'PY' "$MCP_PY_PORT" "$MCP_TOKEN" "$INPUT_PATH" "$ARTIFACTS_DIR" "$LIST_ITERS" "$CALL_ITERS" "$MAX_ERROR_RATE"
from __future__ import annotations

import json
import statistics
import sys
import time
from pathlib import Path
from urllib import request, error

mcp_port, token, input_path, artifacts_dir, list_iters, call_iters, max_error_rate = sys.argv[1:8]
list_iters = int(list_iters)
call_iters = int(call_iters)
max_error_rate = float(max_error_rate)

mcp_url = f"http://localhost:{mcp_port}/mcp"

with open(input_path, "r", encoding="utf-8") as f:
    call_args = json.load(f)


def p95(values: list[float]) -> float:
    if not values:
        return 0.0
    sorted_vals = sorted(values)
    idx = int(round(0.95 * (len(sorted_vals) - 1)))
    return sorted_vals[idx]


def post_json(payload: dict) -> tuple[int, dict | None, float, str | None]:
    body = json.dumps(payload).encode("utf-8")
    req = request.Request(
        mcp_url,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        data=body,
    )
    started = time.perf_counter()
    try:
        with request.urlopen(req, timeout=90) as resp:
            latency_ms = (time.perf_counter() - started) * 1000
            text = resp.read().decode("utf-8", errors="replace")
            parsed = json.loads(text)
            return resp.status, parsed, latency_ms, None
    except error.HTTPError as exc:
        latency_ms = (time.perf_counter() - started) * 1000
        details = exc.read().decode("utf-8", errors="replace")
        return exc.code, None, latency_ms, details
    except Exception as exc:  # noqa: BLE001
        latency_ms = (time.perf_counter() - started) * 1000
        return 0, None, latency_ms, str(exc)


list_latencies: list[float] = []
call_latencies: list[float] = []
errors: list[str] = []

for i in range(list_iters):
    payload = {"jsonrpc": "2.0", "id": f"reg-list-{i}", "method": "tools/list", "params": {}}
    status, data, latency, err = post_json(payload)
    list_latencies.append(latency)
    if status != 200 or not isinstance(data, dict):
        errors.append(f"tools/list iter={i} status={status} err={err}")
        continue
    tools = [
        t.get("name")
        for t in data.get("result", {}).get("tools", [])
        if isinstance(t, dict)
    ]
    if "web_login_playwright" not in tools:
        errors.append(f"tools/list iter={i} missing web_login_playwright")

for i in range(call_iters):
    payload = {
        "jsonrpc": "2.0",
        "id": f"reg-call-{i}",
        "method": "tools/call",
        "params": {"name": "web_login_playwright", "arguments": call_args},
    }
    status, data, latency, err = post_json(payload)
    call_latencies.append(latency)
    if status != 200 or not isinstance(data, dict):
        errors.append(f"tools/call iter={i} status={status} err={err}")
        continue

    content = data.get("result", {}).get("content", [])
    payload_json = {}
    if content and isinstance(content, list) and isinstance(content[0], dict):
        txt = content[0].get("text", "")
        try:
            payload_json = json.loads(txt) if txt else {}
        except json.JSONDecodeError:
            payload_json = {}

    if not payload_json.get("success", False):
        errors.append(f"tools/call iter={i} success=false payload={payload_json}")

for key in ["message", "screenshotPath", "resultPath"]:
        if key not in payload_json:
            errors.append(f"tools/call iter={i} missing key={key}")


all_calls = list_iters + call_iters
error_rate = (len(errors) / all_calls) if all_calls else 0.0

report = {
    "timestamp": int(time.time()),
    "env": "staging",
    "endpoint": mcp_url,
    "iterations": {
        "tools_list": list_iters,
        "tools_call": call_iters,
    },
    "metrics": {
        "tools_list": {
            "avg_ms": round(statistics.mean(list_latencies), 2) if list_latencies else 0.0,
            "p95_ms": round(p95(list_latencies), 2),
            "max_ms": round(max(list_latencies), 2) if list_latencies else 0.0,
        },
        "tools_call": {
            "avg_ms": round(statistics.mean(call_latencies), 2) if call_latencies else 0.0,
            "p95_ms": round(p95(call_latencies), 2),
            "max_ms": round(max(call_latencies), 2) if call_latencies else 0.0,
        },
        "error_rate": round(error_rate, 6),
    },
    "thresholds": {
        "max_error_rate": max_error_rate,
    },
    "errors": errors,
}

report_path = Path(artifacts_dir) / f"staging-regression-report-{report['timestamp']}.json"
report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")

if error_rate > max_error_rate:
    print("[FAIL] Regresión excede error rate")
    print(f"[INFO] error_rate={error_rate:.4f} threshold={max_error_rate:.4f}")
    print(f"[INFO] report={report_path}")
    sys.exit(1)

print("[OK] Regresión staging completada")
print(f"[INFO] error_rate={error_rate:.4f}")
print(f"[INFO] list_p95_ms={report['metrics']['tools_list']['p95_ms']}")
print(f"[INFO] call_p95_ms={report['metrics']['tools_call']['p95_ms']}")
print(f"[INFO] report={report_path}")
PY
