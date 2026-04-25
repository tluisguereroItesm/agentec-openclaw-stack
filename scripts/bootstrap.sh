#!/usr/bin/env bash
# bootstrap.sh — Instalación inicial de agentec-openclaw-stack
# Uso: ./scripts/bootstrap.sh
# Corre una sola vez la primera vez que se clona el stack.

set -euo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTEC_ROOT="$(cd "$STACK_DIR/.." && pwd)"
LOG_DIR="$AGENTEC_ROOT/logs"
LOG_FILE="$LOG_DIR/bootstrap-$(date +%Y%m%d-%H%M%S).log"

# shellcheck source=./lib-env.sh
source "$STACK_DIR/scripts/lib-env.sh"

# ─── colores ─────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }
step() { echo -e "\n${YELLOW}──── $* ────${NC}"; }

# Redirigir salida a log también
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================================"
echo " agentec-openclaw-stack bootstrap"
echo " $(date)"
echo " Log: $LOG_FILE"
echo "============================================================"

# ─── Fase 1: validar entorno ─────────────────────────────────────────────────
step "Validando entorno"

if ! ensure_supported_runtime; then
  fail "Ejecuta este script en Linux/macOS o dentro de WSL2 (Ubuntu)."
fi

PLATFORM="$(detect_platform)"
ok "Sistema operativo: $PLATFORM (OSTYPE=${OSTYPE:-n/a})"

for cmd in git docker curl; do
  if ! command -v "$cmd" &>/dev/null; then
    fail "Falta el comando: $cmd — instálalo antes de continuar"
  fi
  ok "Comando disponible: $cmd"
done

# Node.js — requerido para correr la tool en el host
if ! command -v node &>/dev/null; then
  warn "node no encontrado — instalando via nvm..."
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  # shellcheck disable=SC1090
  source "$HOME/.nvm/nvm.sh"
  nvm install --lts
fi
ok "Node.js: $(node --version)"

if ! docker compose version &>/dev/null; then
  fail "Docker Compose plugin no encontrado. Actualiza Docker Desktop o instala el plugin."
fi
ok "Docker Compose: disponible"

if ! docker info &>/dev/null; then
  if [[ "${PLATFORM:-}" == "linux" ]]; then
    fail "Docker no está corriendo o requiere sudo. Solución: sudo usermod -aG docker \$USER && newgrp docker"
  else
    fail "Docker no está corriendo. Asegúrate de que Docker Desktop esté iniciado."
  fi
fi
ok "Docker: corriendo"

# ─── Fase 2: estructura de carpetas ──────────────────────────────────────────
step "Creando estructura de carpetas en $AGENTEC_ROOT"

mkdir -p \
  "$AGENTEC_ROOT/stack" \
  "$AGENTEC_ROOT/openclaw" \
  "$AGENTEC_ROOT/agentec-catalog" \
  "$AGENTEC_ROOT/agentec-skills" \
  "$AGENTEC_ROOT/agentec-tools" \
  "$AGENTEC_ROOT/artifacts" \
  "$AGENTEC_ROOT/logs"

ok "Estructura de carpetas creada"

# ─── Fase 3: clonar o actualizar repositorios ────────────────────────────────
step "Clonando/actualizando repositorios"

clone_or_pull() {
  local name="$1"
  local url="$2"
  local dest="$3"

  if [ -d "$dest/.git" ]; then
    echo "  → $name: ya existe, actualizando..."
    git -C "$dest" pull --ff-only || warn "$name: no se pudo hacer pull (puede haber cambios locales)"
  else
    echo "  → $name: clonando desde $url..."
    git clone "$url" "$dest" || fail "No se pudo clonar $name desde $url"
  fi
  ok "$name"
}

AGENTEC_GIT_BASE="${AGENTEC_GIT_BASE:-git@github.com:tluisguereroItesm}"

clone_or_pull "openclaw" \
  "https://github.com/openclaw/openclaw.git" \
  "$AGENTEC_ROOT/openclaw"

clone_or_pull "agentec-catalog" \
  "$AGENTEC_GIT_BASE/agentec-catalog.git" \
  "$AGENTEC_ROOT/agentec-catalog"

