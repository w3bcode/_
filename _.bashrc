# =============================================================================
# ~/.bashrc — AI Runtime v13.0.0
# Android 16 / Termux / Debian proot / ARM64
# llama.cpp local inference — no Ollama dependency
# =============================================================================

# -----------------------------------------------------------------------------
# Interactive shell guard
# -----------------------------------------------------------------------------

case $- in
    *i*) ;;
      *) return ;;
esac

# -----------------------------------------------------------------------------
# Shell behavior
# -----------------------------------------------------------------------------

export SHELL="${SHELL:-/bin/bash}"
export EDITOR="${EDITOR:-nano}"
export VISUAL="${VISUAL:-$EDITOR}"

export HISTCONTROL="ignoreboth:erasedups"
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTTIMEFORMAT='%F %T '

shopt -s histappend 2>/dev/null
shopt -s checkwinsize 2>/dev/null

# -----------------------------------------------------------------------------
# Android / proot stability
# -----------------------------------------------------------------------------

export PROOT_NO_SECCOMP="${PROOT_NO_SECCOMP:-1}"
export PROOT_TMP_DIR="${PROOT_TMP_DIR:-$HOME/.cache/proot}"

mkdir -p "$PROOT_TMP_DIR" 2>/dev/null

# -----------------------------------------------------------------------------
# Home / project
# -----------------------------------------------------------------------------

export AI_HOME="${AI_HOME:-$HOME/_}"
export AI_STATE_DIR="${AI_STATE_DIR:-$AI_HOME/.ai-state}"

export AI_RUN_DIR="${AI_RUN_DIR:-$AI_STATE_DIR/runs}"
export AI_DB_DIR="${AI_DB_DIR:-$AI_STATE_DIR/db}"
export AI_CACHE_DIR="${AI_CACHE_DIR:-$AI_STATE_DIR/cache}"

mkdir -p \
    "$AI_STATE_DIR" \
    "$AI_RUN_DIR" \
    "$AI_DB_DIR" \
    "$AI_CACHE_DIR" \
    "$AI_HOME/models" \
    2>/dev/null

# -----------------------------------------------------------------------------
# Linuxbrew
# -----------------------------------------------------------------------------

if [[ -d "$HOME/.linuxbrew/bin" ]]; then
    export PATH="$HOME/.linuxbrew/bin:$PATH"
fi

if [[ -d "/home/linuxbrew/.linuxbrew/bin" ]]; then
    export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"
fi

# -----------------------------------------------------------------------------
# llama.cpp
#
# Preferred binary:
#   /home/linuxbrew/.linuxbrew/bin/llama
#
# Fallback:
#   llama-cli
# -----------------------------------------------------------------------------

if [[ -x "/home/linuxbrew/.linuxbrew/bin/llama" ]]; then
    export LLAMA_CLI="/home/linuxbrew/.linuxbrew/bin/llama"
elif command -v llama >/dev/null 2>&1; then
    export LLAMA_CLI="$(command -v llama)"
elif command -v llama-cli >/dev/null 2>&1; then
    export LLAMA_CLI="$(command -v llama-cli)"
fi

# -----------------------------------------------------------------------------
# Model
# -----------------------------------------------------------------------------

export AI_MODEL_PATH="${AI_MODEL_PATH:-$AI_HOME/models/qwen2.5-coder-3b-instruct-q4_k_m.gguf}"

export AI_PRIMARY="${AI_PRIMARY:-qwen2.5-coder-3b-instruct-q4_k_m.gguf}"
export AI_FALLBACK_FILE="${AI_FALLBACK_FILE:-qwen2.5-1.5b-instruct-q4_k_m.gguf}"

# -----------------------------------------------------------------------------
# Hardware
#
# Your current local configuration is CPU-only.
# Keep threads bounded to prevent the controller from consuming the entire
# Android/proot memory budget.
# -----------------------------------------------------------------------------

CPU_THREADS="$(nproc 2>/dev/null || printf '8')"

