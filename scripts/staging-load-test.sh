#!/usr/bin/env bash
# staging-load-test.sh — carga básica concurrente contra MCP Python en staging
# Uso: ./scripts/staging-load-test.sh [--dry-run]

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
TOTAL_REQUESTS="${AGENTEC_LOAD_TOTAL_REQUESTS:-30}"
CONCURRENCY="${AGENTEC_LOAD_CONCURRENCY:-6}"
MAX_ERROR_RATE="${AGENTEC_LOAD_MAX_ERROR_RATE:-0.10}"
P95_TARGET_MS="${AGENTEC_LOAD_P95_TARGET_MS:-3000}"

if [ "$DRY_RUN" = "1" ]; then
  echo "[DRY-RUN] staging-load-test sobre puerto $MCP_PY_PORT"
  echo "[DRY-RUN] total=$TOTAL_REQUESTS concurrency=$CONCURRENCY max_error_rate=$MAX_ERROR_RATE p95_target_ms=$P95_TARGET_MS"
  exit 0
fi

[ "$ENV_NAME" = "staging" ] || echo "[WARN] AGENTEC_ENV=$ENV_NAME (esperado: staging)"
[ -n "$MCP_TOKEN" ] || { echo "[FAIL] AGENTEC_MCP_AUTH_TOKEN vacío"; exit 1; }
[ -f "$INPUT_PATH" ] || { echo "[FAIL] input no encontrado: $INPUT_PATH"; exit 1; }
mkdir -p "$ARTIFACTS_DIR"

python3 - <<'PY' "$MCP_PY_PORT" "$MCP_TOKEN" "$INPUT_PATH" "$ARTIFACTS_DIR" "$TOTAL_REQUESTS" "$CONCURRENCY" "$MAX_ERROR_RATE" "$P95_TARGET_MS"
from __future__ import annotations

import json
import statistics
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib import request, error

mcp_port, token, input_path, artifacts_dir, total_requests, concurrency, max_error_rate, p95_target_ms = sys.argv[1:9]
total_requests = int(total_requests)
concurrency = int(concurrency)
max_error_rate = float(max_error_rate)
p95_target_ms = float(p95_target_ms)

mcp_url = f"http://localhost:{mcp_port}/mcp"

with open(input_path, "r", encoding="utf-8") as f:
    call_args = json.load(f)

payload_template = {
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
        "name": "web_login_playwright",
        "arguments": call_args,
    },
}


def p95(values: list[float]) -> float:
    if not values:
        return 0.0
    vals = sorted(values)
    idx = int(round(0.95 * (len(vals) - 1)))
    return vals[idx]


def send_call(i: int) -> dict:
    payload = dict(payload_template)
    payload["id"] = f"load-{i}"
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
        with request.urlopen(req, timeout=120) as resp:
            latency_ms = (time.perf_counter() - started) * 1000
            text = resp.read().decode("utf-8", errors="replace")
            parsed = json.loads(text)
            content = parsed.get("result", {}).get("content", [])
            payload_json = {}
            if content and isinstance(content, list) and isinstance(content[0], dict):
                txt = content[0].get("text", "")
                try:
                    payload_json = json.loads(txt) if txt else {}
                except json.JSONDecodeError:
                    payload_json = {}
            ok = resp.status == 200 and bool(payload_json.get("success", False))
            return {"ok": ok, "status": resp.status, "latency_ms": latency_ms, "error": None}
    except error.HTTPError as exc:
        latency_ms = (time.perf_counter() - started) * 1000
        details = exc.read().decode("utf-8", errors="replace")
        return {"ok": False, "status": exc.code, "latency_ms": latency_ms, "error": details}
    except Exception as exc:  # noqa: BLE001
        latency_ms = (time.perf_counter() - started) * 1000
        return {"ok": False, "status": 0, "latency_ms": latency_ms, "error": str(exc)}

started_all = time.perf_counter()
results = []
with ThreadPoolExecutor(max_workers=concurrency) as pool:
    futures = [pool.submit(send_call, i) for i in range(total_requests)]
    for fut in as_completed(futures):
        results.append(fut.result())

elapsed_s = time.perf_counter() - started_all

latencies = [r["latency_ms"] for r in results]
errors = [r for r in results if not r["ok"]]
error_rate = (len(errors) / total_requests) if total_requests else 0.0
throughput_rps = (total_requests / elapsed_s) if elapsed_s > 0 else 0.0

report = {
    "timestamp": int(time.time()),
    "env": "staging",
    "endpoint": mcp_url,
    "load": {
        "total_requests": total_requests,
        "concurrency": concurrency,
        "elapsed_seconds": round(elapsed_s, 3),
        "throughput_rps": round(throughput_rps, 3),
    },
    "metrics": {
        "avg_ms": round(statistics.mean(latencies), 2) if latencies else 0.0,
        "p95_ms": round(p95(latencies), 2),
        "max_ms": round(max(latencies), 2) if latencies else 0.0,
        "error_rate": round(error_rate, 6),
    },
    "thresholds": {
        "max_error_rate": max_error_rate,
        "p95_target_ms": p95_target_ms,
    },
    "errors_sample": errors[:10],
}

report_path = Path(artifacts_dir) / f"staging-load-report-{report['timestamp']}.json"
report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")

hard_fail = error_rate > max_error_rate
if hard_fail:
    print("[FAIL] Load test excede error rate")
    print(f"[INFO] error_rate={error_rate:.4f} threshold={max_error_rate:.4f}")
    print(f"[INFO] p95_ms={report['metrics']['p95_ms']}")
    print(f"[INFO] report={report_path}")
    sys.exit(1)

if report["metrics"]["p95_ms"] > p95_target_ms:
    print("[WARN] Load test fuera de objetivo p95")
    print(f"[INFO] p95_ms={report['metrics']['p95_ms']} target={p95_target_ms}")
else:
    print("[OK] Load test dentro de objetivo p95")

print(f"[INFO] throughput_rps={report['load']['throughput_rps']}")
print(f"[INFO] error_rate={error_rate:.4f}")
print(f"[INFO] report={report_path}")
PY
