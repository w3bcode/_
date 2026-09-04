#!/usr/bin/env bash
# =============================================================================
# ai.sh — LOOPSHAPE NEXUS / LLAMA UNIFIED SINGLE-FILE ORCHESTRATOR
# Version: 2.0.0-llama
#
# Architecture:
#
#   PROMPT
#      │
#      ▼
#   REGEX PARSER
#      │
#      ├── model / ctx / threads / GPU / sampling
#      ├── views / synthesis / session
#      └── server / cli backend
#      │
#      ▼
#   INPUT
#      ↓
#   ANALYZE
#      ↓
#   DECIDE
#      ↓
#   EXECUTE
#      ↓
#   OBSERVE
#      ↓
#   UPDATE
#      ↓
#   REPEAT
#
# Primary inference backend:
#   llama serve -> HTTP -> /v1/chat/completions
#
# Optional:
#   llama cli
#   Ollama compatibility bridge
#
# Security:
#   - NO eval on prompt text
#   - NO automatic execution of generated code
#   - workspace-confined file operations
#   - SHA256 for integrity/provenance
#   - MD5 only as legacy provenance
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="2.0.0-llama"
NAME="loopshape-ai"

# -----------------------------------------------------------------------------
# ROOT / STATE
# -----------------------------------------------------------------------------

ROOT="${AI_ROOT:-${AI_HOME:-$HOME/_}}"
STATE="${AI_STATE_DIR:-$ROOT/.ai-state}"

DB="$STATE/db"
OBJECTS="$DB/objects"
RUN="$STATE/run"
LOGS="$STATE/logs"
CACHE="$STATE/cache"
TASKS="${AI_TASKS_DIR:-$ROOT/tasks}"
PROJECTS="${AI_PROJECTS_DIR:-$ROOT/projects}"
REFERENCE="$DB/reference"

mkdir -p \
    "$STATE" \
    "$DB" \
    "$OBJECTS" \
    "$RUN" \
    "$LOGS" \
    "$CACHE" \
    "$TASKS" \
    "$PROJECTS" \
    "$REFERENCE"

ROOT_SHA256="$DB/roots.jsonl"
SESSIONS="$DB/sessions.jsonl"
TASK_DB="$DB/tasks.jsonl"
FILES_DB="$DB/files.jsonl"
TRACE_DB="$DB/traces.jsonl"
SCORES_DB="$DB/scores.jsonl"
EVENTS_DB="$DB/events.jsonl"
TOKENS_DB="$DB/tokens.jsonl"
MEMORY_DB="$DB/memory.jsonl"
BLOBS_DB="$DB/blobs.jsonl"
REFERENCE_DB="$DB/reference.jsonl"
HISTORY_DB="$DB/history.jsonl"

touch \
    "$ROOT_SHA256" \
    "$SESSIONS" \
    "$TASK_DB" \
    "$FILES_DB" \
    "$TRACE_DB" \
    "$SCORES_DB" \
    "$EVENTS_DB" \
    "$TOKENS_DB" \
    "$MEMORY_DB" \
    "$BLOBS_DB" \
    "$REFERENCE_DB" \
    "$HISTORY_DB"

# -----------------------------------------------------------------------------
# LLAMA CONFIG
# -----------------------------------------------------------------------------

LLAMA_HOST="${LLAMA_HOST:-127.0.0.1}"
LLAMA_PORT="${LLAMA_PORT:-8080}"
LLAMA_BASE_URL="${LLAMA_BASE_URL:-http://${LLAMA_HOST}:${LLAMA_PORT}}"

MODEL="${AI_MODEL:-${LLAMA_MODEL:-Qwen/Qwen2.5-Coder-3B-Instruct-GGUF:Q4_K_M}}"

FALLBACK_MODEL="${AI_FALLBACK:-qwen3:0.6b}"

CTX="${AI_CTX:-${LLAMA_CTX_SIZE:-4096}}"
THREADS="${AI_THREADS:-${LLAMA_THREADS:-8}}"
GPU_LAYERS="${AI_GPU_LAYERS:-${LLAMA_GPU_LAYERS:-0}}"

BATCH="${AI_BATCH:-${LLAMA_BATCH:-256}}"
UBATCH="${AI_UBATCH:-${LLAMA_UBATCH:-128}}"

TEMP="${AI_TEMP:-${LLAMA_TEMP:-0.65}}"
TOP_P="${AI_TOP_P:-${LLAMA_TOP_P:-0.95}}"
TOP_K="${AI_TOP_K:-${LLAMA_TOP_K:-40}}"
REPEAT="${AI_REPEAT_PENALTY:-${LLAMA_REPEAT_PENALTY:-1.10}}"

N_PREDICT="${AI_N_PREDICT:-512}"

VIEWS="${AI_VIEWS:-1}"
SYNTHESIS="${AI_SYNTHESIS:-false}"
PARALLEL="${AI_PARALLEL:-0}"

TIMEOUT="${AI_TIMEOUT:-600}"
SESSION="${AI_SESSION:-default}"

SERVER_AUTOSTART="${AI_SERVER_AUTOSTART:-1}"
FALLBACK_CLI="${AI_FALLBACK_CLI:-0}"

SYSTEM_PROMPT="${AI_SYSTEM_PROMPT:-You are a precise local software-engineering agent. Analyze, decide, execute requested non-destructive workflows, observe results, and update state. Never claim an operation was performed unless it actually was.}"

SERVER_PID="$RUN/llama-server.pid"
SERVER_LOG="$LOGS/llama-server.log"

# -----------------------------------------------------------------------------
# BASIC UTILITIES
# -----------------------------------------------------------------------------

die() {
    printf 'ai.sh: %s\n' "$*" >&2
    exit 1
}

warn() {
    printf 'ai.sh: warning: %s\n' "$*" >&2
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 ||
        die "required command not found: $1"
}

now_epoch() {
    date +%s
}

now_iso() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# -----------------------------------------------------------------------------
# LLAMA RESOLUTION
#
# IMPORTANT:
# Do not use:
#
#     LLAMA_BIN="/home/linuxbrew/.linuxbrew/bin/llama"
#
# blindly.
#
# The executable may instead be:
#
#     /home/linuxbrew/.linuxbrew/bin/llama
#     ~/.linuxbrew/bin/llama
#     /usr/local/bin/llama
#     /usr/bin/llama
#
# or simply available through PATH.
# -----------------------------------------------------------------------------

