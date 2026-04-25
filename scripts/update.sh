#!/usr/bin/env bash
# update.sh — Actualización mensual de todos los repositorios y servicios
# Uso: ./scripts/update.sh
# Puede ejecutarse manualmente o via cron/systemd timer.

set -euo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTEC_ROOT="$(cd "$STACK_DIR/.." && pwd)"
LOG_DIR="$AGENTEC_ROOT/logs"
LOG_FILE="$LOG_DIR/update-$(date +%Y%m%d-%H%M%S).log"

# shellcheck source=./lib-env.sh
source "$STACK_DIR/scripts/lib-env.sh"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }
step() { echo -e "\n${YELLOW}──── $* ────${NC}"; }

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================================"
echo " agentec-openclaw-stack update"
echo " $(date)"
echo " Log: $LOG_FILE"
echo "============================================================"

CHANGES_DETECTED=false
AGENTEC_GIT_BASE="${AGENTEC_GIT_BASE:-git@github.com:tluisguereroItesm}"

# Asegurar que repos faltantes existan antes de intentar pull
for repo_info in \
  "openclaw|https://github.com/openclaw/openclaw.git" \
  "agentec-catalog|$AGENTEC_GIT_BASE/agentec-catalog.git" \
  "agentec-skills|$AGENTEC_GIT_BASE/agentec-skills.git" \
  "agentec-tools|$AGENTEC_GIT_BASE/agentec-tools.git"; do
  _name="${repo_info%%|*}"
  _url="${repo_info##*|}"
  _dest="$AGENTEC_ROOT/$_name"
  if [ ! -d "$_dest/.git" ]; then
    echo "  → $_name no encontrado, clonando..."
    git clone "$_url" "$_dest"
  fi
done

# ─── Fase 1: actualizar repos ────────────────────────────────────────────────
step "Actualizando repositorios"

pull_repo() {
  local name="$1"
  local path="$2"

  if [ ! -d "$path/.git" ]; then
    warn "$name no encontrado en $path — omitido"
    return
  fi

  BEFORE=$(git -C "$path" rev-parse HEAD 2>/dev/null || echo "unknown")
  git -C "$path" pull --ff-only 2>&1 || {
    warn "$name: pull falló (puede haber cambios locales no commiteados)"
    return
  }
  AFTER=$(git -C "$path" rev-parse HEAD 2>/dev/null || echo "unknown")

  if [ "$BEFORE" != "$AFTER" ]; then
    ok "$name: actualizado ($BEFORE → $AFTER)"
    CHANGES_DETECTED=true
  else
    ok "$name: ya estaba al día"
  fi
}

pull_repo "agentec-openclaw-stack" "$STACK_DIR"
pull_repo "openclaw"               "$AGENTEC_ROOT/openclaw"
pull_repo "agentec-catalog"        "$AGENTEC_ROOT/agentec-catalog"
pull_repo "agentec-skills"         "$AGENTEC_ROOT/agentec-skills"
pull_repo "agentec-tools"          "$AGENTEC_ROOT/agentec-tools"

# ─── Fase 2: reconstruir imágenes si hubo cambios ────────────────────────────
step "Reconstruyendo imágenes Docker"

cd "$STACK_DIR"

if [ -f ".env" ]; then
  load_env_file "$STACK_DIR/.env"
fi

if [ "$CHANGES_DETECTED" = true ]; then
  docker compose build --pull agentec-mcp-server
  ok "Imagen agentec-mcp-server reconstruida"
else
  ok "Sin cambios en repos — no se reconstruye imagen"
fi

# ─── Fase 3: reiniciar servicios ─────────────────────────────────────────────
step "Reiniciando servicios"

docker compose pull openclaw-gateway 2>&1 || warn "No se pudo hacer pull de la imagen openclaw-gateway"
docker compose up -d --remove-orphans
ok "Servicios reiniciados"

# ─── Fase 4: healthcheck ─────────────────────────────────────────────────────
step "Validando estado tras actualización"

"$STACK_DIR/scripts/healthcheck.sh"

# ─── Resultado ───────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo -e "${GREEN} Update completado: $(date)${NC}"
echo " Log guardado en: $LOG_FILE"
echo "============================================================"
