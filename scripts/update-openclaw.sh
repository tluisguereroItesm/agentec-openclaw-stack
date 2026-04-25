#!/usr/bin/env bash
# update-openclaw.sh — Actualiza la imagen de OpenClaw de forma controlada
# Uso: ./scripts/update-openclaw.sh [--apply]
#
# Sin argumentos: muestra la versión actual vs la disponible (safe, sin cambios)
# Con --apply:    hace pull de latest y actualiza OPENCLAW_IMAGE en .env con el digest

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$STACK_DIR/.env"
APPLY=0

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --help|-h)
      grep '^#' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) warn "Argumento desconocido: $1"; exit 1 ;;
  esac
  shift
done

if ! command -v docker &>/dev/null; then
  error "Docker no encontrado"
  exit 1
fi

REPO="ghcr.io/openclaw/openclaw"

# ─── Versión actualmente usada ─────────────────────────────────────────────
CURRENT_IMAGE=""
if [[ -f "$ENV_FILE" ]]; then
  CURRENT_IMAGE=$(grep -E "^OPENCLAW_IMAGE=" "$ENV_FILE" | cut -d= -f2- | tr -d '"' || true)
fi
if [[ -z "$CURRENT_IMAGE" ]]; then
  CURRENT_IMAGE="${OPENCLAW_IMAGE:-$REPO:latest}"
fi

info "Imagen en uso:     $CURRENT_IMAGE"

# Obtener digest local de la imagen actual (si está descargada)
CURRENT_DIGEST=$(docker inspect "$CURRENT_IMAGE" --format '{{index .RepoDigests 0}}' 2>/dev/null || echo "no descargada")
info "Digest local:      $CURRENT_DIGEST"

echo ""

if [[ "$APPLY" -eq 0 ]]; then
  info "Ejecuta con --apply para hacer pull y actualizar .env"
  info "ADVERTENCIA: Revisa el CHANGELOG antes de aplicar:"
  info "  https://github.com/openclaw/openclaw/releases"
  exit 0
fi

# ─── Pull de latest ────────────────────────────────────────────────────────
info "Haciendo pull de $REPO:latest ..."
docker pull "$REPO:latest"

NEW_DIGEST=$(docker inspect "$REPO:latest" --format '{{index .RepoDigests 0}}' 2>/dev/null || true)

if [[ -z "$NEW_DIGEST" ]]; then
  error "No se pudo obtener el digest de la imagen descargada"
  exit 1
fi

info "Nuevo digest:      $NEW_DIGEST"

if [[ "$CURRENT_DIGEST" == "$NEW_DIGEST" ]]; then
  success "Ya estás en la versión más reciente — no hay cambios"
  exit 0
fi

echo ""
warn "La imagen cambió:"
warn "  Antes: $CURRENT_DIGEST"
warn "  Ahora: $NEW_DIGEST"
echo ""
warn "⚠ Asegúrate de haber probado en staging antes de continuar."
read -r -p "¿Actualizar OPENCLAW_IMAGE en .env? [s/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[sS]$ ]]; then
  info "Cancelado por el usuario"
  exit 0
fi

if [[ ! -f "$ENV_FILE" ]]; then
  error ".env no encontrado en $STACK_DIR — crea uno a partir de .env.example primero"
  exit 1
fi

# Reemplazar (o agregar) OPENCLAW_IMAGE en .env
if grep -qE "^OPENCLAW_IMAGE=" "$ENV_FILE"; then
  # macOS vs Linux sed
  if [[ "${OSTYPE:-}" == "darwin"* ]]; then
    sed -i '' "s|^OPENCLAW_IMAGE=.*|OPENCLAW_IMAGE=$NEW_DIGEST|" "$ENV_FILE"
  else
    sed -i "s|^OPENCLAW_IMAGE=.*|OPENCLAW_IMAGE=$NEW_DIGEST|" "$ENV_FILE"
  fi
else
  echo "OPENCLAW_IMAGE=$NEW_DIGEST" >> "$ENV_FILE"
fi

success ".env actualizado con digest pinneado: $NEW_DIGEST"
info "Reinicia el stack para aplicar: docker compose down && docker compose up -d"
