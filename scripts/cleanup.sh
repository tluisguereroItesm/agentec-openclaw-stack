#!/usr/bin/env bash
# cleanup.sh — Limpieza de artifacts, logs y recursos Docker del stack Agentec
#
# Uso: ./scripts/cleanup.sh [opciones]
#   Sin argumentos     → modo interactivo (wizard con preguntas)
#
# Opciones (modo no-interactivo):
#   --dry-run           Muestra qué se borraría sin borrar nada
#   --artifacts-days N  Borrar artifacts más viejos que N días (default: 7)
#   --logs-days N       Borrar logs más viejos que N días (default: 30)
#   --docker            Limpiar imágenes y build cache de Docker
#   --docker-all        Limpiar TODO Docker (imágenes, volúmenes, build cache)
#   --tokens-pending    Borrar auth tokens con estado "pending" (login expirado)
#   --browser-sessions  Borrar sesiones y cookies del navegador web (OpenClaw/Playwright)
#   --openclaw-logs N   Borrar logs internos de OpenClaw más viejos que N días (default: 14)
#   --all               Ejecutar todas las limpiezas (equivale a todas las opciones)
#   --help              Mostrar esta ayuda

set -euo pipefail

# ─── defaults ────────────────────────────────────────────────────────────────
DRY_RUN=0
ARTIFACTS_DAYS=7
LOGS_DAYS=30
OPENCLAW_LOGS_DAYS=14
DO_DOCKER=0
DO_DOCKER_ALL=0
DO_TOKENS_PENDING=0
DO_BROWSER_SESSIONS=0
DO_ALL=0
INTERACTIVE=0

# ─── colores ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
dry()     { echo -e "${YELLOW}[DRY]${NC}  $*"; }
deleted() { echo -e "${RED}[DEL]${NC}  $*"; }
# ask va a stderr para que no lo capture la sustitución de comandos $()
ask()     { echo -e "${CYAN}${BOLD}[?]${NC}   $*" >&2; }
header()  { echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════${NC}"; echo -e "  ${BOLD}$*${NC}"; echo -e "${BOLD}${BLUE}══════════════════════════════════════════${NC}"; }

# ─── parse args ──────────────────────────────────────────────────────────────
# Si no se pasan argumentos → modo interactivo
[[ $# -eq 0 ]] && INTERACTIVE=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)              DRY_RUN=1 ;;
    --artifacts-days)       ARTIFACTS_DAYS="$2"; shift ;;
    --logs-days)            LOGS_DAYS="$2"; shift ;;
    --openclaw-logs)        OPENCLAW_LOGS_DAYS="$2"; shift ;;
    --docker)               DO_DOCKER=1 ;;
    --docker-all)           DO_DOCKER_ALL=1 ;;
    --tokens-pending)       DO_TOKENS_PENDING=1 ;;
    --browser-sessions)     DO_BROWSER_SESSIONS=1 ;;
    --all)                  DO_ALL=1 ;;
    --interactive|-i)       INTERACTIVE=1 ;;
    --help|-h)
      sed -n '/^# Uso:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0 ;;
    *)
      warn "Argumento desconocido: $1. Usa --help para ver opciones."
      exit 1 ;;
  esac
  shift
done

[[ "$DO_ALL" -eq 1 ]] && DO_DOCKER=1 && DO_TOKENS_PENDING=1 && DO_BROWSER_SESSIONS=1

# ─── wizard interactivo ───────────────────────────────────────────────────────
prompt_yn() {
  # prompt_yn "¿Pregunta?" → retorna 0 (sí) o 1 (no)
  local msg="$1" default="${2:-n}"
  local hint="[s/N]"; [[ "$default" == "s" ]] && hint="[S/n]"
  while true; do
    ask "$msg $hint "
    read -r -p "  → " reply
    reply="${reply:-$default}"
    case "${reply,,}" in
      s|si|sí|y|yes) return 0 ;;
      n|no)          return 1 ;;
      *) echo "  Responde s (sí) o n (no)." >&2 ;;
    esac
  done
}

prompt_int() {
  # prompt_int "¿Pregunta?" default → imprime el número elegido en stdout
  local msg="$1" default="$2"
  while true; do
    ask "$msg [default: ${default}] "
    read -r -p "  → " reply
    reply="${reply:-$default}"
    if [[ "$reply" =~ ^[0-9]+$ ]] && [[ "$reply" -ge 1 ]]; then
      echo "$reply"   # único output a stdout — lo captura la sustitución $()
      return 0
    else
      echo "  Ingresa un número entero mayor a 0." >&2
    fi
  done
}

