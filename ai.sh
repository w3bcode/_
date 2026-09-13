#!/usr/bin/env bash
# =============================================================================
# ai.sh v16.0.0
# =============================================================================
# Single-file local AI controller for llama.cpp (llama-cli), tuned for
# proot-distro Debian on Android with modest RAM (~16GB or less).
#
# Runtime:
#   $HOME/.local/bin/llama   (override with LLAMA_CLI)
#
# Architecture:
#
#   prompt
#      |
#      v
#   normalization
#      |
#      v
#   genesis SHA-256
#      |
#      v
#   task hash
#      |
#      v
#   2PI / 8 POV multiview  (sequential — safe for constrained RAM)
#      |
#      +---- analytical
#      +---- architectural
#      +---- critical
#      +---- creative
#      +---- implementation
#      +---- adversarial
#      +---- systems
#      +---- synthesis
#      |
#      v
#   candidate scoring
#      |
#      v
#   convergence / consensus
#      |
#      v
#   optional synthesis
#      |
#      v
#   recursive continuation
#      |
#      v
#   SHA-256 content-addressed ledger  (JSON, $OBJECT_DIR)
#      |
#      v
#   sandboxed file CRUD + queryable index  ($FILE_ROOT, $DB_DIR/file_index.json)
#
# Model policy:
#
#   PRIMARY
#     Qwen2.5-Coder-3B-Instruct Q4_K_M
#
#   FALLBACK
#     Qwen2.5-1.5B-Instruct Q4_K_M
#
# IMPORTANT:
#   - Logical model identifiers are NEVER passed to llama.
#     Only verified physical GGUF files are passed through --model.
#   - "ai file" CRUD operations are sandboxed under FILE_ROOT by default.
#     See `ai help` / FILE ACCESS section for how to opt out.
#
# Requires: bash, awk, sed, grep, find, sort, jq, bc, sha256sum (or shasum),
#           curl (only for `ai install`). All are standard on Debian/apt.
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

# =============================================================================
# VERSION
# =============================================================================

AI_VERSION="16.0.0"

# =============================================================================
# BASE PATHS
# =============================================================================

AI_HOME="${AI_HOME:-${HOME:-/root}/.ai}"
HOME_DIR="${HOME:-/root}"

STATE_DIR="${AI_STATE_DIR:-$AI_HOME/.ai-state}"

CACHE_DIR="${AI_CACHE_DIR:-$STATE_DIR/cache}"
LOG_DIR="${AI_LOG_DIR:-$STATE_DIR/logs}"
DB_DIR="${AI_DB:-$STATE_DIR/db}"
OBJECT_DIR="${AI_OBJECTS:-$DB_DIR/objects}"
REFERENCE_DIR="${AI_REFERENCE:-$DB_DIR/reference}"
RUN_DIR="${AI_RUN_DIR:-$STATE_DIR/run}"
SESSION_DIR="${AI_SESSION_DIR:-$STATE_DIR/sessions}"

MODEL_DIR="${AI_MODEL_DIR:-$AI_HOME/models}"

mkdir -p \
    "$STATE_DIR" \
    "$CACHE_DIR" \
    "$LOG_DIR" \
    "$DB_DIR" \
    "$OBJECT_DIR" \
    "$REFERENCE_DIR" \
    "$RUN_DIR" \
    "$SESSION_DIR" \
    "$MODEL_DIR"

# =============================================================================
# RUNTIME
# =============================================================================

LLAMA_CLI="${LLAMA_CLI:-${HOME:-/root}/.local/bin/llama}"

# =============================================================================
# MODEL IDENTITIES
# =============================================================================

AI_MODEL="${AI_MODEL:-Qwen/Qwen2.5-Coder-3B-Instruct-GGUF:Q4_K_M}"
AI_CODER="${AI_CODER:-$AI_MODEL}"
AI_FALLBACK="${AI_FALLBACK:-Qwen/Qwen2.5-1.5B-Instruct-GGUF:Q4_K_M}"

# Physical overrides.
AI_MODEL_PATH="${AI_MODEL_PATH:-}"
AI_FALLBACK_PATH="${AI_FALLBACK_PATH:-}"

# Local filenames.
AI_PRIMARY_FILE="${AI_PRIMARY_FILE:-qwen2.5-coder-3b-instruct-q4_k_m.gguf}"
AI_FALLBACK_FILE="${AI_FALLBACK_FILE:-qwen2.5-1.5b-instruct-q4_k_m.gguf}"

PRIMARY_LOCAL_PATH="$MODEL_DIR/$AI_PRIMARY_FILE"
FALLBACK_LOCAL_PATH="$MODEL_DIR/$AI_FALLBACK_FILE"

# HF cache.
AI_HF_ROOT="${AI_HF_ROOT:-$HOME_DIR/.cache/huggingface/hub}"

PRIMARY_HF_CACHE="$AI_HF_ROOT/models--Qwen--Qwen2.5-Coder-3B-Instruct-GGUF"
FALLBACK_HF_CACHE="$AI_HF_ROOT/models--Qwen--Qwen2.5-1.5B-Instruct-GGUF"

# HF repositories.
PRIMARY_HF_REPO="Qwen/Qwen2.5-Coder-3B-Instruct-GGUF"
FALLBACK_HF_REPO="Qwen/Qwen2.5-1.5B-Instruct-GGUF"

# =============================================================================
# RUNTIME PARAMETERS
# =============================================================================

AI_CONTEXT="${AI_CONTEXT:-${AI_CTX:-4096}}"
AI_BATCH="${AI_BATCH:-${AI_BATCH_SIZE:-256}}"
AI_UBATCH="${AI_UBATCH:-${AI_UBATCH_SIZE:-128}}"
AI_PREDICT="${AI_PREDICT:-${AI_N_PREDICT:-512}}"

AI_THREADS="${AI_THREADS:-8}"
AI_GPU_LAYERS="${AI_GPU_LAYERS:-0}"

AI_TEMPERATURE="${AI_TEMPERATURE:-${AI_TEMP:-0.65}}"
AI_TOP_K="${AI_TOP_K:-40}"
AI_TOP_P="${AI_TOP_P:-0.95}"
AI_REPEAT_PENALTY="${AI_REPEAT_PENALTY:-1.10}"

AI_TIMEOUT="${AI_TIMEOUT:-600}"

# =============================================================================
# ORCHESTRATION
# =============================================================================

AI_VIEWS="${AI_VIEWS:-8}"
AI_DEPTH="${AI_DEPTH:-1}"

AI_SYNTHESIS="${AI_SYNTHESIS:-false}"
AI_STREAM="${AI_STREAM:-false}"

AI_SESSION="${AI_SESSION:-default}"

# Minimum useful answer length.
AI_MIN_OUTPUT="${AI_MIN_OUTPUT:-8}"

# Candidate scoring weights.
AI_SCORE_LENGTH="${AI_SCORE_LENGTH:-0.20}"
AI_SCORE_STRUCTURE="${AI_SCORE_STRUCTURE:-0.20}"
AI_SCORE_DIRECTNESS="${AI_SCORE_DIRECTNESS:-0.20}"
AI_SCORE_HASH="${AI_SCORE_HASH:-0.10}"
AI_SCORE_COMPLETENESS="${AI_SCORE_COMPLETENESS:-0.30}"

# =============================================================================
# COLORS
# =============================================================================

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_MAGENTA=$'\033[35m'
    C_CYAN=$'\033[36m'
    C_WHITE=$'\033[37m'
    C_DIM=$'\033[2m'
else
    C_RESET=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_BLUE=""
    C_MAGENTA=""
    C_CYAN=""
    C_WHITE=""
    C_DIM=""
fi

# =============================================================================
# GLOBALS
# =============================================================================

CURRENT_MODEL_PATH=""
CURRENT_MODEL_NAME=""
CURRENT_MODEL_TIER=""

LAST_OUTPUT=""
LAST_ERROR=""
LAST_EXIT_CODE=0

GENESIS_HASH=""
TASK_HASH=""
CURRENT_HASH=""

POV_INDEX=0
POV_NAME=""
POV_ANGLE=""

LLAMA_HELP_CACHE=""

