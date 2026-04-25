#!/usr/bin/env bash
# healthcheck.sh — Valida que el ambiente esté operativo
# Uso: ./scripts/healthcheck.sh
# Sale con código 0 si todo está OK, 1 si hay fallos.

set -euo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTEC_ROOT="$(cd "$STACK_DIR/.." && pwd)"

# shellcheck source=./lib-env.sh
source "$STACK_DIR/scripts/lib-env.sh"

if ! ensure_supported_runtime; then
  echo "[FAIL] Ejecuta healthcheck en Linux/macOS o WSL2 (Ubuntu)."
  exit 1
fi

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail_check() { echo -e "${RED}[FAIL]${NC} $*"; FAILURES=$((FAILURES + 1)); }

FAILURES=0

cd "$STACK_DIR"

if [ -f ".env" ]; then
  load_env_file "$STACK_DIR/.env"
fi

normalize_path_var "OPENCLAW_CONFIG_DIR" "$STACK_DIR" "../.openclaw"
normalize_path_var "AGENTEC_STACK_CONFIG_DIR" "$STACK_DIR" "./config"

GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
MCP_PORT="${AGENTEC_MCP_PORT:-3002}"
MCP_PY_PORT="${AGENTEC_MCP_PY_PORT:-3102}"
SHADOW_MODE="${AGENTEC_SHADOW_MODE:-0}"
GOLDEN_TEST="${AGENTEC_GOLDEN_TEST:-0}"

echo ""
echo "============================================================"
echo " agentec-openclaw-stack healthcheck — $(date)"
echo "============================================================"

# 1. Docker responde sin sudo
if docker info &>/dev/null; then
  ok "Docker: accesible sin sudo"
else
  fail_check "Docker: no responde o requiere sudo"
fi

# 2. Contenedores corriendo
for svc in openclaw-gateway agentec-mcp-server; do
  STATE=$(docker compose ps --status running --quiet "$svc" 2>/dev/null || true)
  if [ -n "$STATE" ]; then
    ok "Contenedor $svc: running"
  else
    fail_check "Contenedor $svc: no está corriendo"
  fi
done

if [ "$SHADOW_MODE" = "1" ]; then
  STATE=$(docker compose ps --status running --quiet "agentec-mcp-server-py" 2>/dev/null || true)
  if [ -n "$STATE" ]; then
    ok "Contenedor agentec-mcp-server-py: running"
  else
    fail_check "Contenedor agentec-mcp-server-py: no está corriendo"
  fi
fi

# 3. Gateway healthz
if curl -sf "http://localhost:$GATEWAY_PORT/healthz" &>/dev/null; then
  ok "Gateway /healthz: responde (puerto $GATEWAY_PORT)"
else
  fail_check "Gateway /healthz: no responde en puerto $GATEWAY_PORT"
fi

# 3b. MCP health
if curl -sf "http://localhost:$MCP_PORT/health" &>/dev/null; then
  ok "MCP /health: responde (puerto $MCP_PORT)"
else
  fail_check "MCP /health: no responde en puerto $MCP_PORT"
fi

if [ "$SHADOW_MODE" = "1" ]; then
  if curl -sf "http://localhost:$MCP_PY_PORT/health" &>/dev/null; then
    ok "MCP Python /health: responde (puerto $MCP_PY_PORT)"
  else
    fail_check "MCP Python /health: no responde en puerto $MCP_PY_PORT"
  fi
fi

# 4. Repos sincronizados (HEAD en remote)
check_repo_sync() {
  local name="$1"
  local path="$2"
  if [ ! -d "$path/.git" ]; then
    warn "$name: repo no encontrado en $path"
    return
  fi
  git -C "$path" fetch --quiet origin 2>/dev/null || { warn "$name: no se pudo verificar remote"; return; }
  LOCAL=$(git -C "$path" rev-parse HEAD)
  REMOTE=$(git -C "$path" rev-parse "@{u}" 2>/dev/null || echo "")
  if [ -z "$REMOTE" ]; then
    warn "$name: sin upstream configurado"
  elif [ "$LOCAL" = "$REMOTE" ]; then
    ok "$name: sincronizado con remote"
  else
    warn "$name: hay commits pendientes de pull"
  fi
}

check_repo_sync "openclaw"          "$AGENTEC_ROOT/openclaw"
check_repo_sync "agentec-catalog"   "$AGENTEC_ROOT/agentec-catalog"
check_repo_sync "agentec-skills"    "$AGENTEC_ROOT/agentec-skills"
check_repo_sync "agentec-tools"     "$AGENTEC_ROOT/agentec-tools"

# 5. Skills disponibles en repo local
SKILLS_SOURCE_DIR="${AGENTEC_SKILLS_DIR:-$AGENTEC_ROOT/agentec-skills/skills}"
REQUIRED_SKILLS=(
  "web-login-monitor"
  "web-login-monitor-py"
  "graph-mail"
  "graph-files"
)

for skill in "${REQUIRED_SKILLS[@]}"; do
  if [ -d "$SKILLS_SOURCE_DIR/$skill" ]; then
    ok "Skill $skill: disponible en $SKILLS_SOURCE_DIR"
  else
    fail_check "Skill $skill: NO encontrada en $SKILLS_SOURCE_DIR"
  fi
done

