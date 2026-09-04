# =============================================================================
# ~/.bashrc — Termux/proot Debian ARM64 local-AI runtime
# Android 16 / unrooted / ~16GB RAM / llama + Ollama bridge
# =============================================================================

# -----------------------------------------------------------------------------
# Interactive shell guard
#
# Runtime variables are initialized below only for interactive shells because
# this file is ~/.bashrc. Non-interactive processes should use an explicit
# environment file if they need the same configuration.
# -----------------------------------------------------------------------------
case $- in
  *i*) ;;
  *) return ;;
esac

# -----------------------------------------------------------------------------
# Shell baseline
# -----------------------------------------------------------------------------
export EDITOR="${EDITOR:-nano}"
export VISUAL="${VISUAL:-$EDITOR}"
export PAGER="${PAGER:-less}"
export LESS="${LESS:--FRX}"

export HISTCONTROL="${HISTCONTROL:-ignoreboth}"
export HISTSIZE="${HISTSIZE:-50000}"
export HISTFILESIZE="${HISTFILESIZE:-100000}"
export HISTTIMEFORMAT="${HISTTIMEFORMAT:-%F %T }"

shopt -s histappend cmdhist lithist checkwinsize 2>/dev/null || true

# -----------------------------------------------------------------------------
# Termux -> Debian proot identity
# -----------------------------------------------------------------------------
export PROOT_NO_SECCOMP="${PROOT_NO_SECCOMP:-1}"
export PROOT_TMPDIR="${PROOT_TMPDIR:-${TMPDIR:-/tmp}}"

# Intentionally user-space:
# no root / sudo / systemd / privileged mounts / GPU device assumptions.
export AI_UNROOTED="${AI_UNROOTED:-1}"
export AI_PLATFORM="${AI_PLATFORM:-android16-termux-proot-debian-arm64}"

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------
export AI_HOME="${AI_HOME:-$HOME/_}"
export AI_SCRIPT="${AI_SCRIPT:-$AI_HOME/ai.sh}"

export AI_STATE_DIR="${AI_STATE_DIR:-$AI_HOME/.ai-state}"
export AI_DB="${AI_DB:-$AI_STATE_DIR/db}"
export AI_OBJECTS="${AI_OBJECTS:-$AI_DB/objects}"
export AI_REFERENCE="${AI_REFERENCE:-$AI_DB/reference}"
export AI_RUN_DIR="${AI_RUN_DIR:-$AI_STATE_DIR/run}"
export AI_LOG_DIR="${AI_LOG_DIR:-$AI_STATE_DIR/logs}"
export AI_CACHE_DIR="${AI_CACHE_DIR:-$AI_STATE_DIR/cache}"

mkdir -p \
  "$AI_HOME" \
  "$AI_STATE_DIR" \
  "$AI_DB" \
  "$AI_OBJECTS" \
  "$AI_REFERENCE" \
  "$AI_RUN_DIR" \
  "$AI_LOG_DIR" \
  "$AI_CACHE_DIR" \
  2>/dev/null || true

# -----------------------------------------------------------------------------
# Linuxbrew / user-local tools
# -----------------------------------------------------------------------------

# Put the likely llama installation locations FIRST.
if [[ -d "/home/linuxbrew/.linuxbrew/bin" ]]; then
  export PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH"
fi

if [[ -d "$HOME/.linuxbrew/bin" ]]; then
  export PATH="$HOME/.linuxbrew/bin:$HOME/.linuxbrew/sbin:$PATH"
fi

export PATH="$AI_HOME/bin:$HOME/bin:$PATH"

# -----------------------------------------------------------------------------
# Python venv
# -----------------------------------------------------------------------------
for VENV in \
  "$HOME/.env.local" \
  "$HOME/.venv" \
  "$AI_HOME/.venv"
do
  if [[ -f "$VENV/bin/activate" ]]; then
    # shellcheck disable=SC1090
    source "$VENV/bin/activate"
    break
  fi