declare -a LLAMA_CMD=()
declare -a CANDIDATE_FILES=()
declare -a CANDIDATE_SCORES=()
declare -a CANDIDATE_HASHES=()

# =============================================================================
# CLEANUP
# =============================================================================

TMP_FILES=()

cleanup() {
    local f

    for f in "${TMP_FILES[@]:-}"; do
        [[ -n "$f" ]] || continue
        [[ -f "$f" ]] && rm -f -- "$f" || true
    done
}

trap cleanup EXIT
trap 'printf "\n[INTERRUPTED]\n" >&2; exit 130' INT TERM

# =============================================================================
# ERROR HANDLER
# =============================================================================

on_error() {
    local rc=$?
    local line="${BASH_LINENO[0]:-unknown}"
    local cmd="${BASH_COMMAND:-unknown}"

    printf '%s[ERROR]%s line=%s rc=%s\n' \
        "$C_RED" "$C_RESET" "$line" "$rc" >&2

    printf '%sCOMMAND:%s %s\n' \
        "$C_DIM" "$C_RESET" "$cmd" >&2

    exit "$rc"
}

trap on_error ERR

# =============================================================================
# BASIC UTILITIES
# =============================================================================

die() {
    printf '%s[ERROR]%s %s\n' \
        "$C_RED" "$C_RESET" "$*" >&2
    exit 1
}

warn() {
    printf '%s[WARN]%s %s\n' \
        "$C_YELLOW" "$C_RESET" "$*" >&2
}

info() {
    printf '%s[AI]%s %s\n' \
        "$C_CYAN" "$C_RESET" "$*"
}

ok() {
    printf '%s[OK]%s %s\n' \
        "$C_GREEN" "$C_RESET" "$*"
}

debug() {
    [[ "${AI_VERBOSE:-false}" == "true" ]] || return 0

    printf '%s[DEBUG]%s %s\n' \
        "$C_DIM" "$C_RESET" "$*" >&2
}

have() {
    command -v "$1" >/dev/null 2>&1
}

now_ms() {
    if date +%s%3N >/dev/null 2>&1; then
        date +%s%3N
    else
        printf '%s000\n' "$(date +%s)"
    fi
}

now_iso() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# =============================================================================
# VALIDATION
# =============================================================================

is_uint() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

require_uint() {
    local name="$1"
    local value="$2"

    is_uint "$value" || die "$name must be an unsigned integer: $value"
}

validate_config() {
    require_uint AI_CONTEXT "$AI_CONTEXT"
    require_uint AI_BATCH "$AI_BATCH"
    require_uint AI_UBATCH "$AI_UBATCH"
    require_uint AI_PREDICT "$AI_PREDICT"
    require_uint AI_THREADS "$AI_THREADS"
    require_uint AI_TIMEOUT "$AI_TIMEOUT"
    require_uint AI_VIEWS "$AI_VIEWS"
    require_uint AI_DEPTH "$AI_DEPTH"

    (( AI_CONTEXT > 0 )) || die "AI_CONTEXT must be > 0"
    (( AI_BATCH > 0 )) || die "AI_BATCH must be > 0"
    (( AI_UBATCH > 0 )) || die "AI_UBATCH must be > 0"
    (( AI_PREDICT > 0 )) || die "AI_PREDICT must be > 0"
    (( AI_THREADS > 0 )) || die "AI_THREADS must be > 0"
    (( AI_VIEWS >= 1 && AI_VIEWS <= 8 )) ||
        die "AI_VIEWS must be between 1 and 8"

    (( AI_DEPTH >= 1 && AI_DEPTH <= 32 )) ||
        die "AI_DEPTH must be between 1 and 32"
}

# =============================================================================
# HASHING
# =============================================================================

sha256_string() {
    local text="$1"

    if have sha256sum; then
        printf '%s' "$text" |
            sha256sum |
            awk '{print $1}'
        return
    fi

    if have shasum; then
        printf '%s' "$text" |
            shasum -a 256 |
            awk '{print $1}'
        return
    fi

    die "sha256sum or shasum is required"
}

sha256_file() {
    local file="$1"

    [[ -f "$file" ]] || return 1

    if have sha256sum; then
        sha256sum "$file" |
            awk '{print $1}'
        return
    fi

    if have shasum; then
        shasum -a 256 "$file" |
            awk '{print $1}'
        return
    fi

    die "sha256sum or shasum is required"
}

# =============================================================================
# JSON ESCAPE
# =============================================================================

json_escape() {
    local s="$1"

    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"

    printf '%s' "$s"
}

# =============================================================================
# FILE UTILITIES
# =============================================================================

safe_tmp() {
    local prefix="${1:-ai}"

    local tmp

    if have mktemp; then
        tmp="$(mktemp "$RUN_DIR/${prefix}.XXXXXX")"
    else
        tmp="$RUN_DIR/${prefix}.$$.$RANDOM"
        : > "$tmp"
    fi

    TMP_FILES+=("$tmp")

    printf '%s\n' "$tmp"
}

# =============================================================================
# GGUF VALIDATION
# =============================================================================

is_valid_gguf() {
    local file="$1"
    local magic=""

    [[ -f "$file" ]] || return 1
    [[ -s "$file" ]] || return 1

    magic="$(
        head -c 4 "$file" 2>/dev/null |
        LC_ALL=C od -An -tc |
        tr -d '[:space:]'
    )"

    [[ "$magic" == "GGUF" ]]
}

verify_gguf() {
    local file="$1"

    if ! is_valid_gguf "$file"; then
        warn "Invalid GGUF: $file"
        return 1
    fi

    return 0
}

# =============================================================================
# MODEL DISCOVERY
# =============================================================================

find_exact_gguf() {
    local root="$1"
    local filename="$2"

    [[ -d "$root" ]] || return 1

    find "$root" \
        -type f \
        -iname "$filename" \
        -print \
        -quit \
        2>/dev/null
}

find_any_gguf() {
    local root="$1"

    [[ -d "$root" ]] || return 1

    find "$root" \
        -type f \
        \( -iname '*.gguf' -o -iname '*.GGUF' \) \
        -print \
        2>/dev/null |
        sort |
        head -n 1
}

# =============================================================================
# PRIMARY MODEL
# =============================================================================

find_primary_model() {
    local model=""

    # Explicit path.
    if [[ -n "$AI_MODEL_PATH" &&
          -f "$AI_MODEL_PATH" &&
          -s "$AI_MODEL_PATH" ]]; then

        verify_gguf "$AI_MODEL_PATH" || return 1

        printf '%s\n' "$AI_MODEL_PATH"
        return 0
    fi

    # Dedicated local registry.
    if [[ -f "$PRIMARY_LOCAL_PATH" ]]; then
        if verify_gguf "$PRIMARY_LOCAL_PATH"; then
            printf '%s\n' "$PRIMARY_LOCAL_PATH"
            return 0
        fi
    fi

    # Another matching local GGUF.
    model="$(
        find_exact_gguf \
            "$MODEL_DIR" \
            "$AI_PRIMARY_FILE" ||
            true
    )"

    if [[ -n "$model" && -f "$model" ]]; then
        if verify_gguf "$model"; then
            printf '%s\n' "$model"
            return 0
        fi
    fi

    # HF cache.
    model="$(
        find_exact_gguf \
            "$PRIMARY_HF_CACHE" \
            "$AI_PRIMARY_FILE" ||
            true
    )"

    if [[ -n "$model" && -f "$model" ]]; then
        if verify_gguf "$model"; then
            printf '%s\n' "$model"
            return 0
        fi
    fi

    # Any GGUF in primary repository cache.
    model="$(
        find_any_gguf "$PRIMARY_HF_CACHE" ||
        true
    )"

    if [[ -n "$model" && -f "$model" ]]; then
        if verify_gguf "$model"; then
            printf '%s\n' "$model"
            return 0
        fi
    fi

    return 1
}

# =============================================================================
# FALLBACK MODEL
# =============================================================================