run_interactive_wizard() {
  header "Agentec Cleanup — Asistente de limpieza"
  echo ""
  info "Este asistente te guiará para configurar la limpieza del stack."
  info "Al final se mostrará un resumen y podrás confirmar antes de borrar cualquier cosa."
  echo ""

  # ── 1. Artifacts ─────────────────────────────────────────────────────────
  echo -e "${BOLD}── 1. Artifacts (JSONs de herramientas, screenshots)${NC}"
  echo "   Los artifacts contienen resultados de herramientas Graph/Power BI/Mail."
  echo "   Pueden incluir datos sensibles (correos, calendarios, archivos)."
  echo ""
  if prompt_yn "¿Limpiar artifacts?" "s"; then
    ARTIFACTS_DAYS=$(prompt_int "¿Borrar artifacts con más de cuántos días de antigüedad?" 7)
    echo ""
    echo "   Tipos de archivo a borrar:"
    echo "   - JSONs de herramientas (graph-mail-*, graph-powerbi-*, etc.)"
    echo "   - Screenshots de login (.png) — pueden contener imágenes de pantallas de autenticación"
    echo "   - PDFs descargados temporalmente"
  else
    ARTIFACTS_DAYS=999999  # No borrar
    info "Artifacts: omitidos."
  fi
  echo ""

  # ── 2. Logs del stack ────────────────────────────────────────────────────
  echo -e "${BOLD}── 2. Logs del stack${NC}"
  echo "   Archivos .log del directorio logs/ del stack (bootstrap, healthcheck, etc.)."
  echo ""
  if prompt_yn "¿Limpiar logs del stack?" "n"; then
    LOGS_DAYS=$(prompt_int "¿Borrar logs con más de cuántos días de antigüedad?" 30)
  else
    LOGS_DAYS=999999
    info "Logs del stack: omitidos."
  fi
  echo ""

  # ── 3. Logs y sesiones de OpenClaw ───────────────────────────────────────
  echo -e "${BOLD}── 3. Logs y canvas de OpenClaw (~/.openclaw/)${NC}"
  echo "   Logs internos de OpenClaw y datos de canvas (sesiones de conversación con el agente)."
  echo ""
  if prompt_yn "¿Limpiar logs y canvas de OpenClaw?" "n"; then
    OPENCLAW_LOGS_DAYS=$(prompt_int "¿Borrar con más de cuántos días de antigüedad?" 14)
  else
    OPENCLAW_LOGS_DAYS=999999
    info "Logs OpenClaw: omitidos."
  fi
  echo ""

  # ── 4. Sesiones y cookies del navegador web ──────────────────────────────
  echo -e "${BOLD}── 4. Sesiones y cookies del navegador web${NC}"
  echo "   Incluye:"
  echo "   - ~/.openclaw/devices/pending.json  (dispositivos en espera de auth)"
  echo "   - /tmp/playwright-*/                (datos temporales de Playwright/Chromium)"
  echo "   - ~/.openclaw/tasks/runs.sqlite     (historial de ejecuciones — solo si lo pides)"
  echo ""
  warn "Atención: borrar pending.json requiere volver a hacer login en los dispositivos emparejados."
  echo ""
  if prompt_yn "¿Limpiar sesiones y cookies de navegador?" "n"; then
    DO_BROWSER_SESSIONS=1
    echo ""
    if prompt_yn "  ¿También borrar el historial de ejecuciones (runs.sqlite)?" "n"; then
      DO_TASKS_DB=1
    else
      DO_TASKS_DB=0
    fi
  else
    DO_BROWSER_SESSIONS=0
    DO_TASKS_DB=0
    info "Sesiones de navegador: omitidas."
  fi
  echo ""

  # ── 5. Tokens de auth pendientes ─────────────────────────────────────────
  echo -e "${BOLD}── 5. Tokens de autenticación pendientes${NC}"
  echo "   Borra tokens OAuth con estado 'pending' o 'poll' (flujos de login que nunca se completaron)."
  echo "   Los tokens de sesión activos (owner.json) NO se tocan."
  echo ""
  if prompt_yn "¿Limpiar tokens de auth pendientes/expirados?" "n"; then
    DO_TOKENS_PENDING=1
  else
    info "Tokens pendientes: omitidos."
  fi
  echo ""

  # ── 6. Docker ─────────────────────────────────────────────────────────────
  echo -e "${BOLD}── 6. Docker${NC}"
  if command -v docker &>/dev/null; then
    echo "   Espacio actual en Docker:"
    docker system df 2>/dev/null | sed 's/^/   /'
    echo ""
    echo "   Opciones:"
    echo "   a) Limpiar build cache y imágenes dangling (conserva 2 GB de cache)"
    echo "   b) Limpieza total — TODAS las imágenes no usadas + volúmenes huérfanos"
    echo "   c) No limpiar Docker"
    echo ""
    ask "¿Qué hacer con Docker? [a/b/c, default: c] "
    read -r -p "  → " docker_choice
    docker_choice="${docker_choice:-c}"
    case "${docker_choice,,}" in
      a) DO_DOCKER=1 ;;
      b) DO_DOCKER_ALL=1
         warn "⚠ La opción b borrará TODAS las imágenes no activas. Asegúrate de que no hay otros proyectos Docker." ;;
      *) info "Docker: omitido." ;;
    esac
  else
    info "Docker no encontrado — omitiendo."
  fi
  echo ""

  # ── 7. Dry-run o real ────────────────────────────────────────────────────
  echo -e "${BOLD}── 7. Modo de ejecución${NC}"
  echo ""
  if prompt_yn "¿Primero hacer un dry-run (ver qué se borraría sin borrar nada)?" "s"; then
    DRY_RUN=1
    info "Modo DRY-RUN activado. Nada se borrará hasta que lo confirmes."
  else
    DRY_RUN=0
  fi
  echo ""

  # ── Resumen de configuración ──────────────────────────────────────────────
  header "Resumen de configuración"
  echo ""
  [[ "$ARTIFACTS_DAYS" -lt 999999 ]] && info "Artifacts:         borrar si >$ARTIFACTS_DAYS días" || info "Artifacts:         omitir"
  [[ "$LOGS_DAYS" -lt 999999 ]]      && info "Logs stack:        borrar si >$LOGS_DAYS días"      || info "Logs stack:        omitir"
  [[ "$OPENCLAW_LOGS_DAYS" -lt 999999 ]] && info "Logs OpenClaw:     borrar si >$OPENCLAW_LOGS_DAYS días" || info "Logs OpenClaw:     omitir"
  [[ "$DO_BROWSER_SESSIONS" -eq 1 ]] && info "Sesiones browser:  SÍ" || info "Sesiones browser:  omitir"
  [[ "$DO_TOKENS_PENDING" -eq 1 ]]   && info "Tokens pendientes: SÍ" || info "Tokens pendientes: omitir"
  [[ "$DO_DOCKER_ALL" -eq 1 ]]       && warn "Docker:            LIMPIEZA TOTAL" \
  || { [[ "$DO_DOCKER" -eq 1 ]] && info "Docker:            build cache + dangling" || info "Docker:            omitir"; }
  [[ "$DRY_RUN" -eq 1 ]] && warn "Modo:              DRY-RUN (solo mostrar)" || warn "Modo:              REAL (borrará archivos)"
  echo ""

  if ! prompt_yn "¿Continuar con esta configuración?" "s"; then
    info "Cancelado por el usuario."
    exit 0
  fi
  echo ""
}