clone_or_pull "agentec-skills" \
  "$AGENTEC_GIT_BASE/agentec-skills.git" \
  "$AGENTEC_ROOT/agentec-skills"

clone_or_pull "agentec-tools" \
  "$AGENTEC_GIT_BASE/agentec-tools.git" \
  "$AGENTEC_ROOT/agentec-tools"

# ─── Fase 4: archivo .env ────────────────────────────────────────────────────
step "Configurando .env"

ENV_FILE="$STACK_DIR/.env"
ENV_EXAMPLE="$STACK_DIR/.env.example"

if [ ! -f "$ENV_FILE" ]; then
  sed \
    -e "s|OPENCLAW_CONFIG_DIR=~/.openclaw|OPENCLAW_CONFIG_DIR=../.openclaw|" \
    -e "s|OPENCLAW_WORKSPACE_DIR=~/.openclaw/workspace|OPENCLAW_WORKSPACE_DIR=../.openclaw/workspace|" \
    -e "s|AGENTEC_ARTIFACTS_DIR=../artifacts|AGENTEC_ARTIFACTS_DIR=$AGENTEC_ROOT/artifacts|" \
    -e "s|AGENTEC_SKILLS_DIR=../agentec-skills/skills|AGENTEC_SKILLS_DIR=$AGENTEC_ROOT/agentec-skills/skills|" \
    -e "s|AGENTEC_TOOLS_DIR=../agentec-tools/tools|AGENTEC_TOOLS_DIR=$AGENTEC_ROOT/agentec-tools/tools|" \
    -e "s|AGENTEC_STACK_CONFIG_DIR=./config|AGENTEC_STACK_CONFIG_DIR=$STACK_DIR/config|" \
    -e "s|AGENTEC_STACK_ENV_FILE=./.env|AGENTEC_STACK_ENV_FILE=$STACK_DIR/.env|" \
    -e "s|AGENTEC_GRAPH_TOKEN_STORE_DIR=../.agentec-graph-tokens|AGENTEC_GRAPH_TOKEN_STORE_DIR=$AGENTEC_ROOT/.agentec-graph-tokens|" \
    "$ENV_EXAMPLE" > "$ENV_FILE"
  ok ".env creado con rutas absolutas desde .env.example"
else
  ok ".env ya existe"
fi