find_fallback_model() {
    local model=""

    # Explicit path.
    if [[ -n "$AI_FALLBACK_PATH" &&
          -f "$AI_FALLBACK_PATH" &&
          -s "$AI_FALLBACK_PATH" ]]; then

        verify_gguf "$AI_FALLBACK_PATH" || return 1

        printf '%s\n' "$AI_FALLBACK_PATH"
        return 0
    fi

    # Dedicated local registry.
    if [[ -f "$FALLBACK_LOCAL_PATH" ]]; then
        if verify_gguf "$FALLBACK_LOCAL_PATH"; then
            printf '%s\n' "$FALLBACK_LOCAL_PATH"
            return 0
        fi
    fi

    model="$(
        find_exact_gguf \
            "$MODEL_DIR" \
            "$AI_FALLBACK_FILE" ||
            true
    )"

    if [[ -n "$model" && -f "$model" ]]; then
        if verify_gguf "$model"; then
            printf '%s\n' "$model"
            return 0
        fi
    fi

    # HF cache.
    model="$(
        find_exact_gguf \
            "$FALLBACK_HF_CACHE" \
            "$AI_FALLBACK_FILE" ||
            true
    )"

    if [[ -n "$model" && -f "$model" ]]; then
        if verify_gguf "$model"; then
            printf '%s\n' "$model"
            return 0
        fi
    fi

    model="$(
        find_any_gguf "$FALLBACK_HF_CACHE" ||
        true
    )"

    if [[ -n "$model" && -f "$model" ]]; then
        if verify_gguf "$model"; then
            printf '%s\n' "$model"
            return 0
        fi
    fi

    return 1
}

# =============================================================================
# MODEL RESOLUTION
# =============================================================================

resolve_model() {
    local model=""

    CURRENT_MODEL_PATH=""
    CURRENT_MODEL_NAME=""
    CURRENT_MODEL_TIER=""

    model="$(find_primary_model || true)"

    if [[ -n "$model" && -f "$model" ]]; then
        CURRENT_MODEL_PATH="$model"
        CURRENT_MODEL_NAME="$(basename "$model")"
        CURRENT_MODEL_TIER="primary"

        printf '%s\n' "$model"
        return 0
    fi

    model="$(find_fallback_model || true)"

    if [[ -n "$model" && -f "$model" ]]; then
        CURRENT_MODEL_PATH="$model"
        CURRENT_MODEL_NAME="$(basename "$model")"
        CURRENT_MODEL_TIER="fallback"

        printf '%s\n' "$model"
        return 0
    fi

    return 1
}

# =============================================================================
# RUNTIME CAPABILITIES
# =============================================================================

check_runtime() {
    [[ -x "$LLAMA_CLI" ]] || {
        LAST_ERROR="llama runtime is not executable: $LLAMA_CLI"
        return 127
    }

    return 0
}

llama_help() {
    if [[ -z "$LLAMA_HELP_CACHE" ]]; then
        LLAMA_HELP_CACHE="$(
            "$LLAMA_CLI" --help 2>&1 ||
            true
        )"
    fi

    printf '%s\n' "$LLAMA_HELP_CACHE"
}

llama_supports() {
    local option="$1"

    llama_help |
        grep -Eq -- \
            "(^|[[:space:]])${option}([=[:space:]]|,|$)"
}

# =============================================================================
# BUILD LLAMA COMMAND
# =============================================================================

build_llama_command() {
    local model="$1"

    # HARD MODEL INVARIANT.
    [[ -n "$model" ]] || {
        LAST_ERROR="empty model path"
        return 2
    }

    [[ -f "$model" ]] || {
        LAST_ERROR="model does not exist: $model"
        return 2
    }

    [[ -s "$model" ]] || {
        LAST_ERROR="model is empty: $model"
        return 2
    }

    verify_gguf "$model" || {
        LAST_ERROR="invalid GGUF: $model"
        return 2
    }

    LLAMA_CMD=(
        "$LLAMA_CLI"
        --model "$model"
    )

    # Context.
    if llama_supports '--ctx-size'; then
        LLAMA_CMD+=(--ctx-size "$AI_CONTEXT")
    elif llama_supports '-c'; then
        LLAMA_CMD+=(-c "$AI_CONTEXT")
    fi

    # Batch.
    if llama_supports '--batch-size'; then
        LLAMA_CMD+=(--batch-size "$AI_BATCH")
    elif llama_supports '-b'; then
        LLAMA_CMD+=(-b "$AI_BATCH")
    fi

    # UBatch.
    if llama_supports '--ubatch-size'; then
        LLAMA_CMD+=(--ubatch-size "$AI_UBATCH")
    fi

    # Prediction.
    if llama_supports '--predict'; then
        LLAMA_CMD+=(--predict "$AI_PREDICT")
    elif llama_supports '-n'; then
        LLAMA_CMD+=(-n "$AI_PREDICT")
    fi

    # Threads.
    if llama_supports '--threads'; then
        LLAMA_CMD+=(--threads "$AI_THREADS")
    elif llama_supports '-t'; then
        LLAMA_CMD+=(-t "$AI_THREADS")
    fi

    # Temperature.
    if llama_supports '--temp'; then
        LLAMA_CMD+=(--temp "$AI_TEMPERATURE")
    fi

    # Top K.
    if llama_supports '--top-k'; then
        LLAMA_CMD+=(--top-k "$AI_TOP_K")
    fi

    # Top P.
    if llama_supports '--top-p'; then
        LLAMA_CMD+=(--top-p "$AI_TOP_P")
    fi

    # Repeat penalty.
    if llama_supports '--repeat-penalty'; then
        LLAMA_CMD+=(--repeat-penalty "$AI_REPEAT_PENALTY")
    fi

    # GPU.
    if [[ "$AI_GPU_LAYERS" != "0" ]]; then
        if llama_supports '--n-gpu-layers'; then
            LLAMA_CMD+=(--n-gpu-layers "$AI_GPU_LAYERS")
        elif llama_supports '-ngl'; then
            LLAMA_CMD+=(-ngl "$AI_GPU_LAYERS")
        fi
    fi

    return 0
}

# =============================================================================
# RAW LLAMA EXECUTION
# =============================================================================

run_llama() {
    local prompt="$1"
    local model="${2:-}"
    local output=""
    local rc=0
    local stderr_file=""

    LAST_OUTPUT=""
    LAST_ERROR=""
    LAST_EXIT_CODE=0

    check_runtime || {
        LAST_EXIT_CODE=$?
        return "$LAST_EXIT_CODE"
    }

    # Resolve automatically if model wasn't explicitly supplied.
    if [[ -z "$model" || ! -f "$model" ]]; then
        model="$(resolve_model || true)"
    fi

    # NEVER invoke llama with an unresolved model.
    if [[ -z "$model" || ! -f "$model" ]]; then
        LAST_ERROR="No physical GGUF model resolved."
        LAST_EXIT_CODE=2

        warn "$LAST_ERROR"
        warn "Model registry: $MODEL_DIR"
        warn "HF cache:      $AI_HF_ROOT"

        return 2
    fi

    verify_gguf "$model" || {
        LAST_ERROR="Resolved model is not a valid GGUF: $model"
        LAST_EXIT_CODE=2
        return 2
    }

    build_llama_command "$model" || {
        LAST_EXIT_CODE=$?
        return "$LAST_EXIT_CODE"
    }

    stderr_file="$(safe_tmp llama-stderr)"

    LLAMA_CMD+=(--prompt "$prompt")

    if [[ "${AI_VERBOSE:-false}" == "true" ]]; then
        printf '%sMODEL:%s %s\n' \
            "$C_DIM" "$C_RESET" "$model"

        printf '%sCOMMAND:%s' \
            "$C_DIM" "$C_RESET"

        printf ' %q' "${LLAMA_CMD[@]}"

        printf '\n'
    fi

    debug "executing llama"

    if have timeout; then
        output="$(
            timeout \
                "$AI_TIMEOUT" \
                "${LLAMA_CMD[@]}" \
                2>"$stderr_file"
        )"

        rc=$?
    else
        output="$(
            "${LLAMA_CMD[@]}" \
            2>"$stderr_file"
        )"

        rc=$?
    fi

    if [[ $rc -ne 0 ]]; then
        LAST_EXIT_CODE=$rc
        LAST_ERROR="$(cat "$stderr_file" 2>/dev/null || true)"

        [[ -n "$LAST_ERROR" ]] &&
            log_event "llama_error" \
                "$LAST_ERROR"

        return "$rc"
    fi

    LAST_OUTPUT="$output"
    LAST_EXIT_CODE=0

    printf '%s\n' "$output"

    return 0
}