resolve_llama() {

    local candidate

    # Explicit absolute override.
    if [[ -n "${LLAMA_BIN:-}" ]]; then

        if [[ "$LLAMA_BIN" == */* ]]; then
            if [[ -x "$LLAMA_BIN" ]]; then
                printf '%s\n' "$LLAMA_BIN"
                return 0
            fi
        else
            candidate="$(command -v "$LLAMA_BIN" 2>/dev/null || true)"

            if [[ -n "$candidate" && -x "$candidate" ]]; then
                printf '%s\n' "$candidate"
                return 0
            fi
        fi
    fi

    # PATH.
    candidate="$(command -v llama 2>/dev/null || true)"

    if [[ -n "$candidate" && -x "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    # Common user/system locations.
    for candidate in \
        "$HOME/.linuxbrew/bin/llama" \
        "$HOME/.local/bin/llama" \
        "$HOME/bin/llama" \
        "/home/linuxbrew/.linuxbrew/bin/llama" \
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

LLAMA_RESOLVED="$(resolve_llama || true)"

if [[ -n "$LLAMA_RESOLVED" ]]; then
    LLAMA_BIN="$LLAMA_RESOLVED"
else
    LLAMA_BIN="${LLAMA_BIN:-llama}"
fi

unset LLAMA_RESOLVED

llama_exists() {
    if [[ "$LLAMA_BIN" == */* ]]; then
        [[ -x "$LLAMA_BIN" ]]
    else
        command -v "$LLAMA_BIN" >/dev/null 2>&1
    fi
}

require_llama() {

    if llama_exists; then
        return 0
    fi

    cat >&2 <<EOF
ai.sh: llama not found: $LLAMA_BIN

Set LLAMA_BIN to the real executable:

  export LLAMA_BIN=/absolute/path/to/llama

Then verify:

  "\$LLAMA_BIN" --version

Search for it with:

  find "\$HOME" /home/linuxbrew /usr/local /usr \\
      -type f -name llama -perm -111 2>/dev/null

Current PATH:

  $PATH
EOF

    return 127
}

# -----------------------------------------------------------------------------
# HASHING
# -----------------------------------------------------------------------------

sha256_text() {

    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$1" |
            sha256sum |
            awk '{print $1}'
        return
    fi

    if command -v shasum >/dev/null 2>&1; then
        printf '%s' "$1" |
            shasum -a 256 |
            awk '{print $1}'
        return
    fi

    die "sha256sum or shasum required"
}

sha256_file() {

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" |
            awk '{print $1}'
        return
    fi

    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" |
            awk '{print $1}'
        return
    fi

    die "sha256sum or shasum required"
}

md5_file() {

    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$1" |
            awk '{print $1}'
        return
    fi

    if command -v md5 >/dev/null 2>&1; then
        md5 -q "$1"
        return
    fi

    printf ''
}

# -----------------------------------------------------------------------------
# EVENT STORE
# -----------------------------------------------------------------------------

log_event() {

    local type="${1:-event}"
    local message="${2:-}"
    local task="${3:-}"
    local session="${4:-$SESSION}"

    jq -cn \
        --arg timestamp "$(now_iso)" \
        --arg type "$type" \
        --arg task "$task" \
        --arg session "$session" \
        --arg message "$message" \
        '{
            timestamp:$timestamp,
            type:$type,
            task_id:$task,
            session:$session,
            message:$message
        }' >> "$EVENTS_DB"
}

# -----------------------------------------------------------------------------
# GENESIS
# -----------------------------------------------------------------------------

genesis() {

    local ts seed hash

    ts="$(now_epoch)"

    seed="${ts}:$((ts % 1000000007)):$((ts % 7))"

    hash="$(sha256_text "$seed")"

    jq -cn \
        --arg timestamp "$(now_iso)" \
        --arg seed "$seed" \
        --arg hash "$hash" \
        '{
            timestamp:$timestamp,
            seed:$seed,
            genesis:$hash
        }' >> "$ROOT_SHA256"

    printf '%s\n' "$hash"
}

session_root() {

    sha256_text "session:$SESSION:$1"
}

round_id() {

    sha256_text \
        "round:$SESSION:$2:$(now_epoch):$1"
}

# -----------------------------------------------------------------------------
# REGEX STRING PARSER
#
# Example:
#
# ai.sh '@model=Qwen/Qwen2.5-Coder-3B-Instruct-GGUF:Q4_K_M @views=4 @synthesis=true Build agent'
# -----------------------------------------------------------------------------

PARSE_MODEL="$MODEL"
PARSE_CTX="$CTX"
PARSE_THREADS="$THREADS"
PARSE_GPU_LAYERS="$GPU_LAYERS"
PARSE_BATCH="$BATCH"
PARSE_UBATCH="$UBATCH"

PARSE_TEMP="$TEMP"
PARSE_TOP_P="$TOP_P"
PARSE_TOP_K="$TOP_K"
PARSE_REPEAT="$REPEAT"

PARSE_N_PREDICT="$N_PREDICT"

PARSE_VIEWS="$VIEWS"
PARSE_SYNTHESIS="$SYNTHESIS"
PARSE_PARALLEL="$PARALLEL"

PARSE_SESSION="$SESSION"
PARSE_SERVER="auto"
PARSE_CLI="0"

PARSE_SYSTEM="$SYSTEM_PROMPT"

reset_parse() {

    PARSE_MODEL="$MODEL"
    PARSE_CTX="$CTX"
    PARSE_THREADS="$THREADS"
    PARSE_GPU_LAYERS="$GPU_LAYERS"

    PARSE_BATCH="$BATCH"
    PARSE_UBATCH="$UBATCH"

    PARSE_TEMP="$TEMP"
    PARSE_TOP_P="$TOP_P"
    PARSE_TOP_K="$TOP_K"
    PARSE_REPEAT="$REPEAT"

    PARSE_N_PREDICT="$N_PREDICT"

    PARSE_VIEWS="$VIEWS"
    PARSE_SYNTHESIS="$SYNTHESIS"
    PARSE_PARALLEL="$PARALLEL"

    PARSE_SESSION="$SESSION"

    PARSE_SERVER="auto"
    PARSE_CLI="0"

    PARSE_SYSTEM="$SYSTEM_PROMPT"
}

parse_prompt() {

    local raw="$1"
    local token key value

    reset_parse

    while read -r token; do

        [[ "$token" == @*=* ]] || continue

        key="${token#@}"
        key="${key%%=*}"

        value="${token#*=}"

        case "$key" in

            model)
                PARSE_MODEL="$value"
                ;;

            ctx|context)
                PARSE_CTX="$value"
                ;;

            threads)
                PARSE_THREADS="$value"
                ;;

            gpu_layers)
                PARSE_GPU_LAYERS="$value"
                ;;

            batch)
                PARSE_BATCH="$value"
                ;;

            ubatch)
                PARSE_UBATCH="$value"
                ;;

            temp|temperature)
                PARSE_TEMP="$value"
                ;;

            top_p)
                PARSE_TOP_P="$value"
                ;;

            top_k)
                PARSE_TOP_K="$value"
                ;;

            repeat_penalty)
                PARSE_REPEAT="$value"
                ;;

            n_predict|max_tokens)
                PARSE_N_PREDICT="$value"
                ;;

            views)
                PARSE_VIEWS="$value"
                ;;

            synthesis)
                PARSE_SYNTHESIS="$value"
                ;;

            parallel)
                PARSE_PARALLEL="$value"
                ;;

            session)
                PARSE_SESSION="$value"
                ;;

            server)
                PARSE_SERVER="$value"
                ;;

            cli)
                PARSE_CLI="$value"
                ;;

            system)
                PARSE_SYSTEM="$value"
                ;;

        esac

    done < <(
        grep -oE \
            '@[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+' \
            <<< "$raw" || true
    )
}