# ─── Fase 4b: setup interactivo de modelo y API key ──────────────────────────
# Solo corre si el .env todavía tiene el token placeholder (primera ejecución real)
if grep -q "change-me-to-a-long-random-token" "$ENV_FILE" 2>/dev/null || \
   grep -q "^OPENCLAW_MODEL_PRIMARY=$\|^OPENCLAW_MODEL_PRIMARY=placeholder" "$ENV_FILE" 2>/dev/null || \
   ! grep -q "^OPENCLAW_MODEL_PRIMARY=" "$ENV_FILE" 2>/dev/null; then

  echo ""
  echo -e "${YELLOW}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${YELLOW}║         CONFIGURACIÓN INICIAL DE MODELO Y API KEY        ║${NC}"
  echo -e "${YELLOW}╚══════════════════════════════════════════════════════════╝${NC}"
  echo ""

  # ── Proveedor ────────────────────────────────────────────────────────────
  echo "  Selecciona tu proveedor de modelos:"
  echo "    1) openrouter  (recomendado — acceso a muchos modelos con una sola key)"
  echo "    2) openai"
  echo "    3) anthropic"
  echo "    4) gemini"
  echo ""
  while true; do
    read -rp "  Proveedor [1-4]: " PROVIDER_CHOICE
    case "$PROVIDER_CHOICE" in
      1) PROVIDER="openrouter"; KEY_VAR="OPENROUTER_API_KEY";  break ;;
      2) PROVIDER="openai";      KEY_VAR="OPENAI_API_KEY";     break ;;
      3) PROVIDER="anthropic";   KEY_VAR="ANTHROPIC_API_KEY";  break ;;
      4) PROVIDER="gemini";      KEY_VAR="GEMINI_API_KEY";     break ;;
      *) echo "  Opción inválida, elige entre 1 y 4" ;;
    esac
  done

  # ── Modelo ────────────────────────────────────────────────────────────────
  echo ""
  echo "  Modelos sugeridos para $PROVIDER:"
  case "$PROVIDER" in
    openrouter)
      echo "    • anthropic/claude-sonnet-4-5  (Claude Sonnet — recomendado)"
      echo "    • anthropic/claude-3.5-haiku   (rápido y barato)"
      echo "    • openai/gpt-4o"
      echo "    • google/gemini-2.0-flash-001"
      echo "    • meta-llama/llama-3.3-70b-instruct:free  (gratis)"
      MODEL_PREFIX="openrouter/"
    ;;
    openai)
      echo "    • gpt-4o  (recomendado)"
      echo "    • gpt-4o-mini  (rápido y barato)"
      MODEL_PREFIX="openai/"
    ;;
    anthropic)
      echo "    • claude-sonnet-4-5  (recomendado)"
      echo "    • claude-3-5-haiku-20241022  (rápido)"
      MODEL_PREFIX="anthropic/"
    ;;
    gemini)
      echo "    • gemini-2.0-flash-001  (recomendado)"
      echo "    • gemini-1.5-pro"
      MODEL_PREFIX="gemini/"
    ;;
  esac
  echo ""
  read -rp "  Ingresa el nombre del modelo (solo la parte después de $MODEL_PREFIX): " MODEL_INPUT
  MODEL_INPUT="$(echo "$MODEL_INPUT" | xargs)"  # trim spaces
  # si ya viene con el prefijo del proveedor, no duplicar
  if [[ "$MODEL_INPUT" == ${MODEL_PREFIX}* ]]; then
    SELECTED_MODEL="$MODEL_INPUT"
  else
    SELECTED_MODEL="${MODEL_PREFIX}${MODEL_INPUT}"
  fi

  # ── API Key ───────────────────────────────────────────────────────────────
  echo ""
  read -rsp "  Ingresa tu $KEY_VAR (no se mostrará): " USER_API_KEY
  echo ""
  USER_API_KEY="$(echo "$USER_API_KEY" | xargs)"
  if [ -z "$USER_API_KEY" ]; then
    fail "La API key no puede estar vacía."
  fi

  # ── Gateway token ─────────────────────────────────────────────────────────
  GENERATED_TOKEN="$(openssl rand -hex 32)"
  GENERATED_MCP_TOKEN="$(openssl rand -hex 32)"

  # ── Escribir en .env ──────────────────────────────────────────────────────
  sed_inplace "s|OPENCLAW_GATEWAY_TOKEN=change-me-to-a-long-random-token|OPENCLAW_GATEWAY_TOKEN=$GENERATED_TOKEN|" "$ENV_FILE"
  sed_inplace "s|AGENTEC_MCP_AUTH_TOKEN=change-me-to-a-long-random-token|AGENTEC_MCP_AUTH_TOKEN=$GENERATED_MCP_TOKEN|" "$ENV_FILE"
  # Agregar o reemplazar la key del proveedor
  if grep -q "^${KEY_VAR}=" "$ENV_FILE"; then
    sed_inplace "s|^${KEY_VAR}=.*|${KEY_VAR}=$USER_API_KEY|" "$ENV_FILE"
  elif grep -q "^# ${KEY_VAR}=" "$ENV_FILE"; then
    sed_inplace "s|^# ${KEY_VAR}=.*|${KEY_VAR}=$USER_API_KEY|" "$ENV_FILE"
  else
    echo "${KEY_VAR}=$USER_API_KEY" >> "$ENV_FILE"
  fi
  # Guardar modelo seleccionado
  if grep -q "^OPENCLAW_MODEL_PRIMARY=" "$ENV_FILE"; then
    sed_inplace "s|^OPENCLAW_MODEL_PRIMARY=.*|OPENCLAW_MODEL_PRIMARY=$SELECTED_MODEL|" "$ENV_FILE"
  else
    echo "OPENCLAW_MODEL_PRIMARY=$SELECTED_MODEL" >> "$ENV_FILE"
  fi

  echo ""
  ok "Proveedor:  $PROVIDER"
  ok "Modelo:     $SELECTED_MODEL"
  ok "Token:      generado automáticamente"
  ok "Configuración guardada en .env"
fi

