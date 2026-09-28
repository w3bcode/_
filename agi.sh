#!/usr/bin/env bash
# ==========================================================
# ~/ai.sh — NEXUS Singlefile Orchestrator (WSL1)
# Fully autonomous AI stack: Ollama + tool_generate + recursion
# ==========================================================
set -euo pipefail
IFS=$'\n\t'

# -----------------------------
# ENVIRONMENT & PATHS
# -----------------------------
AI_ROOT="$HOME/_/ai"
LOG_DIR="$AI_ROOT/logs"
mkdir -p "$LOG_DIR"
OLLAMA_URL="${NEXUS_OLLAMA_URL:-http://localhost:11434}"
export PATH="$PATH:$AI_ROOT"

NEXUS_DIR="$HOME/.nexus"
mkdir -p "$NEXUS_DIR"

# -----------------------------
# BASIC LOGGING
# -----------------------------
info() { echo "[NEXUS:INFO] $*"; }
warn() { echo "[NEXUS:WARN] $*"; }
error() { echo "[NEXUS:ERROR] $*" >&2; }

# -----------------------------
# AGENT → MODEL MAPPING
# -----------------------------
declare -A AGENT_MODEL=(
    [CUBE]="gemma3:1b"
    [CORE]="deepseek-v3.1:671b-cloud"
    [LOOP]="loop:latest"
    [LINE]="line:latest"
    [WAVE]="qwen3-vl:2b"
    [COIN]="stable-code:latest"
    [CODE]="phi:2.7b"
    [WORK]="deepseek-v3.1:671b-cloud"
)

# -----------------------------
# HELPER FUNCTIONS
# -----------------------------
ollama_check() {
    curl -sf "${OLLAMA_URL}/api/tags" >/dev/null 2>&1 || {
        warn "Ollama not reachable at ${OLLAMA_URL}"
        return 1
    }
}

resolve_model() {
    local agent="$1"
    local model="$agent"
    local available
    available=$(curl -sf "${OLLAMA_URL}/api/tags" | grep -oP '"name":"\K[^"]+')
    if ! grep -q "^${model}$" <<<"$available"; then
        warn "Model '$model' for $agent not found, fallback..."
        model=$(echo "$available" | head -n1)
        [ -z "$model" ] && { error "No models available"; return 1; }
    fi
    echo "$model"
}

agent_pidfile() { echo "$LOG_DIR/$1.pid"; }
agent_is_up() {
    local pidfile
    pidfile="$(agent_pidfile "$1")"
    [ -f "$pidfile" ] && ps -p "$(cat "$pidfile")" >/dev/null 2>&1
}

nexus-quorum-ok() {
    local a
    for a in "$@"; do
        agent_is_up "$a" || return 1
    done
    return 0
}

# -----------------------------
# NEXUS LOOP
# -----------------------------
export NEXUS_LOOP_PHASE=0
export NEXUS_LOOP_CYCLE=0
export NEXUS_LOOP_MAX=5
export NEXUS_LOOP_PI_PHASE=2
export NEXUS_LOOP_2PI=2
export NEXUS_LOOP_STATE_FILE="$NEXUS_DIR/loop.state"

_nexus_loop_advance() {
    NEXUS_LOOP_PHASE=$(( (NEXUS_LOOP_PHASE + 1) % NEXUS_LOOP_MAX ))
    [ "$NEXUS_LOOP_PHASE" -eq 0 ] && NEXUS_LOOP_CYCLE=$((NEXUS_LOOP_CYCLE + 1))
}

_nexus_loop_hash() { printf "%s:%s\n" "$NEXUS_LOOP_PHASE" "$NEXUS_LOOP_CYCLE" | sha256sum | awk '{print $1}'; }
nexus-loop-step() { _nexus_loop_advance; echo "[NEXUS::LOOP] phase:$NEXUS_LOOP_PHASE cycle:$NEXUS_LOOP_CYCLE hash:$(_nexus_loop_hash | cut -c1-16)…"; }

# -----------------------------
# START / STOP AGENTS
# -----------------------------
start_agent() {
    local agent="$1"
    ollama_check || { warn "Skipping $agent: Ollama offline"; return 1; }
    local model
    model=$(resolve_model "$agent") || return 1

    local pidfile=$(agent_pidfile "$agent")
    info "Starting agent $agent ($model)"
    nohup bash -c "\
        while true; do \
            curl -sf -X POST '${OLLAMA_URL}/api/generate' \
                -d '{\"model\":\"$model\",\"prompt\":\"$agent heartbeat\",\"stream\":false}' \
                >>'$LOG_DIR/$agent.log' 2>&1 || sleep 10; \
            sleep 60; \
        done" >>"$LOG_DIR/$agent.log" 2>&1 &
    echo $! >"$pidfile"
}

stop_agent() {
    local agent="$1"
    local pidfile=$(agent_pidfile "$agent")
    [ -f "$pidfile" ] && { kill "$(cat "$pidfile")" 2>/dev/null || true; rm -f "$pidfile"; info "Stopped $agent"; }
}