# =============================================================================
# LOGGING / LEDGER
# =============================================================================

log_event() {
    local type="$1"
    local payload="${2:-}"
    local timestamp
    local hash
    local file

    timestamp="$(now_iso)"

    hash="$(
        sha256_string \
            "${timestamp}|${type}|${payload}"
    )"

    file="$OBJECT_DIR/$hash.json"

    cat > "$file" <<EOF
{
  "hash":"$(json_escape "$hash")",
  "timestamp":"$(json_escape "$timestamp")",
  "type":"$(json_escape "$type")",
  "payload":"$(json_escape "$payload")"
}
EOF

    printf '%s\n' "$hash"
}

write_artifact() {
    local kind="$1"
    local content="$2"
    local parent="${3:-}"
    local hash
    local file
    local meta

    hash="$(sha256_string "$content")"
    file="$OBJECT_DIR/$hash.txt"
    meta="$OBJECT_DIR/$hash.json"

    if [[ ! -f "$file" ]]; then
        printf '%s\n' "$content" > "$file"
    fi

    cat > "$meta" <<EOF
{
  "hash":"$(json_escape "$hash")",
  "kind":"$(json_escape "$kind")",
  "parent":"$(json_escape "$parent")",
  "created":"$(now_iso)",
  "file":"$(json_escape "$file")"
}
EOF

    printf '%s\n' "$hash"
}

# =============================================================================
# PROMPT NORMALIZATION
# =============================================================================

normalize_prompt() {
    local prompt="$1"

    # Normalize CRLF.
    prompt="${prompt//$'\r'/}"

    # Remove leading/trailing blank space without destroying internal newlines.
    prompt="$(
        printf '%s\n' "$prompt" |
        sed \
            -e ':a' \
            -e '/^[[:space:]]*$/{$d;N;ba' \
            -e '}' \
            -e 's/^[[:space:]]*//' \
            -e 's/[[:space:]]*$//'
    )"

    printf '%s' "$prompt"
}

# =============================================================================
# GENESIS
# =============================================================================

create_genesis() {
    local prompt="$1"
    local timestamp
    local material

    timestamp="$(now_iso)"

    material=$(
        cat <<EOF
AI_VERSION=$AI_VERSION
TIMESTAMP=$timestamp
MODEL=$AI_MODEL
PROMPT=$prompt
EOF
    )

    GENESIS_HASH="$(sha256_string "$material")"
    CURRENT_HASH="$GENESIS_HASH"

    log_event \
        "genesis" \
        "$material" >/dev/null

    printf '%s\n' "$GENESIS_HASH"
}

create_task_hash() {
    local prompt="$1"

    TASK_HASH="$(
        sha256_string \
            "${GENESIS_HASH}|${prompt}"
    )"

    CURRENT_HASH="$TASK_HASH"

    log_event \
        "task" \
        "genesis=$GENESIS_HASH task=$TASK_HASH prompt=$prompt" \
        >/dev/null

    printf '%s\n' "$TASK_HASH"
}

# =============================================================================
# 2PI / 8 POV
# =============================================================================

POV_NAMES=(
    "analytical"
    "architectural"
    "critical"
    "creative"
    "implementation"
    "adversarial"
    "systems"
    "synthesis"
)

POV_ANGLES=(
    "0"
    "45"
    "90"
    "135"
    "180"
    "225"
    "270"
    "315"
)

build_pov_prompt() {
    local original="$1"
    local index="$2"
    local name="${POV_NAMES[$index]}"
    local angle="${POV_ANGLES[$index]}"

    cat <<EOF
You are one node in a deterministic 2PI/8-POV reasoning controller.

TASK:
$original

VIEW:
$name

ANGULAR POSITION:
${angle} degrees

GENESIS:
$GENESIS_HASH

TASK HASH:
$TASK_HASH

You are NOT the final synthesizer.

Produce an independent, technically useful analysis from this POV.

Requirements:
1. Stay focused on the TASK.
2. Identify assumptions explicitly.
3. Separate facts from inference.
4. Preserve concrete implementation details.
5. Detect contradictions or missing requirements.
6. Prefer testable statements.
7. Do not discuss this orchestration protocol.
8. Do not claim to have executed tools you did not execute.
9. Return only the analysis for this POV.

POV-SPECIFIC OBJECTIVE:
$name
EOF
}

# =============================================================================
# CANDIDATE SCORING
# =============================================================================

count_words() {
    printf '%s\n' "$1" |
        awk '{n+=NF} END {print n+0}'
}

count_structure() {
    local text="$1"
    local score=0

    grep -Eq '(^|[[:space:]])(1\.|2\.|3\.|4\.|5\.|- |\* )' \
        <<< "$text" &&
        score=$((score + 1))

    grep -Eq '(^|[[:space:]])(because|therefore|however|implementation|solution|problem|constraint)' \
        <<< "$text" &&
        score=$((score + 1))

    grep -q ':' <<< "$text" &&
        score=$((score + 1))

    printf '%s\n' "$score"
}