# ─── Fase 5: directorios persistentes de OpenClaw ────────────────────────────
step "Creando directorios persistentes de OpenClaw"

# Recargar .env para tener las variables recién escritas
load_env_file "$ENV_FILE"

normalize_path_var "OPENCLAW_CONFIG_DIR" "$STACK_DIR" "../.openclaw"
normalize_path_var "OPENCLAW_WORKSPACE_DIR" "$STACK_DIR" "../.openclaw/workspace"
normalize_path_var "AGENTEC_STACK_CONFIG_DIR" "$STACK_DIR" "./config"
normalize_path_var "AGENTEC_GRAPH_TOKEN_STORE_DIR" "$STACK_DIR" "../.agentec-graph-tokens"

OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-$HOME/.openclaw}"
OPENCLAW_WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-$HOME/.openclaw/workspace}"
STACK_CONFIG_DIR="${AGENTEC_STACK_CONFIG_DIR:-$STACK_DIR/config}"
GRAPH_TOKEN_STORE_DIR="${AGENTEC_GRAPH_TOKEN_STORE_DIR:-$AGENTEC_ROOT/.agentec-graph-tokens}"

mkdir -p \
  "$OPENCLAW_CONFIG_DIR" \
  "$OPENCLAW_WORKSPACE_DIR" \
  "$STACK_CONFIG_DIR/tools/web-login" \
  "$STACK_CONFIG_DIR/tools/graph" \
  "$GRAPH_TOKEN_STORE_DIR"
ok "~/.openclaw y ~/.openclaw/workspace listos"

if [ -f "$STACK_CONFIG_DIR/tools/web-login/profiles.example.json" ] && [ ! -f "$STACK_CONFIG_DIR/tools/web-login/profiles.json" ]; then
  cp "$STACK_CONFIG_DIR/tools/web-login/profiles.example.json" "$STACK_CONFIG_DIR/tools/web-login/profiles.json"
  ok "profiles.json de web-login creado desde ejemplo"
fi

if [ -f "$STACK_CONFIG_DIR/tools/graph/profiles.example.json" ] && [ ! -f "$STACK_CONFIG_DIR/tools/graph/profiles.json" ]; then
  cp "$STACK_CONFIG_DIR/tools/graph/profiles.example.json" "$STACK_CONFIG_DIR/tools/graph/profiles.json"
  ok "profiles.json de graph creado desde ejemplo"
fi

cp "$ENV_FILE" "$STACK_CONFIG_DIR/stack.env"
ok "stack.env sincronizado para tools y runners locales"

# Generar openclaw.json con el modelo seleccionado por el usuario
MODEL_PRIMARY="${OPENCLAW_MODEL_PRIMARY:-openrouter/meta-llama/llama-3.3-70b-instruct:free}"
MCP_SERVER_URL_INTERNAL="${AGENTEC_MCP_SERVER_URL_INTERNAL:-http://agentec-mcp-server:3000/mcp}"
MCP_AUTH_TOKEN="${AGENTEC_MCP_AUTH_TOKEN:-}"

# ─── Fase 6: levantar Docker ─────────────────────────────────────────────────
ensure_openclaw_local_config "$OPENCLAW_CONFIG_DIR" "$MODEL_PRIMARY" "$MCP_SERVER_URL_INTERNAL" "$MCP_AUTH_TOKEN"
ok "openclaw.json generado con modelo: $MODEL_PRIMARY y MCP server: $MCP_SERVER_URL_INTERNAL"

# ─── Fase 5b: construir imagen del MCP server ────────────────────────────────
step "Construyendo imagen Docker del MCP server (agentec-mcp-server)"

cd "$STACK_DIR"
echo "  → docker compose build agentec-mcp-server (incluye Playwright/Chromium - puede tardar ~3 min la primera vez)..."
docker compose build agentec-mcp-server
ok "Imagen agentec-mcp-server construida"

if [ "${AGENTEC_SHADOW_MODE:-0}" = "1" ]; then
  step "Construyendo imagen Docker del MCP server Python (shadow)"
  echo "  → docker compose --profile shadow build agentec-mcp-server-py"
  docker compose --profile shadow build agentec-mcp-server-py
  ok "Imagen agentec-mcp-server-py construida"
