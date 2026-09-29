#!/usr/bin/env bash
# =============================================================================
# ~/.bashrc — GENESIS/HX mobile runtime
# Android 16 / Termux / Debian PRoot / ARM64
#
# Design:
#   - llama.cpp is the only inference backend
#   - 8 logical HX lanes / 1 physical inference worker
#   - conservative memory/thermal profile
#   - Python / Homebrew / NVM available locally
#   - SSH management endpoint: port 2222
#   - no automatic SSH-agent spawning
#   - no expensive diagnostics on every shell startup
# =============================================================================

# ---------------------------------------------------------------------------
# Interactive shell guard
# ---------------------------------------------------------------------------

case $- in
    *i*) ;;
    *) return ;;
esac

# ---------------------------------------------------------------------------
# Basic shell behavior
# ---------------------------------------------------------------------------

export SHELL="${SHELL:-/bin/bash}"
export EDITOR="${EDITOR:-nano}"
export VISUAL="${VISUAL:-$EDITOR}"

export HISTCONTROL="ignoreboth:erasedups"
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTTIMEFORMAT='%F %T '

shopt -s histappend 2>/dev/null || true
shopt -s checkwinsize 2>/dev/null || true

# ---------------------------------------------------------------------------
# Canonical AI filesystem
# ---------------------------------------------------------------------------

export AI_HOME="$HOME/.ai"
export AI_STATE_DIR="$AI_HOME/state"
export AI_FILE_ROOT="$AI_HOME/files"
export AI_MODEL_DIR="$AI_HOME/models"

# Source/controller tree is separate from runtime state.
export AI_PROJECT_ROOT="$HOME/_"
export AI_BIN="$AI_PROJECT_ROOT/ai.sh"

mkdir -p \
    "$AI_HOME" \
    "$AI_STATE_DIR"/{db,objects,run,sessions,locks,realtime,logs} \
    "$AI_FILE_ROOT" \
    "$AI_MODEL_DIR" \
    2>/dev/null || true

# ---------------------------------------------------------------------------
# Android / PRoot stability
# ---------------------------------------------------------------------------

export PROOT_NO_SECCOMP="${PROOT_NO_SECCOMP:-1}"
export PROOT_TMP_DIR="${PROOT_TMP_DIR:-$HOME/.cache/proot}"

mkdir -p "$PROOT_TMP_DIR" 2>/dev/null || true

# Do not create arbitrary temporary files in shared Android storage.
export TMPDIR="${TMPDIR:-$HOME/.cache/tmp}"
mkdir -p "$TMPDIR" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Homebrew
# ---------------------------------------------------------------------------

if [[ -d "$HOME/.linuxbrew" ]]; then
    eval "$("$HOME/.linuxbrew/bin/brew" shellenv 2>/dev/null)" || true
elif [[ -d "/home/linuxbrew/.linuxbrew" ]]; then
    eval "$("/home/linuxbrew/.linuxbrew/bin/brew" shellenv 2>/dev/null)" || true
fi

# brew.sh compatibility if the user maintains one.
if [[ -f "$HOME/.brew.sh" ]]; then
    # shellcheck disable=SC1090
    source "$HOME/.brew.sh"
elif [[ -f "$HOME/brew.sh" ]]; then
    # shellcheck disable=SC1090
    source "$HOME/brew.sh"
fi

# ---------------------------------------------------------------------------
# NVM
# ---------------------------------------------------------------------------

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    # shellcheck disable=SC1090
    source "$NVM_DIR/nvm.sh"
fi

# Load bash completion only when it exists.
if [[ -s "$NVM_DIR/bash_completion" ]]; then
    # shellcheck disable=SC1090
    source "$NVM_DIR/bash_completion"
fi

# ---------------------------------------------------------------------------
# Python
# ---------------------------------------------------------------------------
#
# Do NOT automatically activate the Python venv.
# The AI controller does not need Python activation merely to run llama.cpp.
#
# Use:
#     ai-python
#
# when Python tooling is actually required.
# ---------------------------------------------------------------------------