count_directness() {
    local text="$1"
    local score=0

    grep -Eiq \
        '(answer|solution|implement|use|change|replace|run|configure|fix)' \
        <<< "$text" &&
        score=$((score + 1))

    (( ${#text} > 200 )) &&
        score=$((score + 1))

    printf '%s\n' "$score"
}

score_candidate() {
    local text="$1"
    local hash="$2"

    local words
    local structure
    local directness
    local completeness
    local length_score
    local hash_score
    local total

    words="$(count_words "$text")"
    structure="$(count_structure "$text")"
    directness="$(count_directness "$text")"

    if (( words >= 100 )); then
        length_score=100
    elif (( words >= 50 )); then
        length_score=80
    elif (( words >= 20 )); then
        length_score=60
    elif (( words >= 8 )); then
        length_score=30
    else
        length_score=0
    fi

    hash_score=$((16#${hash:0:2}))

    completeness="$(
        awk \
            -v x="$structure" \
            'BEGIN {
                if (x >= 2) {
                    printf "%d", 100
                } else {
                    printf "%d", x * 50
                }
            }'
    )"

    total="$(
        awk \
            -v l="$length_score" \
            -v s="$structure" \
            -v d="$directness" \
            -v h="$hash_score" \
            -v c="$completeness" \
            'BEGIN {
                structure_score = s * 33.3333
                direct_score = d * 50
                hash_score = h / 255 * 100
                total = l * 0.20 + structure_score * 0.20 + direct_score * 0.20 + hash_score * 0.10 + c * 0.30
                printf "%.3f", total
            }'
    )"

    printf '%s\n' "$total"
}

# =============================================================================
# SINGLE POV
# =============================================================================

run_pov() {
    local original="$1"
    local index="$2"

    local pov_prompt
    local output
    local hash
    local score
    local artifact

    POV_INDEX="$index"
    POV_NAME="${POV_NAMES[$index]}"
    POV_ANGLE="${POV_ANGLES[$index]}"

    pov_prompt="$(
        build_pov_prompt \
            "$original" \
            "$index"
    )"

    info "POV $((index + 1))/8 — $POV_NAME @ ${POV_ANGLE}°"

    output="$(
        run_llama "$pov_prompt"
    )" || {
        warn "POV failed: $POV_NAME"
        return 1
    }

    if [[ ${#output} -lt "$AI_MIN_OUTPUT" ]]; then
        warn "POV produced insufficient output: $POV_NAME"
        return 1
    fi

    hash="$(sha256_string "$output")"
    score="$(score_candidate "$output" "$hash")"

    artifact="$(
        write_artifact \
            "pov:$POV_NAME" \
            "$output" \
            "$TASK_HASH"
    )"

    CANDIDATE_FILES+=("$artifact")
    CANDIDATE_SCORES+=("$score")
    CANDIDATE_HASHES+=("$hash")

    log_event \
        "pov" \
        "task=$TASK_HASH pov=$POV_NAME angle=$POV_ANGLE hash=$hash score=$score" \
        >/dev/null

    printf '%s\n' "$output"
}

# =============================================================================
# BEST CANDIDATE
# =============================================================================

best_candidate_index() {
    local i
    local best=-1
    local best_score="-1"

    for i in "${!CANDIDATE_SCORES[@]}"; do

        if awk \
            -v a="${CANDIDATE_SCORES[$i]}" \
            -v b="$best_score" \
            'BEGIN {exit !(a > b)}'
        then
            best="$i"
            best_score="${CANDIDATE_SCORES[$i]}"
        fi

    done

    printf '%s\n' "$best"
}

get_candidate_text() {
    local artifact="$1"
    local file="$OBJECT_DIR/$artifact.txt"

    [[ -f "$file" ]] || return 1

    cat "$file"
}

# =============================================================================
# SYNTHESIS
# =============================================================================

synthesize_candidates() {
    local original="$1"

    local index
    local best
    local source
    local synthesis_prompt
    local output
    local hash

    if [[ "${AI_SYNTHESIS,,}" != "true" ]]; then
        best="$(best_candidate_index)"

        if [[ "$best" -ge 0 ]]; then
            get_candidate_text \
                "${CANDIDATE_FILES[$best]}"
        fi

        return 0
    fi

    synthesis_prompt=$(
        cat <<EOF
You are the synthesis node of a deterministic 2PI/8-POV reasoning process.

ORIGINAL TASK:
$original

GENESIS:
$GENESIS_HASH

TASK:
$TASK_HASH

CANDIDATES:
EOF

        for index in "${!CANDIDATE_FILES[@]}"; do
            source="$(
                get_candidate_text \
                    "${CANDIDATE_FILES[$index]}"
            )"

            cat <<EOF

--- CANDIDATE $((index + 1)) ---
POV: ${POV_NAMES[$index]}
ANGLE: ${POV_ANGLES[$index]} degrees
SCORE: ${CANDIDATE_SCORES[$index]}
HASH: ${CANDIDATE_HASHES[$index]}

$source
EOF
        done

        cat <<'EOF'

SYNTHESIS REQUIREMENTS:

1. Reconcile useful information across candidates.
2. Resolve contradictions explicitly.
3. Do not average incorrect claims.
4. Prefer concrete and testable implementation.
5. Preserve important constraints.
6. Remove redundant material.
7. Produce one coherent final answer.
8. Do not mention the POV machinery.
9. Do not claim execution that did not occur.
10. Return only the synthesized answer.
EOF
    )

    info "SYNTHESIS"

    output="$(
        run_llama "$synthesis_prompt"
    )" || {
        warn "Synthesis failed; using best candidate."
        best="$(best_candidate_index)"

        if [[ "$best" -ge 0 ]]; then
            get_candidate_text \
                "${CANDIDATE_FILES[$best]}"
        fi

        return 0
    }

    hash="$(sha256_string "$output")"

    write_artifact \
        "synthesis" \
        "$output" \
        "$TASK_HASH" >/dev/null

    log_event \
        "synthesis" \
        "task=$TASK_HASH hash=$hash" \
        >/dev/null

    printf '%s\n' "$output"
}

# =============================================================================
# ONE ORCHESTRATION ROUND
# =============================================================================

run_round() {
    local original="$1"
    local depth="$2"

    local i
    local output=""

    CANDIDATE_FILES=()
    CANDIDATE_SCORES=()
    CANDIDATE_HASHES=()

    info "ROUND $depth/$AI_DEPTH"

    for ((i = 0; i < AI_VIEWS; i++)); do
        if ! run_pov "$original" "$i" >/dev/null; then
            continue
        fi
    done

    if (( ${#CANDIDATE_FILES[@]} == 0 )); then
        die "All POV executions failed."
    fi

    output="$(
        synthesize_candidates \
            "$original"
    )"

    printf '%s\n' "$output"

    return 0
}

# =============================================================================
# RECURSIVE ENGINE
# =============================================================================

run_engine() {
    local prompt="$1"

    local normalized
    local depth
    local result
    local parent_hash

    normalized="$(normalize_prompt "$prompt")"

    [[ -n "$normalized" ]] ||
        die "empty prompt"

    validate_config

    check_runtime ||
        die "llama runtime unavailable: $LLAMA_CLI"

    create_genesis "$normalized" >/dev/null
    create_task_hash "$normalized" >/dev/null

    info "GENESIS $GENESIS_HASH"
    info "TASK    $TASK_HASH"

    parent_hash="$TASK_HASH"

    for ((depth = 1; depth <= AI_DEPTH; depth++)); do

        result="$(
            run_round \
                "$normalized" \
                "$depth"
        )"

        local result_hash
        result_hash="$(sha256_string "$result")"

        log_event \
            "round" \
            "depth=$depth parent=$parent_hash result=$result_hash" \
            >/dev/null

        write_artifact \
            "round:$depth" \
            "$result" \
            "$parent_hash" >/dev/null

        parent_hash="$result_hash"

        # Recursion:
        #
        # The result becomes the semantic state for the next round.
        #
        # Prevent unbounded prompt growth by wrapping it as a continuation.
        if (( depth < AI_DEPTH )); then
            normalized=$(
                cat <<EOF
Continue solving the following task using the previous result as state.

ORIGINAL TASK:
$prompt

PREVIOUS RESULT:
$result

Continuation requirements:
- identify unresolved issues
- correct contradictions
- improve implementation precision
- retain useful prior information
- produce a better candidate
EOF
            )

            create_task_hash "$normalized" >/dev/null
        fi
    done

    # Final answer.
    printf '%s\n' "$result"
}

# =============================================================================
# SESSION
# =============================================================================

session_file() {
    printf '%s/%s.log\n' \
        "$SESSION_DIR" \
        "${AI_SESSION//[^a-zA-Z0-9_.-]/_}"
}

append_session() {
    local role="$1"
    local text="$2"

    {
        printf '\n[%s] %s\n' \
            "$(now_iso)" \
            "$role"

        printf '%s\n' "$text"

    } >> "$(session_file)"
}

run_chat() {
    local prompt=""

    info "interactive session: $AI_SESSION"
    info "type /help for commands"
    info "type /exit to leave"

    while true; do
        printf '%s\n' '> '

        if ! IFS= read -r prompt; then
            printf '\n'
            break
        fi

        case "$prompt" in
            /exit|/quit)
                break
                ;;

            /help)
                printf '%s\n' \
                    '/exit  leave session' \
                    '/clear clear session log' \
                    '/status runtime status' \
                    '/models model status'
                ;;

            /clear)
                : > "$(session_file)"
                ok "session cleared"
                ;;

            /status)
                cmd_status
                ;;

            /models)
                cmd_models
                ;;

            "")
                continue
                ;;

            *)
                append_session user "$prompt"

                local response
                response="$(
                    run_engine "$prompt"
                )"

                append_session assistant "$response"

                printf '\n%s\n\n' "$response"
                ;;
        esac
    done
}

# =============================================================================
# MODEL INSTALLATION
# =============================================================================

check_disk_space() {
    local target_dir="$1"

    have df || return 0

    df -Pk "$target_dir" |
        awk 'NR==2 {print $4}'
}

download_with_curl() {
    local url="$1"
    local target="$2"
    local temp

    have curl ||
        die "curl is required for model installation"

    temp="$(
        mktemp \
            "$MODEL_DIR/.download.XXXXXX"
    )"

    TMP_FILES+=("$temp")

    info "Downloading model"
    printf 'URL    : %s\n' "$url"
    printf 'TARGET : %s\n' "$target"
    printf '\n'

    if ! curl \
        --fail \
        --location \
        --retry 5 \
        --retry-delay 3 \
        --connect-timeout 20 \
        --continue-at - \
        --output "$temp" \
        "$url"
    then
        rm -f "$temp"
        die "model download failed"
    fi

    verify_gguf "$temp" ||
        die "downloaded file is not a valid GGUF"

    # Atomic replacement.
    mv -f \
        "$temp" \
        "$target"

    ok "model installed: $target"
}