if [[ "$CPU_THREADS" =~ ^[0-9]+$ ]]; then
    (( CPU_THREADS > 8 )) && CPU_THREADS=8
    (( CPU_THREADS < 1 )) && CPU_THREADS=1
else
    CPU_THREADS=8
fi

export AI_THREADS="${AI_THREADS:-$CPU_THREADS}"

# -----------------------------------------------------------------------------
# llama.cpp inference parameters
# -----------------------------------------------------------------------------

export AI_CTX="${AI_CTX:-4096}"
export AI_BATCH="${AI_BATCH:-256}"
export AI_UBATCH="${AI_UBATCH:-128}"

export AI_PREDICT="${AI_PREDICT:-512}"

export AI_TEMP="${AI_TEMP:-0.65}"
export AI_TOP_P="${AI_TOP_P:-0.90}"
export AI_TOP_K="${AI_TOP_K:-40}"
export AI_REPEAT="${AI_REPEAT:-1.10}"

export AI_TIMEOUT="${AI_TIMEOUT:-180}"

# -----------------------------------------------------------------------------
# v13 reasoning pipeline
# -----------------------------------------------------------------------------

export AI_VIEWS="${AI_VIEWS:-1}"
export AI_SYNTHESIS="${AI_SYNTHESIS:-0}"

export AI_DEPTH="${AI_DEPTH:-8}"
export AI_CONVERGENCE="${AI_CONVERGENCE:-0.985}"

# Optional platform marker used by status/ledger.
export AI_PLATFORM="${AI_PLATFORM:-android16-termux-proot-debian-arm64}"

# -----------------------------------------------------------------------------
# Memory-aware execution
#
# This does not dynamically unload the GGUF. It only prevents pathological
# context/thread settings from being selected before inference.
# -----------------------------------------------------------------------------

ai_memory_guard() {
    local mem_kb avail_kb
    local ctx="$AI_CTX"

    mem_kb="$(
        awk '/MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null
    )"

    avail_kb="$(
        awk '/MemAvailable:/ {print $2; exit}' /proc/meminfo 2>/dev/null
    )"

    [[ "$mem_kb" =~ ^[0-9]+$ ]] || return 0
    [[ "$avail_kb" =~ ^[0-9]+$ ]] || return 0

    # Critical memory: reduce context before launching inference.
    if (( avail_kb < 1200000 )); then
        export AI_CTX=2048
        export AI_BATCH=128
        export AI_UBATCH=64
        export AI_THREADS=4
        export AI_PREDICT=384
        return
    fi

    # Elevated memory pressure.
    if (( avail_kb < 2200000 )); then
        (( ctx > 3072 )) && export AI_CTX=3072
        (( AI_BATCH > 192 )) && export AI_BATCH=192
        (( AI_UBATCH > 96 )) && export AI_UBATCH=96
        (( AI_THREADS > 6 )) && export AI_THREADS=6
    fi
}

ai_memory_guard

# -----------------------------------------------------------------------------
# AI executable
# -----------------------------------------------------------------------------

export AI_BIN="$AI_HOME/ai.sh"

if [[ -x "$AI_BIN" ]]; then
    export PATH="$AI_HOME:$HOME/.local/bin:$PATH"
fi

# -----------------------------------------------------------------------------
# Command aliases / compatibility
# -----------------------------------------------------------------------------

if [[ -f "$AI_BIN" ]]; then

    # Local function wins over stale system aliases.
    ai() {
        "$AI_BIN" "$@"
    }

    # Legacy command retained as an alias to the same controller.
    cli-regex-string() {
        "$AI_BIN" "$@"
    }

    export -f ai 2>/dev/null
    export -f cli-regex-string 2>/dev/null
fi

# -----------------------------------------------------------------------------
# Convenience commands
# -----------------------------------------------------------------------------

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
    "$AI_BIN" chat
}

ai-hash() {
    "$AI_BIN" hash "$@"
}

# -----------------------------------------------------------------------------
# Model shortcuts
# -----------------------------------------------------------------------------