fi
step "Levantando servicios Docker"

cd "$STACK_DIR"

# Levantar gateway + MCP server
docker compose up -d openclaw-gateway agentec-mcp-server
ok "Servicios levantados"

if [ "${AGENTEC_SHADOW_MODE:-0}" = "1" ]; then
  docker compose --profile shadow up -d agentec-mcp-server-py
  ok "Servicio shadow agentec-mcp-server-py levantado"
fi

# ─── Fase 7: esperar gateway y MCP server ────────────────────────────────────
step "Validando que los servicios responden"

GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
MCP_PORT="${AGENTEC_MCP_PORT:-3002}"
MCP_PY_PORT="${AGENTEC_MCP_PY_PORT:-3102}"
MAX_WAIT=90
WAITED=0

echo "  Esperando gateway en puerto $GATEWAY_PORT (máximo ${MAX_WAIT}s)..."
until curl -sf "http://localhost:$GATEWAY_PORT/healthz" &>/dev/null; do
  sleep 2
  WAITED=$((WAITED + 2))
  if [ "$WAITED" -ge "$MAX_WAIT" ]; then
    fail "Gateway no respondió en ${MAX_WAIT}s. Revisa: docker compose logs openclaw-gateway"
  fi
done
ok "Gateway responde en http://localhost:$GATEWAY_PORT"

WAITED=0
echo "  Esperando MCP server en puerto $MCP_PORT (máximo ${MAX_WAIT}s)..."
until curl -sf "http://localhost:$MCP_PORT/health" &>/dev/null; do
  sleep 2
  WAITED=$((WAITED + 2))
  if [ "$WAITED" -ge "$MAX_WAIT" ]; then
    warn "MCP server tardó más de ${MAX_WAIT}s — puede seguir iniciando. Revisa: docker compose logs agentec-mcp-server"
    break
  fi
done
ok "MCP server responde en http://localhost:$MCP_PORT/health"

if [ "${AGENTEC_SHADOW_MODE:-0}" = "1" ]; then
  WAITED=0
  echo "  Esperando MCP Python (shadow) en puerto $MCP_PY_PORT (máximo ${MAX_WAIT}s)..."
  until curl -sf "http://localhost:$MCP_PY_PORT/health" &>/dev/null; do
    sleep 2
    WAITED=$((WAITED + 2))
    if [ "$WAITED" -ge "$MAX_WAIT" ]; then
      warn "MCP Python shadow tardó más de ${MAX_WAIT}s — revisa: docker compose --profile shadow logs agentec-mcp-server-py"
      break
    fi
  done
  ok "MCP Python shadow responde en http://localhost:$MCP_PY_PORT/health"
fi

# ─── Resultado final ─────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo -e "${GREEN} Bootstrap completado exitosamente${NC}"
echo "============================================================"
echo ""
echo "  Gateway:    http://localhost:$GATEWAY_PORT"
echo "  MCP server: http://localhost:$MCP_PORT/health"
if [ "${AGENTEC_SHADOW_MODE:-0}" = "1" ]; then
  echo "  MCP shadow: http://localhost:$MCP_PY_PORT/health"
fi
echo "  Logs:       $LOG_FILE"
echo ""
echo "  Herramientas disponibles en el agente:"
echo "    • web_login_playwright — ejecuta flujos de login con Playwright"
echo "    • web_login_playwright_py — variante Python para debug/shadow local"
echo "    • graph_mail / graph_files — acceso reusable a correo y archivos Microsoft Graph"
echo ""
echo "  Próximos pasos:"
echo "    1. Abre http://localhost:$GATEWAY_PORT en tu navegador"
echo "    2. Edita $STACK_CONFIG_DIR/tools/web-login/profiles.json y $STACK_CONFIG_DIR/tools/graph/profiles.json"
echo "    3. Para detener: docker compose down"
echo "    4. Para reiniciar: docker compose up -d openclaw-gateway agentec-mcp-server"
if [ "${AGENTEC_SHADOW_MODE:-0}" = "1" ]; then
  echo "    5. Comparar Node vs Python: ./scripts/mcp-shadow-compare.sh"
fi
echo ""