install_primary() {
    local url

    mkdir -p "$MODEL_DIR"

    if [[ -f "$PRIMARY_LOCAL_PATH" ]] &&
       verify_gguf "$PRIMARY_LOCAL_PATH"; then

        ok "primary model already installed"
        return 0
    fi

    url="https://huggingface.co/${PRIMARY_HF_REPO}/resolve/main/${AI_PRIMARY_FILE}"

    download_with_curl \
        "$url" \
        "$PRIMARY_LOCAL_PATH"
}

install_fallback() {
    local url

    mkdir -p "$MODEL_DIR"

    if [[ -f "$FALLBACK_LOCAL_PATH" ]] &&
       verify_gguf "$FALLBACK_LOCAL_PATH"; then

        ok "fallback model already installed"
        return 0
    fi

    url="https://huggingface.co/${FALLBACK_HF_REPO}/resolve/main/${AI_FALLBACK_FILE}"

    download_with_curl \
        "$url" \
        "$FALLBACK_LOCAL_PATH"
}

cmd_install() {
    local target="${1:-primary}"

    case "$target" in

        primary|coder)
            install_primary
            ;;

        fallback|small)
            install_fallback
            ;;

        all)
            install_primary
            install_fallback
            ;;

        *)
            die "usage: ai install primary|fallback|all"
            ;;
    esac
}

# =============================================================================
# MODEL COMMAND
# =============================================================================

cmd_models() {
    local primary=""
    local fallback=""

    primary="$(find_primary_model || true)"
    fallback="$(find_fallback_model || true)"

    printf '\n'
    printf '%sMODEL REGISTRY%s\n' \
        "$C_CYAN" "$C_RESET"

    printf '%s==============================%s\n' \
        "$C_DIM" "$C_RESET"

    printf 'Runtime:\n'
    printf '  %s\n' "$LLAMA_CLI"

    if [[ -x "$LLAMA_CLI" ]]; then
        printf '  status: READY\n'
    else
        printf '  status: MISSING\n'
    fi

    printf '\n'
    printf 'Model directory:\n'
    printf '  %s\n' "$MODEL_DIR"

    printf '\n'
    printf 'Logical primary:\n'
    printf '  %s\n' "$AI_MODEL"

    printf 'Logical fallback:\n'
    printf '  %s\n' "$AI_FALLBACK"

    printf '\n'
    printf 'PRIMARY\n'
    printf '  local: %s\n' "$PRIMARY_LOCAL_PATH"

    if [[ -n "$primary" ]]; then
        printf '  resolved: %s\n' "$primary"
        printf '  size: %s\n' \
            "$(du -h "$primary" | awk '{print $1}')"
    else
        printf '  resolved: NOT FOUND\n'
    fi

    printf '\n'
    printf 'FALLBACK\n'
    printf '  local: %s\n' "$FALLBACK_LOCAL_PATH"

    if [[ -n "$fallback" ]]; then
        printf '  resolved: %s\n' "$fallback"
        printf '  size: %s\n' \
            "$(du -h "$fallback" | awk '{print $1}')"
    else
        printf '  resolved: NOT FOUND\n'
    fi

    printf '\n'

    if [[ -n "$primary" ]]; then
        ok "PRIMARY MODEL READY"
    elif [[ -n "$fallback" ]]; then
        warn "PRIMARY MISSING — FALLBACK READY"
    else
        warn "NO GGUF MODEL FOUND"
        printf '\n'
        printf 'Install primary with:\n'
        printf '  ai install primary\n'
    fi

    printf '\n'
}

# =============================================================================
# STATUS
# =============================================================================

cmd_status() {
    local model=""

    model="$(resolve_model || true)"

    printf '\n'
    printf '%sAI STATUS%s\n' \
        "$C_CYAN" "$C_RESET"

    printf '%s==============================%s\n' \
        "$C_DIM" "$C_RESET"

    printf 'Version       : %s\n' "$AI_VERSION"
    printf 'Runtime       : %s\n' "$LLAMA_CLI"
    printf 'Model         : %s\n' "${model:-NONE}"
    printf 'Tier          : %s\n' "${CURRENT_MODEL_TIER:-NONE}"
    printf 'Context       : %s\n' "$AI_CONTEXT"
    printf 'Batch         : %s\n' "$AI_BATCH"
    printf 'UBatch        : %s\n' "$AI_UBATCH"
    printf 'Predict       : %s\n' "$AI_PREDICT"
    printf 'Threads       : %s\n' "$AI_THREADS"
    printf 'Temperature   : %s\n' "$AI_TEMPERATURE"
    printf 'Top-K         : %s\n' "$AI_TOP_K"
    printf 'Top-P         : %s\n' "$AI_TOP_P"
    printf 'Repeat        : %s\n' "$AI_REPEAT_PENALTY"
    printf 'POV views     : %s\n' "$AI_VIEWS"
    printf 'Depth         : %s\n' "$AI_DEPTH"
    printf 'Synthesis     : %s\n' "$AI_SYNTHESIS"
    printf 'Session       : %s\n' "$AI_SESSION"
    printf 'State         : %s\n' "$STATE_DIR"

    printf '\n'
}

# =============================================================================
# DOCTOR
# =============================================================================

cmd_doctor() {
    local model=""
    local version=""

    printf '\n'
    printf '%sAI RUNTIME DOCTOR%s\n' \
        "$C_CYAN" "$C_RESET"

    printf '%s==============================%s\n\n' \
        "$C_DIM" "$C_RESET"

    # Bash.
    printf 'Bash:\n'
    printf '  %s\n' "$BASH_VERSION"

    # Runtime.
    printf '\nRuntime:\n'
    printf '  path: %s\n' "$LLAMA_CLI"

    if [[ -x "$LLAMA_CLI" ]]; then
        ok "llama executable"
    else
        warn "llama executable missing"
    fi

    if [[ -x "$LLAMA_CLI" ]]; then
        version="$(
            "$LLAMA_CLI" --version 2>&1 |
            head -n 1 ||
            true
        )"

        printf '  version: %s\n' "$version"
    fi

    # Tools.
    printf '\nTools:\n'

    for tool in \
        awk \
        sed \
        grep \
        find \
        sort \
        head \
        tail \
        sha256sum \
        curl
    do
        if have "$tool"; then
            printf '  %-12s OK\n' "$tool"
        else
            printf '  %-12s MISSING\n' "$tool"
        fi
    done

    # Model.
    printf '\nModels:\n'

    model="$(resolve_model || true)"

    if [[ -n "$model" && -f "$model" ]]; then
        ok "GGUF resolved"
        printf '  tier: %s\n' "$CURRENT_MODEL_TIER"
        printf '  file: %s\n' "$model"
        printf '  size: %s\n' \
            "$(du -h "$model" | awk '{print $1}')"
    else
        warn "No GGUF model resolved"
        printf '  install: ai install primary\n'
    fi

    printf '\nConfiguration:\n'
    printf '  context     = %s\n' "$AI_CONTEXT"
    printf '  batch       = %s\n' "$AI_BATCH"
    printf '  ubatch      = %s\n' "$AI_UBATCH"
    printf '  predict     = %s\n' "$AI_PREDICT"
    printf '  threads     = %s\n' "$AI_THREADS"
    printf '  temperature = %s\n' "$AI_TEMPERATURE"
    printf '  top-k       = %s\n' "$AI_TOP_K"
    printf '  top-p       = %s\n' "$AI_TOP_P"
    printf '  repeat      = %s\n' "$AI_REPEAT_PENALTY"

    printf '\nOrchestration:\n'
    printf '  views       = %s\n' "$AI_VIEWS"
    printf '  depth       = %s\n' "$AI_DEPTH"
    printf '  synthesis   = %s\n' "$AI_SYNTHESIS"

    printf '\nState:\n'
    printf '  %s\n' "$STATE_DIR"

    printf '\n'
}

# =============================================================================
# CONFIG
# =============================================================================