strip_controls() {

    sed -E \
        's/@[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+//g' |
    sed -E \
        's/[[:space:]]+/ /g' |
    sed -E \
        's/^[[:space:]]+|[[:space:]]+$//g'
}

# -----------------------------------------------------------------------------
# ENTROPY
# -----------------------------------------------------------------------------

entropy_text() {

    awk '
    {
        for(i=1;i<=NF;i++) {

            t=$i

            gsub(/[^[:alnum:]_:-]/,"",t)

            if(t!="") {
                c[t]++
                total++
            }
        }
    }

    END {

        if(total==0) {
            printf "0.000000\n"
            exit
        }

        for(t in c) {

            p=c[t]/total

            h-=p*log(p)/log(2)
        }

        printf "%.6f\n",h
    }
    ' <<< "$1"
}

# -----------------------------------------------------------------------------
# TOKEN WEIGHTS
# -----------------------------------------------------------------------------

rank_text() {

    awk '
    {
        for(i=1;i<=NF;i++) {

            t=$i

            gsub(/[^[:alnum:]_:-]/,"",t)

            if(t!="")
                c[t]++
        }
    }

    END {

        total=0

        for(t in c)
            total+=c[t]

        for(t in c) {

            p=c[t]/total
            s=-log(p)/log(2)
            w=(1-p)*s

            printf "%s\t%d\t%.8f\t%.8f\t%.8f\n",
                t,c[t],p,s,w
        }
    }
    ' <<< "$1" |
    sort -k5,5nr
}

# -----------------------------------------------------------------------------
# WORKSPACE CONTAINMENT
# -----------------------------------------------------------------------------

realpath_existing() {

    readlink -f -- "$1" 2>/dev/null ||
    realpath -- "$1" 2>/dev/null ||
    printf '%s\n' "$1"
}