[[ "$INTERACTIVE" -eq 1 ]] && run_interactive_wizard

# ─── rutas base ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(dirname "$SCRIPT_DIR")"

# Soportar instalación local (dev) o producción (~/agentec)
if [[ -d "$STACK_DIR/../artifacts" ]]; then
  ARTIFACTS_DIR="$(realpath "$STACK_DIR/../artifacts")"
elif [[ -d "$STACK_DIR/artifacts" ]]; then
  ARTIFACTS_DIR="$STACK_DIR/artifacts"
else
  ARTIFACTS_DIR=""
fi

if [[ -d "$STACK_DIR/../logs" ]]; then
  LOGS_DIR="$(realpath "$STACK_DIR/../logs")"
elif [[ -d "$STACK_DIR/logs" ]]; then
  LOGS_DIR="$STACK_DIR/logs"
else
  LOGS_DIR=""
fi

TOKENS_DIR="${AGENTEC_GRAPH_TOKENS_DIR:-$STACK_DIR/../.agentec-graph-tokens}"
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"

# ─── contadores ──────────────────────────────────────────────────────────────
TOTAL_FILES_DELETED=0
TOTAL_BYTES_FREED=0

delete_old_files() {
  local dir="$1" days="$2" pattern="${3:-*}" label="$4"
  [[ ! -d "$dir" ]] && warn "$label: directorio no encontrado ($dir)" && return
  local count=0 bytes=0
  while IFS= read -r -d '' f; do
    size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
    if [[ "$DRY_RUN" -eq 1 ]]; then
      dry "$label: borraría $(basename "$f") ($(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B"))"
    else
      rm -f "$f"
      deleted "$label: $(basename "$f") ($(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B"))"
    fi
    count=$((count + 1))
    bytes=$((bytes + size))
  done < <(find "$dir" -maxdepth 1 -name "$pattern" -type f -mtime +"$days" -print0 2>/dev/null)
  if [[ "$count" -gt 0 ]]; then
    info "$label: $count archivo(s) → $(numfmt --to=iec "$bytes" 2>/dev/null || echo "${bytes}B") liberados"
    TOTAL_FILES_DELETED=$((TOTAL_FILES_DELETED + count))
    TOTAL_BYTES_FREED=$((TOTAL_BYTES_FREED + bytes))
  else
    success "$label: sin archivos para limpiar (>$days días)"
  fi
}