done
unset VENV

# -----------------------------------------------------------------------------
# Node/NVM
# -----------------------------------------------------------------------------
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  # shellcheck disable=SC1090
  source "$NVM_DIR/nvm.sh"
fi

# -----------------------------------------------------------------------------
# llama executable resolver
#
# Priority:
#   1. Explicit LLAMA_BIN if executable
#   2. command -v llama
#   3. Linuxbrew system prefix
#   4. ~/.linuxbrew
#   5. /usr/local/bin
#   6. /usr/bin
#
# This prevents:
#   ai.sh: llama not found: llama
#
# LLAMA_BIN becomes an absolute executable path whenever possible.
# -----------------------------------------------------------------------------

_ai_resolve_llama() {
  local candidate

  # Explicit executable supplied by user/environment.
  if [[ -n "${LLAMA_BIN:-}" ]] &&
     [[ "$LLAMA_BIN" == */* ]] &&
     [[ -x "$LLAMA_BIN" ]]
  then
    printf '%s\n' "$LLAMA_BIN"
    return 0
  fi

  # PATH lookup.
  candidate="$(command -v llama 2>/dev/null || true)"

  if [[ -n "$candidate" ]] && [[ -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  # Known locations.
  for candidate in \
    "/home/linuxbrew/.linuxbrew/bin/llama" \
    "$HOME/.linuxbrew/bin/llama" \
    "/usr/local/bin/llama" \
    "/usr/bin/llama"
  do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

LLAMA_RESOLVED="$(_ai_resolve_llama || true)"

if [[ -n "$LLAMA_RESOLVED" ]]; then
  export LLAMA_BIN="$LLAMA_RESOLVED"
else
  # Keep the canonical Linuxbrew path as the diagnostic target.
  export LLAMA_BIN="${LLAMA_BIN:-/home/linuxbrew/.linuxbrew/bin/llama}"
fi

unset LLAMA_RESOLVED

# -----------------------------------------------------------------------------
# llama runtime defaults
#
# CPU-first is intentional for unrooted Android/proot.
# -----------------------------------------------------------------------------

export LLAMA_HOST="${LLAMA_HOST:-127.0.0.1}"
export LLAMA_PORT="${LLAMA_PORT:-8080}"
export LLAMA_BASE_URL="${LLAMA_BASE_URL:-http://${LLAMA_HOST}:${LLAMA_PORT}}"

export LLAMA_THREADS="${LLAMA_THREADS:-8}"
export LLAMA_CTX_SIZE="${LLAMA_CTX_SIZE:-4096}"

# Current llama.cpp supports --n-gpu-layers / --gpu-layers.
# Zero explicitly requests CPU-only inference.
export LLAMA_GPU_LAYERS="${LLAMA_GPU_LAYERS:-0}"

export LLAMA_BATCH="${LLAMA_BATCH:-256}"
export LLAMA_UBATCH="${LLAMA_UBATCH:-128}"

export LLAMA_TEMP="${LLAMA_TEMP:-0.65}"
export LLAMA_TOP_P="${LLAMA_TOP_P:-0.95}"
export LLAMA_TOP_K="${LLAMA_TOP_K:-40}"
export LLAMA_REPEAT_PENALTY="${LLAMA_REPEAT_PENALTY:-1.10}"

export LLAMA_KEEP_ALIVE="${LLAMA_KEEP_ALIVE:-5m}"

export LLAMA_MODEL="${LLAMA_MODEL:-Qwen/Qwen2.5-Coder-3B-Instruct-GGUF:Q4_K_M}"

# -----------------------------------------------------------------------------
# Controller model aliases
# -----------------------------------------------------------------------------
export AI_MODEL="${AI_MODEL:-$LLAMA_MODEL}"
export AI_CODER="${AI_CODER:-$LLAMA_MODEL}"
export AI_FALLBACK="${AI_FALLBACK:-qwen3:0.6b}"

# -----------------------------------------------------------------------------
# ai.sh controller configuration
# -----------------------------------------------------------------------------
export AI_CTX="${AI_CTX:-$LLAMA_CTX_SIZE}"
export AI_THREADS="${AI_THREADS:-$LLAMA_THREADS}"
export AI_GPU_LAYERS="${AI_GPU_LAYERS:-$LLAMA_GPU_LAYERS}"

export AI_TEMP="${AI_TEMP:-$LLAMA_TEMP}"
export AI_TOP_P="${AI_TOP_P:-$LLAMA_TOP_P}"
export AI_TOP_K="${AI_TOP_K:-$LLAMA_TOP_K}"
export AI_REPEAT_PENALTY="${AI_REPEAT_PENALTY:-$LLAMA_REPEAT_PENALTY}"

export AI_N_PREDICT="${AI_N_PREDICT:-512}"

# 2PI / multiview defaults
export AI_VIEWS="${AI_VIEWS:-1}"
export AI_SYNTHESIS="${AI_SYNTHESIS:-false}"
export AI_PARALLEL="${AI_PARALLEL:-0}"

export AI_TIMEOUT="${AI_TIMEOUT:-600}"
export AI_KEEP_ALIVE="${AI_KEEP_ALIVE:-$LLAMA_KEEP_ALIVE}"
export AI_STREAM="${AI_STREAM:-false}"
export AI_SESSION="${AI_SESSION:-default}"
export AI_MAX_BYTES="${AI_MAX_BYTES:-10485760}"

# Server-backed inference preferred.
export AI_SERVER_AUTOSTART="${AI_SERVER_AUTOSTART:-1}"

# CLI fallback deliberately disabled.
export AI_FALLBACK_CLI="${AI_FALLBACK_CLI:-0}"

# Never eval prompt content.
export AI_NO_EVAL=1

# -----------------------------------------------------------------------------
# Ollama bridge
# -----------------------------------------------------------------------------
export OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
export OLLAMA_KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:-5m}"
export OLLAMA_NUM_PARALLEL="${OLLAMA_NUM_PARALLEL:-1}"
export OLLAMA_MAX_LOADED_MODELS="${OLLAMA_MAX_LOADED_MODELS:-1}"
export OLLAMA_FLASH_ATTENTION="${OLLAMA_FLASH_ATTENTION:-1}"

# -----------------------------------------------------------------------------
# Runtime validation
# -----------------------------------------------------------------------------

ai-llama-path() {
  local p

  p="$(_ai_resolve_llama || true)"

  if [[ -n "$p" ]]; then
    printf '%s\n' "$p"
    return 0
  fi

  printf '%s\n' "$LLAMA_BIN"
  return 1
}

ai-llama-check() {
  local p="${LLAMA_BIN:-}"

  printf '%s\n' '--- llama executable ---'
  printf 'LLAMA_BIN=%s\n' "$p"

  if [[ -x "$p" ]]; then
    printf 'status=OK\n'
    printf 'realpath='
    readlink -f "$p" 2>/dev/null || printf '%s' "$p"
    printf '\n'
    return 0
  fi

  printf 'status=MISSING\n'
  printf '%s\n' 'searched:'
  printf '  PATH -> command -v llama\n'
  printf '  /home/linuxbrew/.linuxbrew/bin/llama\n'
  printf '  ~/.linuxbrew/bin/llama\n'
  printf '  /usr/local/bin/llama\n'
  printf '  /usr/bin/llama\n'

  return 127
}

# -----------------------------------------------------------------------------
# ai.sh controller helpers
# -----------------------------------------------------------------------------

ai_bin() {
  if [[ ! -x "$AI_SCRIPT" ]]; then
    printf 'ai: controller missing: %s\n' "$AI_SCRIPT" >&2
    return 127
  fi

  printf '%s\n' "$AI_SCRIPT"
}

ai() {
  if [[ ! -x "$AI_SCRIPT" ]]; then
    printf 'ai: controller missing: %s\n' "$AI_SCRIPT" >&2
    return 127
  fi

  "$AI_SCRIPT" "$@"
}

ai-status() {
  "$AI_SCRIPT" status "$@"
}

ai-doctor() {
  "$AI_SCRIPT" doctor "$@"
}

ai-repl() {
  "$AI_SCRIPT" repl "$@"
}

ai-parse() {
  "$AI_SCRIPT" parse "$@"
}

ai-rank() {
  "$AI_SCRIPT" rank "$@"
}

ai-index() {
  "$AI_SCRIPT" index "${1:-$AI_HOME}"
}

# -----------------------------------------------------------------------------
# Native llama CLI
#
# ZERO allow-list.
# Everything after llama-cli is passed unchanged to:
#
#   llama cli ...
# -----------------------------------------------------------------------------

llama-cli() {
  local bin="${LLAMA_BIN:-}"

  if [[ ! -x "$bin" ]]; then
    bin="$(_ai_resolve_llama || true)"
  fi

  if [[ -z "$bin" ]] || [[ ! -x "$bin" ]]; then
    printf 'llama-cli: binary not found\n' >&2
    printf 'LLAMA_BIN=%s\n' "${LLAMA_BIN:-<unset>}" >&2
    printf 'Run: ai-llama-check\n' >&2
    return 127
  fi

  "$bin" cli "$@"
}

lc() {
  llama-cli "$@"
}

# -----------------------------------------------------------------------------
# Exact native llama top-level passthrough
# -----------------------------------------------------------------------------

llama-native() {
  local bin="${LLAMA_BIN:-}"

  if [[ ! -x "$bin" ]]; then
    bin="$(_ai_resolve_llama || true)"
  fi

  if [[ -z "$bin" ]] || [[ ! -x "$bin" ]]; then
    printf 'llama-native: binary not found\n' >&2
    printf 'Run: ai-llama-check\n' >&2
    return 127
  fi

  "$bin" "$@"
}

# -----------------------------------------------------------------------------
# Native top-level commands
# -----------------------------------------------------------------------------

llama-help() {
  llama-native --help "$@"
}

llama-version() {
  llama-native --version "$@"
}

llama-licenses() {
  llama-native licenses "$@"
}

llama-update() {
  llama-native update "$@"
}

llama-download() {
  llama-native download "$@"
}

llama-completion() {
  llama-native completion "$@"
}

llama-serve() {
  llama-native serve "$@"
}

# -----------------------------------------------------------------------------
# Model shortcuts
# -----------------------------------------------------------------------------

llama-qwen() {
  llama-cli \
    -hf "$LLAMA_MODEL" \
    --ctx-size "$LLAMA_CTX_SIZE" \
    --threads "$LLAMA_THREADS" \
    --n-gpu-layers "$LLAMA_GPU_LAYERS" \
    --batch-size "$LLAMA_BATCH" \
    --ubatch-size "$LLAMA_UBATCH" \
    --temp "$LLAMA_TEMP" \
    --top-p "$LLAMA_TOP_P" \
    --top-k "$LLAMA_TOP_K" \
    --repeat-penalty "$LLAMA_REPEAT_PENALTY" \
    "$@"
}

llama-coder() {
  llama-qwen "$@"
}

# -----------------------------------------------------------------------------
# Conservative direct CLI smoke test
# -----------------------------------------------------------------------------

llama-smoke() {
  local model="${1:-$LLAMA_MODEL}"
  shift || true

  llama-cli \
    -hf "$model" \
    --single-turn \
    --ctx-size "${LLAMA_SMOKE_CTX:-1024}" \
    --threads "${LLAMA_SMOKE_THREADS:-2}" \
    --n-gpu-layers 0 \
    --temp 0.2 \
    --prompt "${*:-Reply exactly: runtime OK}"
}

# -----------------------------------------------------------------------------
# Persistent llama server lifecycle
# -----------------------------------------------------------------------------

llama-runtime-start() {
  "$AI_SCRIPT" server start "$@"
}

llama-runtime-stop() {
  "$AI_SCRIPT" server stop "$@"
}

llama-runtime-restart() {
  "$AI_SCRIPT" server restart "$@"
}

llama-runtime-status() {
  "$AI_SCRIPT" server status "$@"
}

llama-runtime-logs() {
  "$AI_SCRIPT" server logs "$@"
}

llama-runtime() {
  case "${1:-status}" in
    start)
      shift
      llama-runtime-start "$@"
      ;;
    stop)
      shift
      llama-runtime-stop "$@"
      ;;
    restart)
      shift
      llama-runtime-restart "$@"
      ;;
    status)
      shift
      llama-runtime-status "$@"
      ;;
    logs)
      shift
      llama-runtime-logs "$@"
      ;;
    *)
      printf '%s\n' \
        'usage: llama-runtime {start|stop|restart|status|logs}' >&2
      return 2
      ;;
  esac
}

# -----------------------------------------------------------------------------
# Ollama lifecycle
#
# No systemd/root assumptions.
# -----------------------------------------------------------------------------

ollama-runtime-start() {
  command -v ollama >/dev/null 2>&1 || {
    printf 'ollama: binary not found\n' >&2
    return 127
  }

  if pgrep -f '(^|/)ollama serve' >/dev/null 2>&1; then
    printf 'ollama: already running at %s\n' "$OLLAMA_HOST"
    return 0
  fi

  nohup ollama serve \
    >"$AI_LOG_DIR/ollama.stdout.log" \
    2>"$AI_LOG_DIR/ollama.stderr.log" &

  local pid=$!

  echo "$pid" > "$AI_RUN_DIR/ollama.pid"

  sleep 1

  if kill -0 "$pid" 2>/dev/null; then
    printf 'ollama: started pid=%s host=%s\n' "$pid" "$OLLAMA_HOST"
  else
    printf 'ollama: failed to start\n' >&2
    return 1
  fi
}

ollama-runtime-stop() {
  local pid=""

  if [[ -s "$AI_RUN_DIR/ollama.pid" ]]; then
    pid="$(cat "$AI_RUN_DIR/ollama.pid" 2>/dev/null || true)"
  fi

  if [[ "$pid" =~ ^[0-9]+$ ]] &&
     kill -0 "$pid" 2>/dev/null
  then
    kill "$pid" 2>/dev/null || true
  fi

  rm -f "$AI_RUN_DIR/ollama.pid"

  printf 'ollama: stopped\n'
}

ollama-runtime-status() {
  if command -v ollama >/dev/null 2>&1; then
    printf 'ollama=%s\n' "$(command -v ollama)"
    printf 'host=%s\n' "$OLLAMA_HOST"
    ollama ps 2>&1 || true
  else
    printf 'ollama=missing\n'
  fi
}

ollama-runtime-logs() {
  tail -n "${1:-100}" \
    "$AI_LOG_DIR/ollama.stdout.log" \
    "$AI_LOG_DIR/ollama.stderr.log" \
    2>/dev/null || true
}

# -----------------------------------------------------------------------------
# llama server health
# -----------------------------------------------------------------------------

ai-server-health() {
  if ! command -v curl >/dev/null 2>&1; then
    printf 'curl=missing\n' >&2
    return 127
  fi

  curl \
    --silent \
    --show-error \
    --max-time 5 \
    "$LLAMA_BASE_URL/health"
}

# -----------------------------------------------------------------------------
# RAM diagnostics
# -----------------------------------------------------------------------------

ai-mem() {
  printf '%s\n' '--- memory ---'

  if command -v free >/dev/null 2>&1; then
    free -h
  elif [[ -r /proc/meminfo ]]; then
    awk '
      /MemTotal|MemAvailable|SwapTotal|SwapFree/ {
        print
      }
    ' /proc/meminfo
  fi
}

# -----------------------------------------------------------------------------
# CPU diagnostics
# -----------------------------------------------------------------------------

ai-cpu() {
  printf '%s\n' '--- cpu ---'

  if [[ -r /proc/cpuinfo ]]; then
    awk -F: '
      /processor/ {
        cpu++
      }

      /CPU architecture/ {
        arch=$2
      }

      /Hardware/ {
        hw=$2
      }

      /Model name/ {
        model=$2
      }

      END {
        printf "logical_cpus=%d\n", cpu

        if (arch != "")
          printf "architecture=%s\n", arch

        if (hw != "")
          printf "hardware=%s\n", hw

        if (model != "")
          printf "model=%s\n", model
      }
    ' /proc/cpuinfo
  fi
}

# -----------------------------------------------------------------------------
# Complete AI environment
# -----------------------------------------------------------------------------

ai-env() {
  env |
    grep -E '^(AI_|LLAMA_|OLLAMA_|PROOT_)' |
    sort
}

# -----------------------------------------------------------------------------
# Unified diagnostics
# -----------------------------------------------------------------------------

ai-runtime-doctor() {
  printf '%s\n' '========================================'
  printf '%s\n' ' AI LOCAL RUNTIME DOCTOR'
  printf '%s\n' '========================================'

  printf '\n%s\n' '--- platform ---'
  printf 'AI_PLATFORM=%s\n' "$AI_PLATFORM"
  printf 'AI_UNROOTED=%s\n' "$AI_UNROOTED"
  printf 'HOME=%s\n' "$HOME"
  printf 'AI_HOME=%s\n' "$AI_HOME"

  printf '\n%s\n' '--- llama ---'
  ai-llama-check || true

  if [[ -x "$LLAMA_BIN" ]]; then
    printf '\n%s\n' '--- llama version ---'
    "$LLAMA_BIN" --version 2>&1 || true
  fi

  printf '\n%s\n' '--- server ---'
  printf 'LLAMA_BASE_URL=%s\n' "$LLAMA_BASE_URL"

  if command -v curl >/dev/null 2>&1; then
    if curl \
      --silent \
      --show-error \
      --max-time 3 \
      "$LLAMA_BASE_URL/health" >/dev/null
    then
      printf 'llama-server=READY\n'
    else
      printf 'llama-server=OFFLINE\n'
    fi
  else
    printf 'curl=MISSING\n'
  fi

  printf '\n%s\n' '--- ollama ---'
  if command -v ollama >/dev/null 2>&1; then
    printf 'ollama=%s\n' "$(command -v ollama)"
  else
    printf 'ollama=MISSING\n'
  fi

  printf '\n%s\n' '--- resources ---'
  ai-mem
  ai-cpu

  printf '\n%s\n' '--- controller ---'
  if [[ -x "$AI_SCRIPT" ]]; then
    printf 'ai.sh=READY\n'
    printf 'AI_SCRIPT=%s\n' "$AI_SCRIPT"
  else
    printf 'ai.sh=MISSING\n'
  fi
}

# -----------------------------------------------------------------------------
# Safe aliases
#
# Do NOT create aliases such as:
#   alias ai-status='ai-status'
#
# Those are self-referential and unnecessary.
# -----------------------------------------------------------------------------

alias ll='ls -lah'
alias la='ls -la'

# -----------------------------------------------------------------------------
# Optional llama server autostart
#
# Disabled by default to avoid consuming Android RAM immediately after shell
# creation.
#
# Enable:
#
#   export AI_AUTOSTART_LLAMA=1
#
# -----------------------------------------------------------------------------

if [[ "${AI_AUTOSTART_LLAMA:-0}" == 1 ]]; then
  (
    "$AI_SCRIPT" server start
  ) >"$AI_LOG_DIR/autostart.stdout.log" \
    2>"$AI_LOG_DIR/autostart.stderr.log" &
fi

# -----------------------------------------------------------------------------
# Prompt
# -----------------------------------------------------------------------------

if [[ -z "${PS1:-}" ]]; then
  PS1='\u@\h:\w\$ '
fi