cmd_config() {
    cat <<EOF

ai.sh $AI_VERSION

RUNTIME
  LLAMA_CLI=$LLAMA_CLI

MODEL
  AI_MODEL=$AI_MODEL
  AI_CODER=$AI_CODER
  AI_FALLBACK=$AI_FALLBACK
  AI_MODEL_DIR=$MODEL_DIR
  AI_MODEL_PATH=$AI_MODEL_PATH
  AI_FALLBACK_PATH=$AI_FALLBACK_PATH

PHYSICAL
  PRIMARY_LOCAL_PATH=$PRIMARY_LOCAL_PATH
  FALLBACK_LOCAL_PATH=$FALLBACK_LOCAL_PATH
  AI_HF_ROOT=$AI_HF_ROOT

INFERENCE
  AI_CONTEXT=$AI_CONTEXT
  AI_BATCH=$AI_BATCH
  AI_UBATCH=$AI_UBATCH
  AI_PREDICT=$AI_PREDICT
  AI_THREADS=$AI_THREADS
  AI_GPU_LAYERS=$AI_GPU_LAYERS
  AI_TEMPERATURE=$AI_TEMPERATURE
  AI_TOP_K=$AI_TOP_K
  AI_TOP_P=$AI_TOP_P
  AI_REPEAT_PENALTY=$AI_REPEAT_PENALTY
  AI_TIMEOUT=$AI_TIMEOUT

ORCHESTRATION
  AI_VIEWS=$AI_VIEWS
  AI_DEPTH=$AI_DEPTH
  AI_SYNTHESIS=$AI_SYNTHESIS
  AI_SESSION=$AI_SESSION

STATE
  STATE_DIR=$STATE_DIR
  CACHE_DIR=$CACHE_DIR
  LOG_DIR=$LOG_DIR
  DB_DIR=$DB_DIR
  OBJECT_DIR=$OBJECT_DIR
  RUN_DIR=$RUN_DIR
  SESSION_DIR=$SESSION_DIR

EOF
}

# =============================================================================
# HASH COMMAND
# =============================================================================

cmd_hash() {
    local input="$*"

    [[ -n "$input" ]] ||
        die "usage: ai hash TEXT"

    sha256_string "$input"
}

# =============================================================================
# FILE CRUD (sandboxed)
# =============================================================================
#
# All file operations are confined to FILE_ROOT by default. FILE_ROOT is a
# normal directory under AI_HOME, not a system path, so "full CRUD access"
# means the tool can freely create/read/update/delete its own working files
# (notes, generated code, session exports, etc.) without touching the rest
# of the phone/container.
#
# To operate outside FILE_ROOT (e.g. editing a project elsewhere in the
# proot filesystem), export AI_ALLOW_UNSAFE_PATHS=true. This is opt-in
# because an LLM-driven tool that can silently write/delete anywhere is a
# real footgun on a shared filesystem.

FILE_ROOT="${AI_FILE_ROOT:-$AI_HOME/files}"
mkdir -p "$FILE_ROOT"

FILE_INDEX="$DB_DIR/file_index.json"

init_file_index() {
    if [[ ! -f "$FILE_INDEX" ]]; then
        printf '{"entries":[]}\n' > "$FILE_INDEX"
    fi
}