# ─── 1. Artifacts ─────────────────────────────────────────────────────────────
echo ""
info "=== ARTIFACTS (>${ARTIFACTS_DAYS} días) ==="
if [[ -n "$ARTIFACTS_DIR" ]]; then
  # JSONs de herramientas (potencialmente con datos sensibles)
  delete_old_files "$ARTIFACTS_DIR" "$ARTIFACTS_DAYS" "*.json" "artifacts/json"
  # Screenshots de login (pueden contener información visual de cuentas)
  delete_old_files "$ARTIFACTS_DIR" "$ARTIFACTS_DAYS" "*.png"  "artifacts/png"
  # PDFs descargados temporalmente
  delete_old_files "$ARTIFACTS_DIR" "$ARTIFACTS_DAYS" "*.pdf"  "artifacts/pdf"
else
  warn "Directorio de artifacts no encontrado — saltando"
fi

# ─── 2. Logs ─────────────────────────────────────────────────────────────────
echo ""
info "=== LOGS (>${LOGS_DAYS} días) ==="
if [[ -n "$LOGS_DIR" ]]; then
  delete_old_files "$LOGS_DIR" "$LOGS_DAYS" "*.log" "logs"
  delete_old_files "$LOGS_DIR" "$LOGS_DAYS" "*.log.*" "logs/rotados"
else
  warn "Directorio de logs no encontrado — saltando"
fi

# ─── 3. Logs internos de OpenClaw ─────────────────────────────────────────────
echo ""
info "=== OPENCLAW LOGS (>${OPENCLAW_LOGS_DAYS} días) ==="
if [[ -d "$OPENCLAW_HOME/logs" ]]; then
  delete_old_files "$OPENCLAW_HOME/logs" "$OPENCLAW_LOGS_DAYS" "*.log" "openclaw/logs"
else
  warn "~/.openclaw/logs no encontrado — saltando"
fi

# Agents canvas / sesiones de agente (datos de conversación)
if [[ -d "$OPENCLAW_HOME/canvas" ]]; then
  delete_old_files "$OPENCLAW_HOME/canvas" "$OPENCLAW_LOGS_DAYS" "*.json" "openclaw/canvas"
fi

# ─── 4. Tokens pendientes (auth expirada) ─────────────────────────────────────
if [[ "$DO_TOKENS_PENDING" -eq 1 || "$DO_ALL" -eq 1 ]]; then
  echo ""
  info "=== TOKENS PENDING (auth flows expirados) ==="
  if [[ -d "$TOKENS_DIR" ]]; then
    while IFS= read -r -d '' f; do
      # Solo borrar si contiene "pending" o "poll" en el nombre o contenido
      if basename "$f" | grep -qiE "pending|poll|tmp"; then
        size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
        if [[ "$DRY_RUN" -eq 1 ]]; then
          dry "tokens: borraría $(basename "$f")"
        else
          rm -f "$f"
          deleted "tokens: $(basename "$f")"
        fi
        TOTAL_FILES_DELETED=$((TOTAL_FILES_DELETED + 1))
        TOTAL_BYTES_FREED=$((TOTAL_BYTES_FREED + size))
      fi
    done < <(find "$TOKENS_DIR" -name "*.json" -print0 2>/dev/null)
    success "tokens: scan completado"
  else
    warn "Directorio de tokens no encontrado ($TOKENS_DIR)"
  fi
fi