ai-model() {
    local model="${1:-}"

    if [[ -z "$model" ]]; then
        printf 'AI_MODEL_PATH=%s\n' "$AI_MODEL_PATH"
        return 0
    fi

    if [[ -f "$model" ]]; then
        export AI_MODEL_PATH="$model"
    elif [[ -f "$AI_HOME/models/$model" ]]; then
        export AI_MODEL_PATH="$AI_HOME/models/$model"
    else
        printf '[ERR] model not found: %s\n' "$model" >&2
        return 1
    fi

    printf '[AI] model=%s\n' "$AI_MODEL_PATH"
}

# -----------------------------------------------------------------------------
# One-shot high-quality modes
# -----------------------------------------------------------------------------

ai8() {
    "$AI_BIN" "$@" @views=8 @synthesis=1
}

aicoder() {
    "$AI_BIN" "$@" \
        @ctx=4096 \
        @threads="$AI_THREADS" \
        @predict=768 \
        @temp=0.45
}

aifast() {
    "$AI_BIN" "$@" \
        @ctx=2048 \
        @threads=4 \
        @batch=128 \
        @ubatch=64 \
        @predict=384
}

# -----------------------------------------------------------------------------
# Prompt convenience
# -----------------------------------------------------------------------------

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

    "$AI_BIN" run "$*" @views=8 @synthesis=1
}

# -----------------------------------------------------------------------------
# Git helpers
# -----------------------------------------------------------------------------

alias gs='git status --short --branch'
alias gl='git log --oneline --decorate -12'
alias gd='git diff'
alias ga='git add'
alias gc='git commit'

# -----------------------------------------------------------------------------
# Navigation
# -----------------------------------------------------------------------------

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'

# -----------------------------------------------------------------------------
# AI project shortcuts
# -----------------------------------------------------------------------------

alias ai-home='cd "$AI_HOME"'
alias ai-state='cd "$AI_STATE_DIR"'
alias ai-runs='cd "$AI_RUN_DIR"'
alias ai-db='cd "$AI_DB_DIR"'
alias ai-cache='cd "$AI_CACHE_DIR"'
alias ai-model-dir='cd "$AI_HOME/models"'

# -----------------------------------------------------------------------------
# Environment display
# -----------------------------------------------------------------------------

ai-env() {
    printf '%s\n' \
        "AI_HOME=$AI_HOME" \
        "AI_STATE_DIR=$AI_STATE_DIR" \
        "LLAMA_CLI=${LLAMA_CLI:-missing}" \
        "AI_MODEL_PATH=$AI_MODEL_PATH" \
        "AI_PLATFORM=$AI_PLATFORM" \
        "AI_THREADS=$AI_THREADS" \
        "AI_CTX=$AI_CTX" \
        "AI_BATCH=$AI_BATCH" \
        "AI_UBATCH=$AI_UBATCH" \
        "AI_PREDICT=$AI_PREDICT" \
        "AI_TEMP=$AI_TEMP" \
        "AI_VIEWS=$AI_VIEWS" \
        "AI_SYNTHESIS=$AI_SYNTHESIS"
}

# -----------------------------------------------------------------------------
# Prompt
# -----------------------------------------------------------------------------

if [[ -n "${PS1:-}" ]]; then
    PS1='\[\e[38;5;45m\]➜ \[\e[38;5;39m\]\w \[\e[38;5;245m\]$(git branch --show-current 2>/dev/null | sed "s/^/git:(/;s/$/)/")\[\e[0m\] '
fi

# -----------------------------------------------------------------------------
# Final startup check
# -----------------------------------------------------------------------------

if [[ -x "$AI_BIN" && -x "${LLAMA_CLI:-/nonexistent}" ]]; then
    export AI_READY=1
else
    export AI_READY=0
fi

# -----------------------------------------------------------------------------
# End ~/.bashrc v13.0.0
# =============================================================================

source /home/loop/.env.local/bin/activate

eval $(ssh-agent -s)
ssh-add
cd ~

clear
screenfetch
free -h
df -h

echo "Shell setup done."