ai-python() {
    local venv="$HOME/.env.local/bin/activate"

    if [[ ! -f "$venv" ]]; then
        printf '[ai] Python venv missing: %s\n' "$venv" >&2
        return 1
    fi

    # shellcheck disable=SC1090
    source "$venv"
    printf '[ai] Python: '
    python3 --version 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# llama.cpp
# ---------------------------------------------------------------------------

if [[ -x "$HOME/.local/bin/llama" ]]; then
    export LLAMA_CLI="$HOME/.local/bin/llama"
elif [[ -x "/home/linuxbrew/.linuxbrew/bin/llama" ]]; then
    export LLAMA_CLI="/home/linuxbrew/.linuxbrew/bin/llama"
elif command -v llama >/dev/null 2>&1; then
    export LLAMA_CLI="$(command -v llama)"
elif command -v llama-cli >/dev/null 2>&1; then
    export LLAMA_CLI="$(command -v llama-cli)"
fi

# ---------------------------------------------------------------------------
# Model selection
# ---------------------------------------------------------------------------

export AI_MODEL_PATH="${AI_MODEL_PATH:-$AI_MODEL_DIR/qwen2.5-coder-3b-instruct-q4_k_m.gguf}"

export AI_FALLBACK_MODEL_PATH="${AI_FALLBACK_MODEL_PATH:-$AI_MODEL_DIR/qwen2.5-1.5b-instruct-q4_k_m.gguf}"

# ---------------------------------------------------------------------------
# llama.cpp MOBILE-STABLE profile
# ---------------------------------------------------------------------------
#
# IMPORTANT:
#
# 8 logical HX lanes != 8 simultaneous llama processes.
#
# The phone gets ONE inference process at a time.
#
# Context and batch are intentionally conservative because Android memory
# pressure can terminate the terminal/process rather than merely slowing it.
# ---------------------------------------------------------------------------

export AI_CTX="${AI_CTX:-2048}"

export AI_BATCH="${AI_BATCH:-128}"
export AI_UBATCH="${AI_UBATCH:-64}"

export AI_THREADS="${AI_THREADS:-4}"
export AI_THREADS_BATCH="${AI_THREADS_BATCH:-4}"

export AI_PREDICT="${AI_PREDICT:-192}"

export AI_TEMP="${AI_TEMP:-0.65}"
export AI_TOP_K="${AI_TOP_K:-40}"
export AI_TOP_P="${AI_TOP_P:-0.95}"
export AI_REPEAT="${AI_REPEAT:-1.10}"

# CPU-only by design unless ai.sh explicitly overrides it.
export AI_GPU_LAYERS="${AI_GPU_LAYERS:-0}"

# Do not mlock a ~2 GB model into scarce Android RAM.
export AI_MLOCK="${AI_MLOCK:-0}"

# ---------------------------------------------------------------------------
# HX orchestration
# ---------------------------------------------------------------------------

export GENESIS="${GENESIS:-2PI/8}"
export MOVEMENT_ID="${MOVEMENT_ID:-2244-1}"

# Eight logical roles.
export AI_VIEWS="${AI_VIEWS:-8}"

# One physical llama worker.
export AI_CONCURRENCY="${AI_CONCURRENCY:-1}"

# Avoid recursive inference explosions.
export AI_DEPTH="${AI_DEPTH:-1}"

# Synthesis is opt-in because it means another inference pass.
export AI_SYNTHESIS="${AI_SYNTHESIS:-0}"

# ---------------------------------------------------------------------------
# Prompt / memory limits
# ---------------------------------------------------------------------------

export AI_PROMPT_BYTES="${AI_PROMPT_BYTES:-5500}"
export AI_REALTIME_MAX_BYTES="${AI_REALTIME_MAX_BYTES:-1200}"

export AI_RECALL_TOP="${AI_RECALL_TOP:-4}"
export AI_MAX_FILE_BYTES="${AI_MAX_FILE_BYTES:-262144}"
export AI_CHUNK_BYTES="${AI_CHUNK_BYTES:-4096}"

# ---------------------------------------------------------------------------
# Storage protection
# ---------------------------------------------------------------------------

# Never silently scan/hydrate the whole workspace on every prompt.
export AI_AUTO_REINDEX="${AI_AUTO_REINDEX:-0}"

# Review explicitly.
export AI_AUTO_REVIEW="${AI_AUTO_REVIEW:-0}"

# Keep enough headroom for Android/PRoot.
export AI_MEM_RESERVE_MB="${AI_MEM_RESERVE_MB:-2200}"

# Give inference enough time without encouraging concurrent workers.
export AI_TIMEOUT="${AI_TIMEOUT:-600}"

# ---------------------------------------------------------------------------
# Realtime state
# ---------------------------------------------------------------------------

export AI_REALTIME="${AI_REALTIME:-1}"
export AI_REALTIME_TIMEOUT="${AI_REALTIME_TIMEOUT:-12}"

export AI_REALTIME_DIR="${AI_REALTIME_DIR:-$AI_STATE_DIR/realtime}"

mkdir -p "$AI_REALTIME_DIR" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Platform marker
# ---------------------------------------------------------------------------

export AI_PLATFORM="${AI_PLATFORM:-android16-termux-proot-debian-arm64}"

# ---------------------------------------------------------------------------
# SSH MANAGEMENT
# ---------------------------------------------------------------------------
#
# SSH is management/remote-control infrastructure.
# It is NOT placed in the critical llama inference dependency chain.
#
# Port 2222 is intentional to avoid privileged port 22.
# ---------------------------------------------------------------------------

export AI_SSH_HOST="${AI_SSH_HOST:-127.0.0.1}"
export AI_SSH_PORT="${AI_SSH_PORT:-2222}"

# Optional remote-management environment marker.
export AI_SSH_RUNTIME="${AI_SSH_RUNTIME:-1}"

ai-ssh-status() {
    if command -v sshd >/dev/null 2>&1; then
        printf '[ssh] sshd: available\n'
    else
        printf '[ssh] sshd: NOT installed\n' >&2
        return 1
    fi

    printf '[ssh] configured port: %s\n' "$AI_SSH_PORT"

    if command -v ss >/dev/null 2>&1; then
        ss -ltn 2>/dev/null |
            awk -v p=":$AI_SSH_PORT" '$4 ~ p"$" {print "[ssh] LISTEN " $4}'
    elif command -v netstat >/dev/null 2>&1; then
        netstat -ltn 2>/dev/null |
            awk -v p=":""$AI_SSH_PORT" '$4 ~ p"$" {print "[ssh] LISTEN " $4}'
    fi
}

ai-ssh-start() {
    command -v sshd >/dev/null 2>&1 || {
        printf '[ssh] sshd not installed\n' >&2
        return 1
    }

    mkdir -p "$HOME/.ssh" 2>/dev/null || true
    chmod 700 "$HOME/.ssh" 2>/dev/null || true

    # Termux/OpenSSH commonly uses this location.
    local cfg="$HOME/.ssh/sshd_config"

    if [[ ! -f "$cfg" ]]; then
        cat >"$cfg" <<EOF
Port 2222
ListenAddress 127.0.0.1
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
AllowTcpForwarding yes
X11Forwarding no
PrintMotd no
EOF
        chmod 600 "$cfg"
    fi

    sshd -t -f "$cfg" || {
        printf '[ssh] invalid configuration: %s\n' "$cfg" >&2
        return 1
    }

    sshd -f "$cfg"

    printf '[ssh] sshd started on 127.0.0.1:%s\n' "$AI_SSH_PORT"
}

ai-ssh-stop() {
    pkill -x sshd 2>/dev/null || true
    printf '[ssh] sshd stop requested\n'
}

# ---------------------------------------------------------------------------
# SSH agent
# ---------------------------------------------------------------------------
#
# Do not run "eval ssh-agent" on every shell.
# Start it explicitly when needed.
# ---------------------------------------------------------------------------

ai-agent() {
    if [[ -n "${SSH_AUTH_SOCK:-}" ]] &&
       [[ -S "$SSH_AUTH_SOCK" ]]; then
        printf '[ssh-agent] already available: %s\n' "$SSH_AUTH_SOCK"
        return 0
    fi

    if ! command -v ssh-agent >/dev/null 2>&1; then
        printf '[ssh-agent] ssh-agent unavailable\n' >&2
        return 1
    fi

    eval "$(ssh-agent -s)"
    printf '[ssh-agent] started\n'
}

# ---------------------------------------------------------------------------
# AI controller
# ---------------------------------------------------------------------------

if [[ -x "$AI_BIN" ]]; then
    export PATH="$AI_PROJECT_ROOT:$HOME/.local/bin:$PATH"

    ai() {
        "$AI_BIN" "$@"
    }

    cli-regex-string() {
        "$AI_BIN" "$@"
    }

    export -f ai 2>/dev/null || true
    export -f cli-regex-string 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Convenience commands
# ---------------------------------------------------------------------------

ai-status() {
    "$AI_BIN" status
}

ai-doctor() {
    "$AI_BIN" doctor
}

ai-models() {
    "$AI_BIN" models
}

ai-config() {
    "$AI_BIN" config
}

ai-chat() {
    "$AI_BIN" chat "$@"
}

ai-hash() {
    "$AI_BIN" hash "$@"
}

ai-env() {
    printf '%s\n' \
        "AI_READY=${AI_READY:-0}" \
        "AI_PLATFORM=$AI_PLATFORM" \
        "AI_HOME=$AI_HOME" \
        "AI_STATE_DIR=$AI_STATE_DIR" \
        "AI_PROJECT_ROOT=$AI_PROJECT_ROOT" \
        "AI_BIN=$AI_BIN" \
        "LLAMA_CLI=${LLAMA_CLI:-missing}" \
        "AI_MODEL_PATH=$AI_MODEL_PATH" \
        "AI_FALLBACK_MODEL_PATH=$AI_FALLBACK_MODEL_PATH" \
        "AI_CTX=$AI_CTX" \
        "AI_BATCH=$AI_BATCH" \
        "AI_UBATCH=$AI_UBATCH" \
        "AI_THREADS=$AI_THREADS" \
        "AI_THREADS_BATCH=$AI_THREADS_BATCH" \
        "AI_PREDICT=$AI_PREDICT" \
        "AI_VIEWS=$AI_VIEWS" \
        "AI_CONCURRENCY=$AI_CONCURRENCY" \
        "AI_DEPTH=$AI_DEPTH" \
        "AI_SYNTHESIS=$AI_SYNTHESIS" \
        "AI_PROMPT_BYTES=$AI_PROMPT_BYTES" \
        "AI_MEM_RESERVE_MB=$AI_MEM_RESERVE_MB" \
        "AI_AUTO_REINDEX=$AI_AUTO_REINDEX" \
        "AI_REALTIME=$AI_REALTIME" \
        "AI_SSH_PORT=$AI_SSH_PORT"
}

# ---------------------------------------------------------------------------
# Memory / hardware observation
# ---------------------------------------------------------------------------

ai-memory() {
    printf '%s\n' '== memory =='

    awk '
        /MemTotal:/     {printf "MemTotal      : %.1f MiB\n",$2/1024}
        /MemAvailable:/ {printf "MemAvailable  : %.1f MiB\n",$2/1024}
        /SwapTotal:/    {printf "SwapTotal     : %.1f MiB\n",$2/1024}
        /SwapFree:/     {printf "SwapFree      : %.1f MiB\n",$2/1024}
    ' /proc/meminfo 2>/dev/null

    printf '\n%s\n' '== load =='
    cat /proc/loadavg 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Full system diagnostic — explicit only
# ---------------------------------------------------------------------------

ai-system() {
    printf '\n== AI ENV ==\n'
    ai-env

    printf '\n== MEMORY ==\n'
    ai-memory

    printf '\n== FILESYSTEM ==\n'
    df -h "$HOME" 2>/dev/null || true

    printf '\n== CPU ==\n'
    nproc 2>/dev/null || true

    printf '\n== LLAMA ==\n'
    if [[ -x "${LLAMA_CLI:-}" ]]; then
        "$LLAMA_CLI" --version 2>&1 | head -n 2
    else
        printf 'llama: missing\n'
    fi

    printf '\n== SSH ==\n'
    ai-ssh-status || true
}

# ---------------------------------------------------------------------------
# Model shortcuts
# ---------------------------------------------------------------------------

ai-model() {
    local model="${1:-}"

    if [[ -z "$model" ]]; then
        printf 'AI_MODEL_PATH=%s\n' "$AI_MODEL_PATH"
        return 0
    fi

    if [[ -f "$model" ]]; then
        export AI_MODEL_PATH="$model"
    elif [[ -f "$AI_MODEL_DIR/$model" ]]; then
        export AI_MODEL_PATH="$AI_MODEL_DIR/$model"
    else
        printf '[ai] model not found: %s\n' "$model" >&2
        return 1
    fi

    printf '[ai] model=%s\n' "$AI_MODEL_PATH"
}

# ---------------------------------------------------------------------------
# Inference modes
# ---------------------------------------------------------------------------

ask() {
    [[ $# -gt 0 ]] || {
        printf 'usage: ask "prompt"\n' >&2
        return 2
    }

    "$AI_BIN" run "$*"
}

think() {
    [[ $# -gt 0 ]] || {
        printf 'usage: think "problem"\n' >&2
        return 2
    }

    AI_VIEWS=8 \
    AI_CONCURRENCY=1 \
    AI_DEPTH=1 \
    "$AI_BIN" run "$*"
}

aifast() {
    [[ $# -gt 0 ]] || {
        printf 'usage: aifast "prompt"\n' >&2
        return 2
    }

    AI_CTX=1536 \
    AI_BATCH=96 \
    AI_UBATCH=48 \
    AI_THREADS=3 \
    AI_THREADS_BATCH=3 \
    AI_PREDICT=128 \
    AI_VIEWS=1 \
    AI_CONCURRENCY=1 \
    AI_SYNTHESIS=0 \
    "$AI_BIN" run "$*"
}

ai8() {
    [[ $# -gt 0 ]] || {
        printf 'usage: ai8 "prompt"\n' >&2
        return 2
    }

    AI_CTX=2048 \
    AI_BATCH=128 \
    AI_UBATCH=64 \
    AI_THREADS=4 \
    AI_PREDICT=192 \
    AI_VIEWS=8 \
    AI_CONCURRENCY=1 \
    AI_DEPTH=1 \
    AI_SYNTHESIS=0 \
    "$AI_BIN" run "$*"
}

# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------

alias gs='git status --short --branch'
alias gl='git log --oneline --decorate -12'
alias gd='git diff'
alias ga='git add'
alias gc='git commit'

# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'

# ---------------------------------------------------------------------------
# AI paths
# ---------------------------------------------------------------------------

alias ai-home='cd "$AI_HOME"'
alias ai-state='cd "$AI_STATE_DIR"'
alias ai-runs='cd "$AI_STATE_DIR/run"'
alias ai-db='cd "$AI_STATE_DIR/db"'
alias ai-cache='cd "$AI_STATE_DIR/objects"'
alias ai-model-dir='cd "$AI_MODEL_DIR"'
alias ai-project='cd "$AI_PROJECT_ROOT"'

# ---------------------------------------------------------------------------
# Prompt
# ---------------------------------------------------------------------------

if [[ -n "${PS1:-}" ]]; then
    PS1='\[\e[38;5;45m\]➜ \[\e[38;5;39m\]\w \[\e[38;5;245m\]$(git branch --show-current 2>/dev/null | sed "s/^/git:(/;s/$/)/")\[\e[0m\] '
fi

# ---------------------------------------------------------------------------
# Readiness
# ---------------------------------------------------------------------------

if [[ -x "$AI_BIN" && -x "${LLAMA_CLI:-/nonexistent}" ]]; then
    export AI_READY=1
else
    export AI_READY=0
fi

# =============================================================================
# End ~/.bashrc
# =============================================================================