# ─── 5. Sesiones y cookies del navegador web ─────────────────────────────────
if [[ "$DO_BROWSER_SESSIONS" -eq 1 || "$DO_ALL" -eq 1 ]]; then
  echo ""
  info "=== SESIONES Y COOKIES DEL NAVEGADOR WEB ==="

  # 5a. Dispositivos pendientes de auth en OpenClaw
  PENDING_DEVICE="$OPENCLAW_HOME/devices/pending.json"
  if [[ -f "$PENDING_DEVICE" ]]; then
    size=$(stat -c%s "$PENDING_DEVICE" 2>/dev/null || stat -f%z "$PENDING_DEVICE" 2>/dev/null || echo 0)
    content=$(cat "$PENDING_DEVICE" 2>/dev/null || echo "")
    if [[ "$content" == "{}" || -z "$content" ]]; then
      success "browser/devices/pending: ya está vacío"
    else
      if [[ "$DRY_RUN" -eq 1 ]]; then
        dry "browser/devices/pending: borraría pending.json (dispositivos esperando auth)"
      else
        echo "{}" > "$PENDING_DEVICE"
        deleted "browser/devices/pending: vaciado pending.json"
      fi
      TOTAL_FILES_DELETED=$((TOTAL_FILES_DELETED + 1))
      TOTAL_BYTES_FREED=$((TOTAL_BYTES_FREED + size))
    fi
  else
    success "browser/devices/pending: no encontrado — omitiendo"
  fi

  # 5b. Directorios temporales de Playwright/Chromium en /tmp
  while IFS= read -r -d '' tmpdir; do
    size=0
    # sumar tamaño del directorio
    size=$(du -sb "$tmpdir" 2>/dev/null | cut -f1 || echo 0)
    if [[ "$DRY_RUN" -eq 1 ]]; then
      dry "browser/tmp: borraría $tmpdir ($(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B"))"
    else
      rm -rf "$tmpdir"
      deleted "browser/tmp: eliminado $(basename "$tmpdir") ($(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B"))"
    fi
    TOTAL_FILES_DELETED=$((TOTAL_FILES_DELETED + 1))
    TOTAL_BYTES_FREED=$((TOTAL_BYTES_FREED + size))
  done < <(find /tmp -maxdepth 2 -type d \( -name "playwright*" -o -name "chromium*" -o -name "pw-*" \) -print0 2>/dev/null)
  success "browser/tmp: scan completado"

  # 5c. SQLite de historial de ejecuciones (solo si el usuario lo pidió en el wizard)
  if [[ "${DO_TASKS_DB:-0}" -eq 1 ]]; then
    TASKS_DB="$OPENCLAW_HOME/tasks/runs.sqlite"
    if [[ -f "$TASKS_DB" ]]; then
      size=$(stat -c%s "$TASKS_DB" 2>/dev/null || stat -f%z "$TASKS_DB" 2>/dev/null || echo 0)
      if [[ "$DRY_RUN" -eq 1 ]]; then
        dry "browser/tasks-db: borraría runs.sqlite ($(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B"))"
      else
        rm -f "$TASKS_DB"
        deleted "browser/tasks-db: runs.sqlite eliminado"
      fi
      TOTAL_FILES_DELETED=$((TOTAL_FILES_DELETED + 1))
      TOTAL_BYTES_FREED=$((TOTAL_BYTES_FREED + size))
    else
      success "browser/tasks-db: no encontrado"
    fi
  fi
fi

# ─── 6. Docker ────────────────────────────────────────────────────────────────
if [[ "$DO_DOCKER" -eq 1 || "$DO_DOCKER_ALL" -eq 1 ]]; then
  echo ""
  info "=== DOCKER ==="
  if ! command -v docker &>/dev/null; then
    warn "Docker no encontrado — saltando limpieza Docker"
  else
    if [[ "$DRY_RUN" -eq 1 ]]; then
      dry "Docker: mostrando espacio (no se limpiará nada)"
      docker system df
    else
      echo ""
      info "Docker build cache y imágenes dangling..."
      docker image prune -f
      docker builder prune -f --keep-storage 2GB
      if [[ "$DO_DOCKER_ALL" -eq 1 ]]; then
        warn "⚠ --docker-all: borrando TODAS las imágenes no usadas y volúmenes huérfanos"
        docker system prune -f --volumes
      fi
      success "Docker: limpieza completada"
    fi
  fi
fi

# ─── Resumen ─────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
if [[ "$DRY_RUN" -eq 1 ]]; then
  warn "MODO DRY-RUN — nada fue borrado"
  info "Se borrarían: ${TOTAL_FILES_DELETED} archivo(s) ($(numfmt --to=iec "$TOTAL_BYTES_FREED" 2>/dev/null || echo "${TOTAL_BYTES_FREED}B"))"
else
  success "Limpieza completada"
  info "Archivos borrados: ${TOTAL_FILES_DELETED}"
  info "Espacio liberado:  $(numfmt --to=iec "$TOTAL_BYTES_FREED" 2>/dev/null || echo "${TOTAL_BYTES_FREED}B")"
fi
echo "─────────────────────────────────────────"