workspace_path() {

    local p="$1"
    local rp rr

    rp="$(realpath_existing "$p")"
    rr="$(realpath_existing "$ROOT")"

    case "$rp" in
        "$rr"|"$rr"/*)
            printf '%s\n' "$rp"
            ;;

        *)
            die "path escapes AI_ROOT: $p"
            ;;
    esac
}

# -----------------------------------------------------------------------------
# FILE INDEX
# -----------------------------------------------------------------------------

index_file() {

    local f="$1"

    [[ -f "$f" ]] || return 0

    local sha md5 bytes mtime ent parent origin

    sha="$(sha256_file "$f")"
    md5="$(md5_file "$f")"

    bytes="$(
        wc -c < "$f" |
        tr -d ' '
    )"

    mtime="$(
        stat -c %Y "$f" 2>/dev/null ||
        stat -f %m "$f" 2>/dev/null ||
        printf '0'
    )"

    ent="$(
        head -c "${AI_MAX_BYTES:-10485760}" "$f" 2>/dev/null |
        entropy_text
    )"

    parent="$(basename "$(dirname "$f")")"

    origin="$(
        sha256_text \
            "origin:$parent:$(basename "$f")"
    )"

    jq -cn \
        --arg path "$f" \
        --arg sha256 "$sha" \
        --arg md5 "$md5" \
        --arg origin "$origin" \
        --arg parent "$parent" \
        --arg entropy "$ent" \
        --argjson bytes "${bytes:-0}" \
        --argjson mtime "${mtime:-0}" \
        '{
            path:$path,
            sha256:$sha256,
            md5_legacy:$md5,
            origin_hash:$origin,
            parent:$parent,
            entropy:($entropy|tonumber),
            bytes:$bytes,
            mtime:$mtime
        }' >> "$FILES_DB"
}

index_path() {

    local p="${1:-$ROOT}"

    p="$(workspace_path "$p")"

    if [[ -f "$p" ]]; then
        index_file "$p"
        return
    fi

    find "$p" \
        -type f \
        ! -path '*/.git/*' \
        ! -path '*/node_modules/*' \
        ! -path '*/.ai-state/*' \
        -print0 2>/dev/null |
    while IFS= read -r -d '' f; do
        index_file "$f"
    done
}

# -----------------------------------------------------------------------------
# CRUD
# -----------------------------------------------------------------------------

crud_read() {

    local p

    p="$(workspace_path "$1")"

    [[ -f "$p" ]] ||
        die "not a file: $1"

    cat "$p"
}

crud_create() {

    local p

    p="$(workspace_path "$1")"

    [[ ! -e "$p" ]] ||
        die "already exists: $p"

    mkdir -p "$(dirname "$p")"

    cat > "$p"

    index_file "$p"
}

crud_update() {

    local p tmp

    p="$(workspace_path "$1")"

    [[ -f "$p" ]] ||
        die "not a file: $1"

    tmp="$(mktemp "${p}.tmp.XXXXXX")"

    cat > "$tmp"

    mv -f "$tmp" "$p"

    index_file "$p"
}

crud_delete() {

    local p

    p="$(workspace_path "$1")"

    [[ -f "$p" ]] ||
        die "not a file: $1"

    rm -f -- "$p"
}

# -----------------------------------------------------------------------------
# CONTEXT LOADER
# -----------------------------------------------------------------------------

load_context() {

    local spec="$1"
    local p

    [[ -n "$spec" ]] || return 0

    for p in $spec; do

        if [[ -f "$p" ]]; then

            p="$(workspace_path "$p")"

            printf '\n[FILE: %s]\n' "$p"

            head -c \
                "${AI_MAX_BYTES:-10485760}" \
                "$p"

            printf '\n[/FILE]\n'

        elif [[ "$p" =~ ^https?:// ]]; then

            need_cmd curl

            printf '\n[URL: %s]\n' "$p"

            curl \
                --fail \
                --silent \
                --show-error \
                --max-time 20 \
                --location "$p" |
                head -c "${AI_MAX_BYTES:-10485760}"

            printf '\n[/URL]\n'
        fi
    done
}

# -----------------------------------------------------------------------------
# LLAMA SERVER
# -----------------------------------------------------------------------------

server_health() {

    need_cmd curl

    curl \
        --fail \
        --silent \
        --show-error \
        --max-time 5 \
        "$LLAMA_BASE_URL/health"
}

server_models() {

    need_cmd curl

    curl \
        --fail \
        --silent \
        --show-error \
        --max-time 5 \
        "$LLAMA_BASE_URL/v1/models"
}

server_status() {

    printf 'llama_bin=%s\n' "$LLAMA_BIN"
    printf 'base_url=%s\n' "$LLAMA_BASE_URL"
    printf 'model=%s\n' "$MODEL"

    printf \
        'ctx=%s threads=%s gpu_layers=%s\n' \
        "$CTX" \
        "$THREADS" \
        "$GPU_LAYERS"

    if server_health >/dev/null 2>&1; then
        printf 'server=READY\n'
    else
        printf 'server=OFFLINE\n'
    fi

    if [[ -s "$SERVER_PID" ]]; then
        printf 'pid=%s\n' "$(cat "$SERVER_PID")"
    fi
}

server_start() {

    require_llama
    need_cmd curl

    if server_health >/dev/null 2>&1; then

        printf \
            'llama-server already ready at %s\n' \
            "$LLAMA_BASE_URL"

        return 0
    fi

    local oldpid=""

    if [[ -s "$SERVER_PID" ]]; then

        oldpid="$(
            cat "$SERVER_PID" 2>/dev/null || true
        )"

        if [[ "$oldpid" =~ ^[0-9]+$ ]] &&
           kill -0 "$oldpid" 2>/dev/null
        then
            warn \
                "server process exists but health endpoint is not ready"
        else
            rm -f "$SERVER_PID"
        fi
    fi

    : > "$SERVER_LOG"

    local -a cmd

    cmd=(
        "$LLAMA_BIN"
        serve

        --host "$LLAMA_HOST"
        --port "$LLAMA_PORT"

        --ctx-size "$CTX"
        --threads "$THREADS"

        --n-gpu-layers "$GPU_LAYERS"

        --batch-size "$BATCH"
        --ubatch-size "$UBATCH"
    )

    # HF repository vs local GGUF.
    if [[ "$MODEL" == *.gguf ||
          "$MODEL" == /* ||
          "$MODEL" == ./* ]]
    then
        cmd+=(
            --model
            "$MODEL"
        )
    else
        cmd+=(
            -hf
            "$MODEL"
        )
    fi

    # Sampling.
    cmd+=(
        --temp "$TEMP"
        --top-p "$TOP_P"
        --top-k "$TOP_K"
        --repeat-penalty "$REPEAT"
    )

    printf '%q ' "${cmd[@]}" >> "$LOGS/last-server-command.txt"
    printf '\n' >> "$LOGS/last-server-command.txt"

    nohup "${cmd[@]}" \
        >> "$SERVER_LOG" \
        2>&1 &

    local pid=$!

    printf '%s\n' "$pid" > "$SERVER_PID"

    local i

    for i in $(seq 1 60); do

        if server_health >/dev/null 2>&1; then

            printf \
                'llama-server ready pid=%s url=%s\n' \
                "$pid" \
                "$LLAMA_BASE_URL"

            log_event \
                "SERVER_START" \
                "llama-server ready" \
                ""

            return 0
        fi

        if ! kill -0 "$pid" 2>/dev/null; then

            warn \
                "llama-server exited before becoming ready"

            tail -n 100 "$SERVER_LOG" >&2 || true

            return 1
        fi

        sleep 1
    done

    warn "llama-server startup timeout"

    tail -n 100 "$SERVER_LOG" >&2 || true

    return 1
}

server_stop() {

    local pid=""

    [[ -s "$SERVER_PID" ]] &&
        pid="$(cat "$SERVER_PID" 2>/dev/null || true)"

    if [[ "$pid" =~ ^[0-9]+$ ]] &&
       kill -0 "$pid" 2>/dev/null
    then

        kill "$pid" 2>/dev/null || true

        for _ in $(seq 1 20); do

            kill -0 "$pid" 2>/dev/null ||
                break

            sleep .2
        done
    fi

    rm -f "$SERVER_PID"

    log_event \
        "SERVER_STOP" \
        "llama-server stopped" \
        ""

    printf '%s\n' 'llama-server stopped'
}

server_restart() {

    server_stop || true

    sleep .5

    server_start
}

server_logs() {

    tail \
        -n "${1:-120}" \
        "$SERVER_LOG" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# OPENAI-COMPATIBLE LLAMA HTTP CHAT
# -----------------------------------------------------------------------------

server_chat() {

    local system="$1"
    local prompt="$2"
    local model="$3"
    local history_file="$4"

    local payload response

    need_cmd curl
    need_cmd jq

    local history='[]'

    if [[ -s "$history_file" ]]; then

        history="$(
            tail -n 24 "$history_file" |
            jq -s '.' 2>/dev/null ||
            printf '[]'
        )"
    fi

    payload="$(
        jq -cn \
            --arg system "$system" \
            --arg prompt "$prompt" \
            --arg model "$model" \
            --argjson history "$history" \
            --argjson temp "$TEMP" \
            --argjson top_p "$TOP_P" \
            --argjson top_k "$TOP_K" \
            --argjson repeat "$REPEAT" \
            --argjson max_tokens "$N_PREDICT" \
            '{
                model:$model,

                messages:
                    (
                        [
                            {
                                role:"system",
                                content:$system
                            }
                        ]

                        +

                        (
                            $history |
                            map(
                                select(
                                    .role=="user" or
                                    .role=="assistant"
                                )
                            )
                        )

                        +

                        [
                            {
                                role:"user",
                                content:$prompt
                            }
                        ]
                    ),

                temperature:$temp,
                top_p:$top_p,
                top_k:$top_k,
                repeat_penalty:$repeat,
                max_tokens:$max_tokens,
                stream:false
            }'
    )"

    response="$(
        curl \
            --fail \
            --silent \
            --show-error \
            --max-time "$TIMEOUT" \
            -H 'Content-Type: application/json' \
            -d "$payload" \
            "$LLAMA_BASE_URL/v1/chat/completions"
    )" || return $?

    jq -r \
        '.choices[0].message.content //
         .choices[0].text //
         empty' \
        <<< "$response"
}

# -----------------------------------------------------------------------------
# DIRECT LLAMA CLI FALLBACK
# -----------------------------------------------------------------------------

cli_infer() {

    require_llama

    local prompt="$1"

    "$LLAMA_BIN" cli \
        -hf "$MODEL" \
        --ctx-size "$CTX" \
        --threads "$THREADS" \
        --n-gpu-layers "$GPU_LAYERS" \
        --temp "$TEMP" \
        --top-p "$TOP_P" \
        --top-k "$TOP_K" \
        --repeat-penalty "$REPEAT" \
        --single-turn \
        --prompt "$prompt"
}

# -----------------------------------------------------------------------------
# SESSION HISTORY
# -----------------------------------------------------------------------------

session_file() {

    printf '%s/%s.jsonl\n' \
        "$CACHE" \
        "$(sha256_text "session:$SESSION" |
          cut -c1-24)"
}

append_history() {

    local role="$1"
    local content="$2"

    jq -cn \
        --arg role "$role" \
        --arg content "$content" \
        '{
            role:$role,
            content:$content
        }' >> "$(session_file)"
}

# -----------------------------------------------------------------------------
# MEMORY
# -----------------------------------------------------------------------------

remember() {

    local task="$1"
    local prompt="$2"
    local response="$3"
    local parent="$4"

    local hash

    hash="$(sha256_text "$response")"

    jq -cn \
        --arg timestamp "$(now_iso)" \
        --arg task "$task" \
        --arg session "$SESSION" \
        --arg prompt "$prompt" \
        --arg response "$response" \
        --arg response_hash "$hash" \
        --arg parent "$parent" \
        '{
            timestamp:$timestamp,
            task_id:$task,
            session:$session,
            prompt:$prompt,
            response:$response,
            response_sha256:$response_hash,
            parent:$parent
        }' >> "$MEMORY_DB"
}

# -----------------------------------------------------------------------------
# MAIN ORCHESTRATOR
#
# INPUT
# ANALYZE
# DECIDE
# EXECUTE
# OBSERVE
# UPDATE
# REPEAT
# -----------------------------------------------------------------------------

run_one() {

    local raw="$1"
    local context="${2:-}"
    local project="${3:-}"
    local parent="${4:-}"

    parse_prompt "$raw"

    local prompt

    prompt="$(strip_controls "$raw")"

    if [[ -n "$context" ]]; then

        prompt+=$'\n'

        prompt+="$(load_context "$context")"
    fi

    # Apply parser.
    SESSION="$PARSE_SESSION"

    MODEL="$PARSE_MODEL"
    CTX="$PARSE_CTX"
    THREADS="$PARSE_THREADS"
    GPU_LAYERS="$PARSE_GPU_LAYERS"

    BATCH="$PARSE_BATCH"
    UBATCH="$PARSE_UBATCH"

    TEMP="$PARSE_TEMP"
    TOP_P="$PARSE_TOP_P"
    TOP_K="$PARSE_TOP_K"
    REPEAT="$PARSE_REPEAT"

    N_PREDICT="$PARSE_N_PREDICT"

    local round

    round="$(
        round_id "$prompt" "$parent"
    )"

    local task="$round"

    local started

    started="$(now_epoch)"

    # INPUT
    jq -cn \
        --arg timestamp "$(now_iso)" \
        --arg task "$task" \
        --arg round "$round" \
        --arg parent "$parent" \
        --arg session "$SESSION" \
        --arg state "INPUT" \
        --arg prompt "$prompt" \
        '{
            timestamp:$timestamp,
            task_id:$task,
            round:$round,
            parent:$parent,
            session:$session,
            state:$state,
            prompt:$prompt
        }' >> "$TASK_DB"

    log_event \
        "INPUT" \
        "$prompt" \
        "$task"

    # ANALYZE
    local ent

    ent="$(entropy_text "$prompt")"

    jq -cn \
        --arg timestamp "$(now_iso)" \
        --arg task "$task" \
        --arg state "ANALYZE" \
        --arg entropy "$ent" \
        '{
            timestamp:$timestamp,
            task_id:$task,
            state:$state,
            entropy:($entropy|tonumber)
        }' >> "$TRACE_DB"

    log_event \
        "ANALYZE" \
        "entropy=$ent" \
        "$task"

    # DECIDE
    local backend="$PARSE_SERVER"

    if [[ "$PARSE_CLI" == "1" ]]; then
        backend="cli"
    elif [[ "$backend" == "auto" ]]; then
        backend="server"
    fi

    log_event \
        "DECIDE" \
        "backend=$backend model=$MODEL" \
        "$task"

    # EXECUTE
    local count="$PARSE_VIEWS"

    [[ "$count" =~ ^[1-9][0-9]*$ ]] ||
        count=1

    local i
    local q
    local out

    local -a outputs=()

    for i in $(seq 1 "$count"); do

        q="$prompt"

        if (( count > 1 )); then

            q=$(
                cat <<EOF
You are POV worker $i/$count.

Analyze the task from an independent engineering perspective.

Return actionable findings.
Do not fabricate execution.

TASK:

$prompt
EOF
            )
        fi

        if [[ "$backend" == "server" ]]; then

            if ! server_health >/dev/null 2>&1; then

                if [[ "$SERVER_AUTOSTART" == "1" ]]; then

                    if ! server_start; then

                        if [[ "$FALLBACK_CLI" == "1" ]]; then
                            backend="cli"
                        else
                            die "llama-server failed to start"
                        fi
                    fi

                elif [[ "$FALLBACK_CLI" == "1" ]]; then

                    backend="cli"

                else

                    die \
                        "llama-server unavailable at $LLAMA_BASE_URL"
                fi
            fi
        fi

        if [[ "$backend" == "server" ]]; then

            out="$(
                server_chat \
                    "$PARSE_SYSTEM" \
                    "$q" \
                    "$MODEL" \
                    "$(session_file)"
            )" ||
                die "llama HTTP inference failed in view $i"

        else

            out="$(
                cli_infer "$q"
            )" ||
                die "llama CLI inference failed in view $i"
        fi

        outputs+=("$out")

        local output_hash

        output_hash="$(
            sha256_text "$out"
        )"

        jq -cn \
            --arg timestamp "$(now_iso)" \
            --arg task "$task" \
            --arg round "$round" \
            --argjson view "$i" \
            --arg output_hash "$output_hash" \
            --arg output "$out" \
            '{
                timestamp:$timestamp,
                task_id:$task,
                round:$round,
                view:$view,
                output_sha256:$output_hash,
                output:$output
            }' >> "$TRACE_DB"

        append_history \
            user \
            "$q"

        append_history \
            assistant \
            "$out"

        printf '%s\n' "$out"

        if (( i < count )); then
            printf '\n--- POV %s ---\n' "$i"
        fi
    done

    # SYNTHESIS
    local response

    if (( count > 1 )) &&
       [[ "${PARSE_SYNTHESIS,,}" == "true" ||
          "${PARSE_SYNTHESIS}" == "1" ]]
    then

        local fused=""

        for out in "${outputs[@]}"; do
            fused+=$'\n--- VIEW ---\n'
            fused+="$out"
        done

        local synthesis_prompt

        synthesis_prompt=$(
            cat <<EOF
Synthesize the following independent engineering views into one precise answer.

Resolve contradictions explicitly.

Do not claim code was executed unless execution evidence exists.

$fused
EOF
        )

        if [[ "$backend" == "server" ]]; then

            response="$(
                server_chat \
                    "$PARSE_SYSTEM" \
                    "$synthesis_prompt" \
                    "$MODEL" \
                    "$(session_file)"
            )"

        else

            response="$(
                cli_infer "$synthesis_prompt"
            )"
        fi

        printf '\n=== SYNTHESIS ===\n'
        printf '%s\n' "$response"

    else

        response="${outputs[0]}"
    fi

    # OBSERVE
    local output_entropy
    local output_hash

    output_entropy="$(
        entropy_text "$response"
    )"

    output_hash="$(
        sha256_text "$response"
    )"

    jq -cn \
        --arg timestamp "$(now_iso)" \
        --arg task "$task" \
        --arg state "OBSERVE" \
        --arg hash "$output_hash" \
        --arg entropy "$output_entropy" \
        '{
            timestamp:$timestamp,
            task_id:$task,
            state:$state,
            sha256:$hash,
            entropy:($entropy|tonumber)
        }' >> "$TRACE_DB"

    jq -cn \
        --arg task "$task" \
        --arg text "$response" \
        --arg entropy "$output_entropy" \
        '{
            task_id:$task,
            text:$text,
            entropy:($entropy|tonumber)
        }' >> "$SCORES_DB"

    # UPDATE
    remember \
        "$task" \
        "$prompt" \
        "$response" \
        "$parent"

    jq -cn \
        --arg timestamp "$(now_iso)" \
        --arg task "$task" \
        --arg state "UPDATE" \
        --arg response_hash "$output_hash" \
        --arg parent "$parent" \
        --argjson elapsed \
            "$(( $(now_epoch) - started ))" \
        '{
            timestamp:$timestamp,
            task_id:$task,
            state:$state,
            response_sha256:$response_hash,
            parent:$parent,
            elapsed_seconds:$elapsed
        }' >> "$TRACE_DB"

    log_event \
        "UPDATE" \
        "response_sha256=$output_hash" \
        "$task"

    # Generated code is extracted but NEVER executed.
    if [[ -n "$project" ]]; then
        extract_code \
            "$response" \
            "$project" ||
            true
    fi

    printf '%s\n' "$response"
}

# -----------------------------------------------------------------------------
# CODE EXTRACTION
# -----------------------------------------------------------------------------

language_extension() {

    case "${1,,}" in

        bash|sh|shell)
            printf 'sh'
            ;;

        javascript|js)
            printf 'js'
            ;;

        typescript|ts)
            printf 'ts'
            ;;

        python|py)
            printf 'py'
            ;;

        html)
            printf 'html'
            ;;

        css)
            printf 'css'
            ;;

        json)
            printf 'json'
            ;;

        yaml|yml)
            printf 'yml'
            ;;

        sql)
            printf 'sql'
            ;;

        go)
            printf 'go'
            ;;

        rust|rs)
            printf 'rs'
            ;;

        c)
            printf 'c'
            ;;

        cpp|c++)
            printf 'cpp'
            ;;

        *)
            printf 'txt'
            ;;
    esac
}

validate_code() {

    local file="$1"
    local lang="${2,,}"
    local rc=0

    case "$lang" in

        bash|sh|shell)
            bash -n "$file" >/dev/null 2>&1 ||
                rc=$?
            ;;

        python|py)
            python3 -m py_compile "$file" >/dev/null 2>&1 ||
                rc=$?
            ;;

        javascript|js)
            node --check "$file" >/dev/null 2>&1 ||
                rc=$?
            ;;

        php)
            php -l "$file" >/dev/null 2>&1 ||
                rc=$?
            ;;

        json)
            jq empty "$file" >/dev/null 2>&1 ||
                rc=$?
            ;;

        *)
            return 0
            ;;
    esac

    if (( rc == 0 )); then

        log_event \
            "VALIDATION_SUCCESS" \
            "$file"

    else

        log_event \
            "VALIDATION_ERROR" \
            "$file rc=$rc"
    fi

    return "$rc"
}

extract_code() {

    local content="$1"
    local project="${2:-task_$(date +%s)}"

    local dir="$PROJECTS/$project"

    mkdir -p "$dir"

    local n=0
    local lang
    local code
    local ext
    local file

    while IFS= read -r block; do

        [[ -n "$block" ]] ||
            continue

        lang="$(sed -n '1p' <<< "$block")"
        code="$(sed '1d' <<< "$block")"

        ext="$(
            language_extension "$lang"
        )"

        n=$((n + 1))

        file="$dir/generated_${n}.${ext}"

        printf '%s\n' "$code" > "$file"

        index_file "$file"

        validate_code \
            "$file" \
            "$lang" ||
            true

        printf '%s\n' "$file"

    done < <(
        awk '
        /^```/ {

            if(inblock) {
                print buf
                buf=""
                inblock=0
            }

            else {
                inblock=1
                print substr($0,4)
            }

            next
        }

        inblock {
            buf=buf $0 "\n"
        }
        ' <<< "$content"
    )
}

# -----------------------------------------------------------------------------
# CONSENSUS
# -----------------------------------------------------------------------------

consensus() {

    local prompt="$1"
    local rounds="${2:-3}"
    local project="${3:-}"

    local parent=""
    local current="$prompt"
    local result=""
    local i

    [[ "$rounds" =~ ^[1-9][0-9]*$ ]] ||
        rounds=3

    for i in $(seq 1 "$rounds"); do

        printf \
            '\n=== CONSENSUS ITERATION %s/%s ===\n' \
            "$i" \
            "$rounds"

        result="$(
            run_one \
                "$current" \
                "" \
                "$project" \
                "$parent"
        )"

        parent="$(
            round_id \
                "$current" \
                "$parent"
        )"

        if (( i < rounds )); then

            current=$(
                cat <<EOF
Review the previous result for:

1. correctness
2. missing requirements
3. contradictions
4. implementation risk

Produce a corrected next result.

PREVIOUS RESULT:

$result
EOF
            )
        fi
    done

    printf \
        '\n=== CONSENSUS FINAL ===\n%s\n' \
        "$result"
}

# -----------------------------------------------------------------------------
# REPL
# -----------------------------------------------------------------------------

repl() {

    printf '%s\n' "$NAME $VERSION"

    printf '%s\n' \
        'Commands: /help /status /server /models /history /index /clear /exit'

    while true; do

        printf 'ai> '

        IFS= read -r line ||
            break

        [[ -n "$line" ]] ||
            continue

        case "$line" in

            /exit|/quit)
                break
                ;;

            /help)

                printf '%s\n' \
                    '/status        runtime status' \
                    '/server        llama server status' \
                    '/models        llama models' \
                    '/history       session history' \
                    '/index [path]  index workspace' \
                    '/clear         clear session' \
                    '/exit          leave REPL'
                ;;

            /status)
                status
                ;;

            /server)
                server_status
                ;;

            /models)
                server_models 2>/dev/null || true
                ;;

            /history)
                cat "$(session_file)" 2>/dev/null || true
                ;;

            /clear)
                : > "$(session_file)"
                ;;

            /index*)
                index_path \
                    "${line#/index }"
                ;;

            *)
                run_one "$line"
                ;;

        esac
    done
}

# -----------------------------------------------------------------------------
# STATUS
# -----------------------------------------------------------------------------

status() {

    printf '%s\n' \
        '========================================'

    printf ' %s %s\n' \
        "$NAME" \
        "$VERSION"

    printf '%s\n' \
        '========================================'

    printf 'root=%s\n' "$ROOT"
    printf 'state=%s\n' "$STATE"

    printf 'llama=%s\n' "$LLAMA_BIN"

    printf 'model=%s\n' "$MODEL"

    printf 'server=%s\n' "$LLAMA_BASE_URL"

    printf \
        'session=%s\n' \
        "$SESSION"

    printf \
        'views=%s synthesis=%s parallel=%s\n' \
        "$VIEWS" \
        "$SYNTHESIS" \
        "$PARALLEL"

    server_status
}

# -----------------------------------------------------------------------------
# DOCTOR
# -----------------------------------------------------------------------------

doctor() {

    status

    printf '\n--- dependencies ---\n'

    local c

    for c in \
        bash \
        curl \
        jq \
        awk \
        sed \
        grep \
        find \
        sha256sum
    do

        if command -v "$c" >/dev/null 2>&1; then
            printf '%-12s OK\n' "$c"
        else
            printf '%-12s MISSING\n' "$c"
        fi
    done

    printf '\n--- llama executable ---\n'

    if llama_exists; then

        printf 'resolved=%s\n' "$LLAMA_BIN"

        "$LLAMA_BIN" \
            --version \
            2>&1 ||
            true

    else

        printf 'MISSING\n'

        printf '\nSearch candidates:\n'

        find \
            "$HOME" \
            /home/linuxbrew \
            /usr/local \
            /usr \
            -type f \
            -name llama \
            -perm -111 \
            2>/dev/null |
            head -50
    fi

    printf '\n--- server health ---\n'

    if server_health >/dev/null 2>&1; then
        printf 'READY\n'
    else
        printf 'OFFLINE\n'
    fi

    printf '\n--- architecture ---\n'

    uname -m 2>/dev/null || true

    printf '\n--- cpu ---\n'

    if [[ -r /proc/cpuinfo ]]; then

        printf \
            'logical_cpus=%s\n' \
            "$(grep -c '^processor' /proc/cpuinfo || true)"
    fi

    printf '\n--- memory ---\n'

    if command -v free >/dev/null 2>&1; then
        free -h
    fi
}

# -----------------------------------------------------------------------------
# MANIFEST
# -----------------------------------------------------------------------------

manifest() {

    jq -cn \
        --arg name "$NAME" \
        --arg version "$VERSION" \
        --arg root "$ROOT" \
        --arg llama "$LLAMA_BIN" \
        --arg server "$LLAMA_BASE_URL" \
        --arg model "$MODEL" \
        --arg workflow \
            'INPUT -> ANALYZE -> DECIDE -> EXECUTE -> OBSERVE -> UPDATE -> REPEAT' \
        '{
            name:$name,
            version:$version,
            root:$root,
            llama_bin:$llama,
            server:$server,
            model:$model,
            workflow:$workflow,

            invariants:[
                "no eval on prompt text",
                "no automatic execution of generated code",
                "workspace-confined file operations",
                "SHA-256 integrity/provenance identifier",
                "MD5 legacy provenance only"
            ],

            backends:[
                "llama-server",
                "llama-cli",
                "ollama-compatible"
            ]
        }'
}

# -----------------------------------------------------------------------------
# OLLAMA COMPATIBILITY
# -----------------------------------------------------------------------------

ollama_chat() {

    local prompt="$1"
    local model="${2:-$FALLBACK_MODEL}"

    local host="${OLLAMA_HOST:-127.0.0.1:11434}"

    need_cmd curl
    need_cmd jq

    curl \
        --fail \
        --silent \
        --show-error \
        --max-time "$TIMEOUT" \
        -H 'Content-Type: application/json' \
        -d "$(
            jq -cn \
                --arg model "$model" \
                --arg prompt "$prompt" \
                '{
                    model:$model,
                    prompt:$prompt,
                    stream:false
                }'
        )" \
        "http://${host}/api/generate" |
    jq -r '.response // empty'
}

# -----------------------------------------------------------------------------
# NATIVE LLAMA
# -----------------------------------------------------------------------------

native() {

    require_llama

    "$LLAMA_BIN" "$@"
}

# -----------------------------------------------------------------------------
# HELP
# -----------------------------------------------------------------------------

help_text() {

    cat <<EOF

$NAME $VERSION

PROMPT:

  ai.sh "prompt"

  ai.sh run "prompt"

  ai.sh repl

  ai.sh consensus "prompt" 3

REGEX CONTROLS:

  @model=MODEL
  @ctx=N
  @threads=N
  @gpu_layers=N
  @batch=N
  @ubatch=N

  @temp=N
  @top_p=N
  @top_k=N
  @repeat_penalty=N

  @n_predict=N

  @views=N
  @synthesis=true|false
  @parallel=0|1

  @session=NAME

  @server=auto|server|cli
  @cli=0|1

SERVER:

  ai.sh server start
  ai.sh server stop
  ai.sh server restart
  ai.sh server status
  ai.sh server logs

  ai.sh health
  ai.sh models

STATE:

  ai.sh genesis
  ai.sh status
  ai.sh doctor
  ai.sh manifest

  ai.sh index [PATH]
  ai.sh rank TEXT
  ai.sh entropy TEXT
  ai.sh trace
  ai.sh memory
  ai.sh events

FILES:

  ai.sh read PATH
  ai.sh create PATH < FILE
  ai.sh update PATH < FILE
  ai.sh delete PATH

NATIVE LLAMA:

  ai.sh llama ...
  ai.sh cli ...

  ai.sh serve ...
  ai.sh download ...
  ai.sh update ...
  ai.sh completion ...
  ai.sh licenses ...

OLLAMA:

  ai.sh ollama "prompt" [model]

EXAMPLES:

  ai.sh "Explain the architecture"

  ai.sh \
      @views=4 \
      @synthesis=true \
      "Review this controller"

  ai.sh \
      --context README.md src/main.js \
      "Analyze the implementation"

  ai.sh \
      --project demo \
      "Generate a bash utility"

  ai.sh \
      consensus \
      "Design a fault tolerant local AI runtime" \
      3

EOF
}

# -----------------------------------------------------------------------------
# DISPATCHER
# -----------------------------------------------------------------------------

main() {

    local command="${1:-}"

    case "$command" in

        "")
            help_text
            ;;

        help|-h|--help)
            help_text
            ;;

        version|--version)
            printf '%s\n' "$VERSION"
            ;;

        status)
            status
            ;;

        doctor)
            doctor
            ;;

        manifest)
            manifest
            ;;

        genesis)
            genesis
            ;;

        health)
            server_health
            ;;

        models)
            server_models
            ;;

        server)

            shift

            case "${1:-status}" in

                start)
                    shift
                    server_start "$@"
                    ;;

                stop)
                    shift
                    server_stop "$@"
                    ;;

                restart)
                    shift
                    server_restart "$@"
                    ;;

                status)
                    shift
                    server_status "$@"
                    ;;

                logs)
                    shift
                    server_logs "${1:-120}"
                    ;;

                *)
                    die \
                        "usage: server {start|stop|restart|status|logs}"
                    ;;
            esac
            ;;

        repl)
            repl
            ;;

        parse)

            shift

            local raw="$*"

            parse_prompt "$raw"

            jq -cn \
                --arg model "$PARSE_MODEL" \
                --arg ctx "$PARSE_CTX" \
                --arg threads "$PARSE_THREADS" \
                --arg gpu "$PARSE_GPU_LAYERS" \
                --arg batch "$PARSE_BATCH" \
                --arg ubatch "$PARSE_UBATCH" \
                --arg temp "$PARSE_TEMP" \
                --arg top_p "$PARSE_TOP_P" \
                --arg top_k "$PARSE_TOP_K" \
                --arg repeat "$PARSE_REPEAT" \
                --arg predict "$PARSE_N_PREDICT" \
                --arg views "$PARSE_VIEWS" \
                --arg synthesis "$PARSE_SYNTHESIS" \
                --arg parallel "$PARSE_PARALLEL" \
                --arg session "$PARSE_SESSION" \
                --arg server "$PARSE_SERVER" \
                --arg cli "$PARSE_CLI" \
                '{
                    model:$model,
                    ctx:$ctx,
                    threads:$threads,
                    gpu_layers:$gpu,
                    batch:$batch,
                    ubatch:$ubatch,
                    temp:$temp,
                    top_p:$top_p,
                    top_k:$top_k,
                    repeat_penalty:$repeat,
                    n_predict:$predict,
                    views:$views,
                    synthesis:$synthesis,
                    parallel:$parallel,
                    session:$session,
                    server:$server,
                    cli:$cli
                }'
            ;;

        rank)

            shift

            rank_text "$*"
            ;;

        entropy)

            shift

            entropy_text "$*"
            ;;

        index)

            shift

            index_path "${1:-$ROOT}"
            ;;

        trace)

            if [[ -n "${2:-}" ]]; then
                grep "$2" "$TRACE_DB" || true
            else
                tail -n 100 "$TRACE_DB"
            fi
            ;;

        memory)

            tail -n 100 "$MEMORY_DB"
            ;;

        events)

            tail -n 100 "$EVENTS_DB"
            ;;

        read)

            [[ -n "${2:-}" ]] ||
                die "usage: read PATH"

            crud_read "$2"
            ;;

        create)

            [[ -n "${2:-}" ]] ||
                die "usage: create PATH"

            crud_create "$2"
            ;;

        update)

            [[ -n "${2:-}" ]] ||
                die "usage: update PATH"

            crud_update "$2"
            ;;

        delete)

            [[ -n "${2:-}" ]] ||
                die "usage: delete PATH"

            crud_delete "$2"
            ;;

        ollama)

            shift

            local ollama_prompt="$*"

            [[ -n "$ollama_prompt" ]] ||
                die "ollama prompt is empty"

            ollama_chat \
                "$ollama_prompt" \
                "$FALLBACK_MODEL"
            ;;

        llama)

            shift

            native "$@"
            ;;

        cli)

            shift

            require_llama

            "$LLAMA_BIN" \
                cli \
                "$@"
            ;;

        download|update|completion|licenses|serve)

            shift

            native \
                "$command" \
                "$@"
            ;;

        run|prompt)

            shift

            local context=""
            local project=""
            local consensus_rounds=""
            local system_override=""

            local -a prompt_parts=()

            while (($#)); do

                case "$1" in

                    --model)
                        MODEL="$2"
                        shift 2
                        ;;

                    --ctx)
                        CTX="$2"
                        shift 2
                        ;;

                    --threads)
                        THREADS="$2"
                        shift 2
                        ;;

                    --gpu-layers)
                        GPU_LAYERS="$2"
                        shift 2
                        ;;

                    --batch)
                        BATCH="$2"
                        shift 2
                        ;;

                    --ubatch)
                        UBATCH="$2"
                        shift 2
                        ;;

                    --temp)
                        TEMP="$2"
                        shift 2
                        ;;

                    --top-p)
                        TOP_P="$2"
                        shift 2
                        ;;

                    --top-k)
                        TOP_K="$2"
                        shift 2
                        ;;

                    --repeat)
                        REPEAT="$2"
                        shift 2
                        ;;

                    --n-predict)
                        N_PREDICT="$2"
                        shift 2
                        ;;

                    --views)
                        VIEWS="$2"
                        shift 2
                        ;;

                    --synthesis)
                        SYNTHESIS=true
                        shift
                        ;;

                    --parallel)
                        PARALLEL=1
                        shift
                        ;;

                    --session)
                        SESSION="$2"
                        shift 2
                        ;;

                    --system)
                        system_override="$2"
                        shift 2
                        ;;

                    --context)

                        shift

                        while (($#)) &&
                              [[ "$1" != --* ]]
                        do

                            context+="${context:+ }$1"

                            shift
                        done
                        ;;

                    --project)
                        project="$2"
                        shift 2
                        ;;

                    --consensus)
                        consensus_rounds="$2"
                        shift 2
                        ;;

                    --)

                        shift

                        prompt_parts+=("$@")

                        break
                        ;;

                    *)
                        prompt_parts+=("$1")
                        shift
                        ;;

                esac
            done

            local prompt="${prompt_parts[*]:-}"

            [[ -n "$prompt" ]] ||
                die "prompt is empty"

            if [[ -n "$system_override" ]]; then
                SYSTEM_PROMPT="$system_override"
            fi

            if [[ -n "$consensus_rounds" ]]; then

                consensus \
                    "$prompt" \
                    "$consensus_rounds" \
                    "$project"

            else

                run_one \
                    "$prompt" \
                    "$context" \
                    "$project"

            fi
            ;;

        consensus)

            shift

            local cprompt="$*"

            [[ -n "$cprompt" ]] ||
                die "consensus prompt is empty"

            consensus \
                "$cprompt" \
                "${AI_CONSENSUS_ROUNDS:-3}" \
                ""
            ;;

        *)

            # Bare arguments are natural-language prompt text.
            run_one "$*"
            ;;

    esac
}

main "$@"
