#!/usr/bin/env bash

is_wsl() {
  if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    return 0
  fi
  if grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then
    return 0
  fi
  return 1
}

detect_platform() {
  case "${OSTYPE:-}" in
    linux-gnu*)
      if is_wsl; then
        printf 'wsl'
      else
        printf 'linux'
      fi
      ;;
    darwin*)
      printf 'macos'
      ;;
    msys*|cygwin*|mingw*)
      printf 'windows-bash'
      ;;
    *)
      if uname -s 2>/dev/null | grep -qi linux; then
        if is_wsl; then
          printf 'wsl'
        else
          printf 'linux'
        fi
      else
        printf 'unknown'
      fi
      ;;
  esac
}

resolve_path() {
  local path_value="$1"
  local base_dir="$2"

  if [[ "$path_value" == "~" ]]; then
    path_value="$HOME"
  elif [[ "$path_value" == ~/* ]]; then
    path_value="$HOME/${path_value#~/}"
  fi

  if [[ "$path_value" != /* ]]; then
    path_value="$base_dir/$path_value"
  fi

  printf '%s' "$path_value"
}

normalize_path_var() {
  local var_name="$1"
  local base_dir="$2"
  local default_value="${3:-}"
  local raw_value="${!var_name:-$default_value}"

  if [[ -z "$raw_value" ]]; then
    return 0
  fi

  local normalized
  normalized="$(resolve_path "$raw_value" "$base_dir")"
  export "$var_name=$normalized"
}

ensure_supported_runtime() {
  local platform
  platform="$(detect_platform)"
  case "$platform" in
    linux|macos|wsl)
      return 0
      ;;
    windows-bash)
      echo "[FAIL] Entorno Windows bash no soportado para este stack. Usa WSL2 (Ubuntu) para ejecutar scripts." >&2
      return 1
      ;;
    *)
      echo "[FAIL] Sistema operativo no soportado. Usa Linux, macOS o Windows con WSL2." >&2
      return 1
      ;;
  esac
}

write_openclaw_json() {
  local openclaw_json="$1"
  local model_primary="$2"
  local mcp_url="$3"
  local mcp_auth_token="$4"

  cat > "$openclaw_json" <<EOF
{
  "gateway": {
    "mode": "local"
  },
  "agents": {
    "defaults": {
      "workspace": "~/.openclaw/workspace",
      "model": {
        "primary": "$model_primary"
      }
    }
  },
  "mcp": {
    "servers": {
      "agentec": {
        "url": "$mcp_url",
        "transport": "streamable-http",
        "headers": {
          "Authorization": "Bearer $mcp_auth_token"
        }
      }
    }
  },
  "skills": {
    "load": {
      "extraDirs": ["~/.openclaw/skills"]
    }
  }
}
EOF
}

ensure_openclaw_local_config() {
  local openclaw_config_dir="$1"
  local model_primary="$2"
  local mcp_url="$3"
  local mcp_auth_token="$4"

  local openclaw_json="$openclaw_config_dir/openclaw.json"

  mkdir -p "$openclaw_config_dir" "$openclaw_config_dir/workspace"

  if [[ ! -f "$openclaw_json" ]]; then
    write_openclaw_json "$openclaw_json" "$model_primary" "$mcp_url" "$mcp_auth_token"
    return 0
  fi

  if command -v node >/dev/null 2>&1; then
    if ! node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$openclaw_json" >/dev/null 2>&1; then
      cp "$openclaw_json" "$openclaw_json.invalid.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
      write_openclaw_json "$openclaw_json" "$model_primary" "$mcp_url" "$mcp_auth_token"
      return 0
    fi
  fi

  if ! grep -q '"mode"[[:space:]]*:[[:space:]]*"local"' "$openclaw_json" 2>/dev/null; then
    cp "$openclaw_json" "$openclaw_json.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
    write_openclaw_json "$openclaw_json" "$model_primary" "$mcp_url" "$mcp_auth_token"
  fi
}

# ─── sed portable (Linux usa sed -i; macOS/BSD usa sed -i '') ────────────────
sed_inplace() {
  if [[ "${OSTYPE:-}" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

trim_env_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

strip_matching_quotes() {
  local value="$1"
  if [[ "$value" =~ ^\".*\"$ ]] || [[ "$value" =~ ^\'.*\'$ ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "$value"
}

load_env_file() {
  local env_file="$1"
  [[ -f "$env_file" ]] || return 0

  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    local line="${raw_line%$'\r'}"
    line="$(trim_env_value "$line")"

    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue
    [[ "$line" != *=* ]] && continue

    local key="${line%%=*}"
    local value="${line#*=}"

    key="$(trim_env_value "$key")"
    value="$(trim_env_value "$value")"

    if [[ "$key" == export* ]]; then
      key="$(trim_env_value "${key#export}")"
    fi

    value="$(strip_matching_quotes "$value")"
    export "$key=$value"
  done < "$env_file"
}