ai_status() {
    echo "=== NEXUS AI STATUS ==="
    printf "%-9s %-8s %-10s\n" "AGENT" "PID" "STATE"
    for a in "${!AGENT_MODEL[@]}"; do
        local state="DOWN" pid="-"
        local pf=$(agent_pidfile "$a")
        [ -f "$pf" ] && pid=$(cat "$pf") && ps -p "$pid" >/dev/null 2>&1 && state="UP"
        printf "%-9s %-8s %-10s\n" "$a" "$pid" "$state"
    done
}

# -----------------------------
# TOOL: GENERATE
# -----------------------------
tool_generate() {
    local PROMPT="$*"
    [ -z "$PROMPT" ] && { error "Missing prompt"; return 1; }

    local BASE_DIR="$AI_ROOT/generated"
    local TS=$(date +%s)
    local OUT_DIR="$BASE_DIR/gen_$TS"
    mkdir -p "$OUT_DIR"
    local RAW="$OUT_DIR/_raw.txt"

    local SYSTEM='You are an autonomous code generator. Output files in format: ===FILE:<path>===\n<code>\nNo explanations.'

    # Fixed heredoc with expanded variables
    ollama run "${AI_MODEL:-Cube:latest}" <<EOF >"$RAW"
$SYSTEM
TASK:
$PROMPT
EOF

    local current=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^===FILE:(.+)=== ]]; then
            current="$OUT_DIR/${BASH_REMATCH[1]}"
            mkdir -p "$(dirname "$current")"
            : >"$current"
            continue
        fi
        [ -n "$current" ] && echo "$line" >>"$current"
    done <"$RAW"

    echo "[tool_generate] files written to $OUT_DIR"
}

# -----------------------------
# TOOL: RECURSIVE
# -----------------------------
tool_recursive() {
    local PROMPT="$*"
    local MAX_DEPTH=5
    local DEPTH=0
    local BASE="$AI_ROOT/recursive"
    mkdir -p "$BASE"

    log() { echo "[recursive] $*"; }

    while [ "$DEPTH" -lt "$MAX_DEPTH" ]; do
        local DIR="$BASE/step_$DEPTH"
        mkdir -p "$DIR"
        log "DEPTH $DEPTH"

        # Safe heredoc: JSON quotes escaped, variables expanded
        ollama run "${AI_MODEL:-Cube:latest}" <<EOF >"$DIR/response.json"
You are an autonomous tool orchestrator. Output ONLY JSON:
{
  "done": false,
  "request_tools": [
    {"tool": "tool_generate", "args": "'"$PROMPT"'"}
  ]
}
EOF

        local done_flag
        done_flag=$(jq -r '.done' "$DIR/response.json")
        [ "$done_flag" = "true" ] && { log "DONE at depth $DEPTH"; break; }

        jq -c '.request_tools[]?' "$DIR/response.json" | while read -r call; do
            local tool=$(jq -r '.tool' <<<"$call")
            local args=$(jq -r '.args' <<<"$call")
            log "CALL → $tool $args"
            "$AI_ROOT/tools/$tool.sh" $args
        done

        DEPTH=$((DEPTH+1))
        PROMPT="Continue previous state"
    done

    log "RECURSION HALTED"
}

# -----------------------------
# CLI ROUTER
# -----------------------------

# 1. Add NEXUS_BRAIN to Agent Mapping if desired
AGENT_MODEL[SIGN]="gemma3:1b"

# 2. Add the Brain Tool to the CLI Router at the bottom
case "${1:-}" in
    start) shift; for a in "${!AGENT_MODEL[@]}"; do start_agent "$a"; done ;;
    stop) shift; for a in "${!AGENT_MODEL[@]}"; do stop_agent "$a"; done ;;
    status) ai_status ;;
    query)
        agent="$2"
        prompt="$3"
        ollama_check || exit 1
        model=$(resolve_model "$agent") || exit 1
        curl -sf -X POST "${OLLAMA_URL}/api/generate" \
            -d "{\"model\": \"$model\",\"prompt\": \"$prompt\",\"stream\": false}" \
            | grep -oP '"response":"\K.*?(?=","done":)' | sed 's/\\n/\n/g; s/\\"/"/g'
        ;;
    generate) shift; tool_generate "$@" ;;
    recursive) shift; tool_recursive "$@" ;;
    brain)
        shift
        # This calls the python script directly using the indexed memory
        python3 "$AI_ROOT/nexus_brain.py" "$@"
        ;;
    agent)
        shift
        python3 "$AI_ROOT/nexus_agent.py" "$@"
        ;;
    # Example of a "Memorized Generate"
    smart-gen)
        shift
        info "Consulting Brain before generation..."
        CONTEXT=$(python3 "$AI_ROOT/nexus_brain.py" "$1")
        tool_generate "Given this context: $CONTEXT. Task: $1"
        ;;
    *) echo "Usage: $0 {start|stop|status|query|generate|recursive|agent|brain}" ;;
esac