# 6. openclaw.json base existe
OPENCLAW_JSON="${OPENCLAW_CONFIG_DIR:-$HOME/.openclaw}/openclaw.json"
if [ -f "$OPENCLAW_JSON" ]; then
  ok "openclaw.json: presente en ~/.openclaw/"
  if grep -q '"mode"[[:space:]]*:[[:space:]]*"local"' "$OPENCLAW_JSON"; then
    ok "openclaw.json: gateway.mode=local"
  else
    fail_check "openclaw.json: falta gateway.mode=local"
  fi
else
  fail_check "openclaw.json: NO encontrado en $OPENCLAW_JSON"
fi

# 6b. Configuración reusable existe
STACK_CONFIG_DIR="${AGENTEC_STACK_CONFIG_DIR:-$STACK_DIR/config}"
WEB_LOGIN_PROFILES="$STACK_CONFIG_DIR/tools/web-login/profiles.json"
GRAPH_PROFILES="$STACK_CONFIG_DIR/tools/graph/profiles.json"

if [ -f "$WEB_LOGIN_PROFILES" ]; then
  ok "Config web-login: presente en $WEB_LOGIN_PROFILES"
else
  fail_check "Config web-login: NO encontrada en $WEB_LOGIN_PROFILES"
fi

if [ -f "$GRAPH_PROFILES" ]; then
  ok "Config graph: presente en $GRAPH_PROFILES"
else
  fail_check "Config graph: NO encontrada en $GRAPH_PROFILES"
fi

# 6c. Tools aprobadas visibles por MCP
TOOLS_LIST_PAYLOAD='{"jsonrpc":"2.0","id":"healthcheck-tools-list","method":"tools/list","params":{}}'
TOOLS_LIST_RESULT=$(curl -sf -X POST "http://localhost:$MCP_PORT/mcp" \
  -H "Content-Type: application/json" \
  -d "$TOOLS_LIST_PAYLOAD" 2>/dev/null || echo '{"error":"request_failed"}')

REQUIRED_TOOLS=(
  "web_login_playwright"
  "web_login_playwright_py"
  "graph_mail"
  "graph_files"
)

if echo "$TOOLS_LIST_RESULT" | grep -q '"error":"request_failed"'; then
  fail_check "tools/list: no respondió correctamente en MCP"
else
  for tool_name in "${REQUIRED_TOOLS[@]}"; do
    if echo "$TOOLS_LIST_RESULT" | grep -q "\"name\":\"$tool_name\"\|\"name\": \"$tool_name\""; then
      ok "Tool $tool_name: visible en tools/list"
    else
      fail_check "Tool $tool_name: NO visible en tools/list"
    fi
  done
fi

# 7. Prueba mínima: invocar tool aprobada vía MCP con input de ejemplo
TEST_INPUT="$AGENTEC_ROOT/agentec-tools/tools/web-login-playwright/input.json"
if [ ! -f "$TEST_INPUT" ]; then
  TEST_INPUT="$AGENTEC_ROOT/agentec-tools/tools/web-login-playwright/input.example.json"
fi

if [ -f "$TEST_INPUT" ]; then
  echo "  Ejecutando prueba mínima de login web vía MCP..."
  MCP_ARGS=$(cat "$TEST_INPUT")
  MCP_PAYLOAD=$(cat <<EOF
{"jsonrpc":"2.0","id":"healthcheck-login","method":"tools/call","params":{"name":"web_login_playwright","arguments":$MCP_ARGS}}
EOF
)

  RESULT=$(curl -sf -X POST "http://localhost:$MCP_PORT/mcp" \
    -H "Content-Type: application/json" \
    -d "$MCP_PAYLOAD" 2>/dev/null || echo '{"error":"request_failed"}')

  if echo "$RESULT" | grep -q '"success": true\|"success":true'; then
    ok "Tool web_login_playwright: prueba de login exitosa"
  else
    warn "Tool web_login_playwright: prueba de login falló (puede ser red o sitio externo)."
  fi
else
  warn "input.json de prueba no encontrado — omitiendo prueba de ejecución"
fi


# 8. Shadow compare Node vs Python
if [ "$SHADOW_MODE" = "1" ]; then
  if [ -x "$STACK_DIR/scripts/mcp-shadow-compare.sh" ]; then
    if "$STACK_DIR/scripts/mcp-shadow-compare.sh" &>/dev/null; then
      ok "Shadow compare Node vs Python: sin divergencias críticas"
    else
      fail_check "Shadow compare Node vs Python: divergencias detectadas"
    fi
  else
    warn "Script mcp-shadow-compare.sh no ejecutable — omitiendo comparación shadow"
  fi
fi

# 9. Golden test Node vs Python (opcional)
if [ "$SHADOW_MODE" = "1" ] && [ "$GOLDEN_TEST" = "1" ]; then
  if [ -x "$STACK_DIR/scripts/mcp-golden-test.sh" ]; then
    if "$STACK_DIR/scripts/mcp-golden-test.sh" &>/dev/null; then
      ok "Golden test Node vs Python: OK"
    else
      fail_check "Golden test Node vs Python: falló"
    fi
  else
    warn "Script mcp-golden-test.sh no ejecutable — omitiendo golden test"
  fi
fi

# ─── Resumen ─────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
if [ "$FAILURES" -eq 0 ]; then
  echo -e "${GREEN} AMBIENTE LISTO — todos los checks pasaron${NC}"
else
  echo -e "${RED} $FAILURES CHECK(S) FALLARON — revisa los [FAIL] arriba${NC}"
fi
echo "============================================================"
echo ""

exit "$FAILURES"
