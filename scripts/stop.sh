#!/usr/bin/env bash
# stop.sh — Para todos los servicios del stack
# Uso: ./scripts/stop.sh

set -euo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Deteniendo agentec-openclaw-stack..."

cd "$STACK_DIR"
docker compose down

echo "[OK] Stack detenido"