# Resolve a user-supplied path to an absolute path and enforce the sandbox
# unless the user has explicitly opted out.
resolve_file_path() {
    local input="$1"
    local abs=""

    if [[ "$input" = /* ]]; then
        abs="$input"
    else
        abs="$FILE_ROOT/$input"
    fi

    # Collapse .. / . without requiring the target to already exist.
    if have realpath; then
        abs="$(realpath -m -- "$abs")"
    else
        mkdir -p "$(dirname "$abs")" 2>/dev/null || true
        abs="$(
            cd "$(dirname "$abs")" 2>/dev/null && \
            printf '%s/%s\n' "$(pwd -P)" "$(basename "$abs")"
        )" || die "cannot resolve path: $input"
    fi

    if [[ "${AI_ALLOW_UNSAFE_PATHS:-false}" != "true" ]]; then
        case "$abs" in
            "$FILE_ROOT"/*|"$FILE_ROOT")
                : ;;
            *)
                die "path escapes sandbox ($FILE_ROOT): $abs — set AI_ALLOW_UNSAFE_PATHS=true to override"
                ;;
        esac
    fi

    printf '%s\n' "$abs"
}

file_index_record() {
    local action="$1"
    local path="$2"
    local hash="${3:-}"
    local size="${4:-0}"

    init_file_index

    jq --arg ts "$(now_iso)" \
       --arg action "$action" \
       --arg path "$path" \
       --arg hash "$hash" \
       --argjson size "$size" \
       '.entries += [{"timestamp": $ts, "action": $action, "path": $path, "hash": $hash, "size": $size}]' \
       "$FILE_INDEX" > "${FILE_INDEX}.tmp" && mv "${FILE_INDEX}.tmp" "$FILE_INDEX"

    log_event "file_$action" "$path" >/dev/null
}

file_create() {
    local rel="$1"
    local content="$2"
    local path

    path="$(resolve_file_path "$rel")"
    mkdir -p "$(dirname "$path")"

    [[ -e "$path" ]] && die "already exists (use 'ai file write' to overwrite): $path"

    printf '%s' "$content" > "$path"

    file_index_record "create" "$path" "$(sha256_file "$path" || true)" "$(wc -c < "$path")"
    ok "created: $path"
}

file_read() {
    local rel="$1"
    local path

    path="$(resolve_file_path "$rel")"
    [[ -f "$path" ]] || die "not found: $path"

    cat "$path"
}

file_write() {
    local rel="$1"
    local content="$2"
    local path

    path="$(resolve_file_path "$rel")"
    mkdir -p "$(dirname "$path")"

    printf '%s' "$content" > "$path"

    file_index_record "write" "$path" "$(sha256_file "$path" || true)" "$(wc -c < "$path")"
    ok "wrote: $path"
}

file_append() {
    local rel="$1"
    local content="$2"
    local path

    path="$(resolve_file_path "$rel")"
    mkdir -p "$(dirname "$path")"

    printf '%s' "$content" >> "$path"

    file_index_record "append" "$path" "$(sha256_file "$path" || true)" "$(wc -c < "$path")"
    ok "appended: $path"
}

file_delete() {
    local rel="$1"
    local path

    path="$(resolve_file_path "$rel")"
    [[ -e "$path" ]] || die "not found: $path"

    rm -rf -- "$path"

    file_index_record "delete" "$path" "" "0"
    ok "deleted: $path"
}

file_list() {
    local rel="${1:-.}"
    local path

    path="$(resolve_file_path "$rel")"
    [[ -d "$path" ]] || die "not a directory: $path"

    find "$path" -mindepth 1 -maxdepth 4 -printf '%y %10s  %p\n' 2>/dev/null | sort -k3
}

cmd_file() {
    local sub="${1:-}"
    shift || true

    case "$sub" in
        create)
            local rel="${1:-}"; shift || true
            [[ -n "$rel" ]] || die "usage: ai file create PATH [CONTENT | - for stdin]"
            local content="${1:-}"
            [[ "$content" == "-" || -z "$content" && ! -t 0 ]] && content="$(cat)"
            file_create "$rel" "$content"
            ;;
        read|cat)
            local rel="${1:-}"
            [[ -n "$rel" ]] || die "usage: ai file read PATH"
            file_read "$rel"
            ;;
        write)
            local rel="${1:-}"; shift || true
            [[ -n "$rel" ]] || die "usage: ai file write PATH [CONTENT | - for stdin]"
            local content="${1:-}"
            [[ "$content" == "-" || -z "$content" && ! -t 0 ]] && content="$(cat)"
            file_write "$rel" "$content"
            ;;
        append)
            local rel="${1:-}"; shift || true
            [[ -n "$rel" ]] || die "usage: ai file append PATH [CONTENT | - for stdin]"
            local content="${1:-}"
            [[ "$content" == "-" || -z "$content" && ! -t 0 ]] && content="$(cat)"
            file_append "$rel" "$content"
            ;;
        delete|rm)
            local rel="${1:-}"
            [[ -n "$rel" ]] || die "usage: ai file delete PATH"
            file_delete "$rel"
            ;;
        list|ls)
            file_list "${1:-.}"
            ;;
        root)
            printf '%s\n' "$FILE_ROOT"
            ;;
        *)
            die "usage: ai file {create|read|write|append|delete|list|root} PATH [CONTENT]"
            ;;
    esac
}

# =============================================================================
# DB / INDEX
# =============================================================================
#
# Everything the orchestrator does (genesis, task, pov, synthesis, round,
# file_*) is already content-addressed into $OBJECT_DIR as small JSON
# records via log_event/write_artifact. This section adds a way to query
# that ledger and the file index without hand-rolling jq each time.

cmd_db() {
    local sub="${1:-summary}"
    shift || true

    init_file_index

    case "$sub" in
        summary)
            printf '\n%sDB SUMMARY%s\n' "$C_CYAN" "$C_RESET"
            printf '%s==============================%s\n' "$C_DIM" "$C_RESET"
            printf 'Object store : %s\n' "$OBJECT_DIR"
            printf 'File index   : %s\n' "$FILE_INDEX"
            printf 'File root    : %s\n\n' "$FILE_ROOT"

            printf 'Events by type:\n'
            find "$OBJECT_DIR" -maxdepth 1 -name '*.json' -exec \
                jq -r 'if .type then .type else "artifact:" + .kind end' {} \; 2>/dev/null |
                sort | uniq -c | sort -rn

            printf '\nTracked file actions:\n'
            jq -r '.entries[].action' "$FILE_INDEX" 2>/dev/null |
                sort | uniq -c | sort -rn

            printf '\nTotal objects: %s\n' \
                "$(find "$OBJECT_DIR" -maxdepth 1 -name '*.json' | wc -l)"
            printf '\n'
            ;;

        events)
            local type_filter="${1:-}"
            find "$OBJECT_DIR" -maxdepth 1 -name '*.json' -exec cat {} \; 2>/dev/null |
                jq -s --arg t "$type_filter" \
                    'if $t == "" then . else map(select(.type == $t)) end
                     | sort_by(.timestamp)'
            ;;

        files)
            jq '.entries' "$FILE_INDEX"
            ;;

        find)
            local hash="${1:-}"
            [[ -n "$hash" ]] || die "usage: ai db find HASH"
            local f="$OBJECT_DIR/$hash.json"
            local t="$OBJECT_DIR/$hash.txt"
            [[ -f "$f" ]] && cat "$f"
            [[ -f "$t" ]] && { printf '\n---content---\n'; cat "$t"; }
            [[ -f "$f" || -f "$t" ]] || die "no object with hash: $hash"
            ;;

        *)
            die "usage: ai db {summary|events [type]|files|find HASH}"
            ;;
    esac
}
# =============================================================================
# TEST
# =============================================================================

cmd_test() {
    local model=""

    model="$(resolve_model || true)"

    if [[ -z "$model" || ! -f "$model" ]]; then
        die "No GGUF model available. Run: ai install primary"
    fi

    verify_gguf "$model" ||
        die "Resolved model is invalid: $model"

    printf '\n'
    info "LLAMA TEST"
    printf 'Model : %s\n' "$model"
    printf 'Size  : %s\n' \
        "$(du -h "$model" | awk '{print $1}')"
    printf '\n'

    run_llama \
        'Reply with exactly: OK'
}

# =============================================================================
# RUN COMMAND
# =============================================================================

cmd_run() {
    local prompt="$*"

    if [[ -z "$prompt" ]]; then

        if [[ ! -t 0 ]]; then
            prompt="$(cat)"
        else
            die "prompt required"
        fi
    fi

    run_engine "$prompt"
}

# =============================================================================
# INTERACTIVE
# =============================================================================

cmd_chat() {
    run_chat
}

# =============================================================================
# HELP
# =============================================================================

cmd_help() {
    cat <<'EOF'

ai.sh 16.0.0
Bulletproof direct-GGUF local AI controller.

USAGE

  ai "prompt"
  ai run "prompt"

  ai chat

  ai test

  ai models
  ai model

  ai doctor
  ai status
  ai config

  ai install primary
  ai install fallback
  ai install all

  ai hash "text"

  ai file create PATH ["content" | - for stdin]
  ai file read   PATH
  ai file write  PATH ["content" | - for stdin]
  ai file append PATH ["content" | - for stdin]
  ai file delete PATH
  ai file list   [PATH]
  ai file root

  ai db summary
  ai db events [type]
  ai db files
  ai db find HASH

FILE ACCESS

  All "ai file" operations are sandboxed under FILE_ROOT
  ($AI_HOME/files by default, override with AI_FILE_ROOT).

  Every create/write/append/delete is recorded into:
    - $DB_DIR/file_index.json   (structured, jq-queryable)
    - $OBJECT_DIR/*.json        (content-addressed event ledger)

  To operate outside the sandbox, export:
    AI_ALLOW_UNSAFE_PATHS=true

MODEL ARCHITECTURE

  Logical model identifiers are configuration only.

  AI_MODEL
       |
       v
  physical GGUF resolver
       |
       +--> $AI_HOME/models
       |
       +--> Hugging Face cache
       |
       +--> primary
       |
       +--> fallback
       |
       v
  verified *.gguf
       |
       v
  $LLAMA_CLI
       |
       v
  inference

PRIMARY

  Qwen/Qwen2.5-Coder-3B-Instruct-GGUF:Q4_K_M

  Local:
    $AI_HOME/models/qwen2.5-coder-3b-instruct-q4_k_m.gguf

FALLBACK

  Qwen/Qwen2.5-1.5B-Instruct-GGUF:Q4_K_M

  Local:
    $AI_HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf

ORCHESTRATION

  2PI / 8 POV

    0°    analytical
    45°   architectural
    90°   critical
    135°  creative
    180°  implementation
    225°  adversarial
    270°  systems
    315°  synthesis

  Each candidate receives:

    SHA-256 identity
    structural scoring
    directness scoring
    completeness scoring
    convergence ranking

  Optional recursive rounds:

    AI_DEPTH=1

  Optional final synthesis:

    AI_SYNTHESIS=true

EXAMPLES

  ai doctor

  ai models

  ai install primary

  ai install fallback

  ai test

  ai "explain this bash function"

  AI_DEPTH=2 ai "analyze this architecture"

  AI_SYNTHESIS=true ai "design a robust local AI runtime"

  AI_VIEWS=4 ai "quick analysis"

  ai chat

ENVIRONMENT

  LLAMA_CLI
  AI_MODEL
  AI_CODER
  AI_FALLBACK

  AI_MODEL_DIR
  AI_MODEL_PATH
  AI_FALLBACK_PATH

  AI_CONTEXT
  AI_CTX

  AI_BATCH
  AI_BATCH_SIZE

  AI_UBATCH
  AI_UBATCH_SIZE

  AI_PREDICT
  AI_N_PREDICT

  AI_THREADS
  AI_GPU_LAYERS

  AI_TEMPERATURE
  AI_TEMP

  AI_TOP_K
  AI_TOP_P
  AI_REPEAT_PENALTY

  AI_TIMEOUT

  AI_VIEWS
  AI_DEPTH
  AI_SYNTHESIS

  AI_STATE_DIR
  AI_SESSION

SAFETY INVARIANT

  llama is never called unless:

    - runtime exists
    - model path is non-empty
    - model path exists
    - model path is a regular file
    - model path is non-empty
    - GGUF magic is valid

EOF
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    local command="${1:-}"

    case "$command" in

        "")
            cmd_help
            ;;

        help|-h|--help)
            cmd_help
            ;;

        run)
            shift
            cmd_run "$@"
            ;;

        chat|repl)
            shift
            cmd_chat "$@"
            ;;

        test)
            shift
            cmd_test "$@"
            ;;

        model|models)
            shift
            cmd_models "$@"
            ;;

        doctor)
            shift
            cmd_doctor "$@"
            ;;

        status)
            shift
            cmd_status "$@"
            ;;

        config)
            shift
            cmd_config "$@"
            ;;

        hash)
            shift
            cmd_hash "$@"
            ;;

        install)
            shift
            cmd_install "$@"
            ;;

        file|files)
            shift
            cmd_file "$@"
            ;;

        db)
            shift
            cmd_db "$@"
            ;;

        version|-V|--version)
            printf '%s\n' "$AI_VERSION"
            ;;

        *)
            cmd_run "$@"
            ;;
    esac
}

# =============================================================================
# ENTRY
# =============================================================================

main "$@"

