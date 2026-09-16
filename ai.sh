#!/usr/bin/env bash
# =============================================================================
# ai.sh v17.0.0
# =============================================================================
# Single-file local AI controller for llama.cpp.
#
# PRIMARY RUNTIME CONTRACT:
#
#   llama cli -m /path/model.gguf
#
# Prompt is always delivered through stdin.
#
# Architecture:
#
#   input
#     |
#     +--> normalize
#     +--> genesis SHA256
#     +--> task SHA256
#     |
#     +--> sequential 2PI / 8 POV
#     |      0°   analytical
#     |     45°   architectural
#     |     90°   critical
#     |    135°   creative
#     |    180°   implementation
#     |    225°   adversarial
#     |    270°   systems
#     |    315°   synthesis
#     |
#     +--> candidate scoring
#     +--> optional synthesis
#     +--> optional recursive continuation
#     |
#     +--> SHA256 object ledger
#     +--> sandboxed file CRUD
#     +--> file index
#
# Designed for:
#   Android / Termux / Debian proot / ARM64
#
# No Ollama dependency.
# No HTTP inference dependency.
# No logical model identifier is passed to llama.
#
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

# =============================================================================
# VERSION
# =============================================================================

AI_VERSION="17.0.0"

# =============================================================================
# PATHS
# =============================================================================

HOME_DIR="${HOME:-/root}"

AI_HOME="${AI_HOME:-$HOME_DIR/.ai}"
STATE_DIR="${AI_STATE_DIR:-$AI_HOME/.ai-state}"

MODEL_DIR="${AI_MODEL_DIR:-$AI_HOME/models}"

CACHE_DIR="${AI_CACHE_DIR:-$STATE_DIR/cache}"
LOG_DIR="${AI_LOG_DIR:-$STATE_DIR/logs}"
DB_DIR="${AI_DB:-$STATE_DIR/db}"
OBJECT_DIR="${AI_OBJECTS:-$DB_DIR/objects}"
REFERENCE_DIR="${AI_REFERENCE:-$DB_DIR/reference}"
RUN_DIR="${AI_RUN_DIR:-$STATE_DIR/run}"
SESSION_DIR="${AI_SESSION_DIR:-$STATE_DIR/sessions}"

FILE_ROOT="${AI_FILE_ROOT:-$AI_HOME/files}"
FILE_INDEX="$DB_DIR/file_index.json"

LAST_ERROR_FILE="$RUN_DIR/last_error.log"

mkdir -p \
    "$AI_HOME" \
    "$STATE_DIR" \
    "$MODEL_DIR" \
    "$CACHE_DIR" \
    "$LOG_DIR" \
    "$DB_DIR" \
    "$OBJECT_DIR" \
    "$REFERENCE_DIR" \
    "$RUN_DIR" \
    "$SESSION_DIR" \
    "$FILE_ROOT"

# =============================================================================
# LLAMA RUNTIME
# =============================================================================

LLAMA_CLI="${LLAMA_CLI:-$HOME_DIR/.local/bin/llama}"

# =============================================================================
# MODEL CONFIGURATION
# =============================================================================

AI_MODEL="${AI_MODEL:-Qwen/Qwen2.5-Coder-3B-Instruct-GGUF:Q4_K_M}"
AI_CODER="${AI_CODER:-$AI_MODEL}"
AI_FALLBACK="${AI_FALLBACK:-Qwen/Qwen2.5-1.5B-Instruct-GGUF:Q4_K_M}"

AI_MODEL_PATH="${AI_MODEL_PATH:-}"
AI_FALLBACK_PATH="${AI_FALLBACK_PATH:-}"

AI_PRIMARY_FILE="${AI_PRIMARY_FILE:-qwen2.5-coder-3b-instruct-q4_k_m.gguf}"
AI_FALLBACK_FILE="${AI_FALLBACK_FILE:-qwen2.5-1.5b-instruct-q4_k_m.gguf}"

PRIMARY_LOCAL_PATH="$MODEL_DIR/$AI_PRIMARY_FILE"
FALLBACK_LOCAL_PATH="$MODEL_DIR/$AI_FALLBACK_FILE"

AI_HF_ROOT="${AI_HF_ROOT:-$HOME_DIR/.cache/huggingface/hub}"

PRIMARY_HF_CACHE="$AI_HF_ROOT/models--Qwen--Qwen2.5-Coder-3B-Instruct-GGUF"
FALLBACK_HF_CACHE="$AI_HF_ROOT/models--Qwen--Qwen2.5-1.5B-Instruct-GGUF"

PRIMARY_HF_REPO="Qwen/Qwen2.5-Coder-3B-Instruct-GGUF"
FALLBACK_HF_REPO="Qwen/Qwen2.5-1.5B-Instruct-GGUF"

# =============================================================================
# INFERENCE
# =============================================================================

AI_CONTEXT="${AI_CONTEXT:-4096}"
AI_BATCH="${AI_BATCH:-256}"
AI_UBATCH="${AI_UBATCH:-128}"
AI_PREDICT="${AI_PREDICT:-512}"

AI_THREADS="${AI_THREADS:-8}"
AI_GPU_LAYERS="${AI_GPU_LAYERS:-0}"

AI_TEMPERATURE="${AI_TEMPERATURE:-0.65}"
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

AI_SESSION="${AI_SESSION:-default}"

AI_MIN_OUTPUT="${AI_MIN_OUTPUT:-8}"

# =============================================================================
# COLORS
# =============================================================================

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_CYAN=$'\033[36m'
    C_DIM=$'\033[2m'
else
    C_RESET=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_CYAN=""
    C_DIM=""
fi

# =============================================================================
# GLOBAL STATE
# =============================================================================

CURRENT_MODEL_PATH=""
CURRENT_MODEL_NAME=""
CURRENT_MODEL_TIER=""

GENESIS_HASH=""
TASK_HASH=""
CURRENT_HASH=""

LAST_OUTPUT=""
LAST_ERROR=""
LAST_EXIT_CODE=0

declare -a CANDIDATE_FILES=()
declare -a CANDIDATE_SCORES=()
declare -a CANDIDATE_HASHES=()
declare -a TMP_FILES=()

# =============================================================================
# SIGNAL / CLEANUP
# =============================================================================

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
# OUTPUT
# =============================================================================

info() {
    printf '%s[AI]%s %s\n' \
        "$C_CYAN" "$C_RESET" "$*" >&2
}

ok() {
    printf '%s[OK]%s %s\n' \
        "$C_GREEN" "$C_RESET" "$*"
}

warn() {
    printf '%s[WARN]%s %s\n' \
        "$C_YELLOW" "$C_RESET" "$*" >&2
}

die() {
    printf '%s[ERROR]%s %s\n' \
        "$C_RED" "$C_RESET" "$*" >&2
    exit 1
}

debug() {
    [[ "${AI_VERBOSE:-false}" == "true" ]] || return 0

    printf '%s[DEBUG]%s %s\n' \
        "$C_DIM" "$C_RESET" "$*" >&2
}

show_last_error() {
    [[ -f "$LAST_ERROR_FILE" ]] || return 0

    printf '%s[LLAMA ERROR]%s\n' \
        "$C_RED" "$C_RESET" >&2

    sed 's/^/  /' "$LAST_ERROR_FILE" >&2
}

# =============================================================================
# UTILITIES
# =============================================================================

have() {
    command -v "$1" >/dev/null 2>&1
}

now_iso() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

safe_tmp() {
    local prefix="${1:-ai}"
    local file

    if have mktemp; then
        file="$(mktemp "$RUN_DIR/${prefix}.XXXXXX")"
    else
        file="$RUN_DIR/${prefix}.$$.$RANDOM"
        : > "$file"
    fi

    TMP_FILES+=("$file")

    printf '%s\n' "$file"
}

is_uint() {
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

require_uint() {
    local name="$1"
    local value="$2"

    is_uint "$value" ||
        die "$name must be an unsigned integer: $value"
}

# =============================================================================
# CONFIG VALIDATION
# =============================================================================

validate_config() {
    require_uint AI_CONTEXT "$AI_CONTEXT"
    require_uint AI_BATCH "$AI_BATCH"
    require_uint AI_UBATCH "$AI_UBATCH"
    require_uint AI_PREDICT "$AI_PREDICT"
    require_uint AI_THREADS "$AI_THREADS"
    require_uint AI_TIMEOUT "$AI_TIMEOUT"
    require_uint AI_VIEWS "$AI_VIEWS"
    require_uint AI_DEPTH "$AI_DEPTH"

    (( AI_CONTEXT > 0 )) ||
        die "AI_CONTEXT must be > 0"

    (( AI_BATCH > 0 )) ||
        die "AI_BATCH must be > 0"

    (( AI_UBATCH > 0 )) ||
        die "AI_UBATCH must be > 0"

    (( AI_PREDICT > 0 )) ||
        die "AI_PREDICT must be > 0"

    (( AI_THREADS > 0 )) ||
        die "AI_THREADS must be > 0"

    (( AI_TIMEOUT > 0 )) ||
        die "AI_TIMEOUT must be > 0"

    (( AI_VIEWS >= 1 && AI_VIEWS <= 8 )) ||
        die "AI_VIEWS must be 1..8"

    (( AI_DEPTH >= 1 && AI_DEPTH <= 32 )) ||
        die "AI_DEPTH must be 1..32"
}

# =============================================================================
# HASH
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

    die "sha256sum or shasum required"
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

    die "sha256sum or shasum required"
}

# =============================================================================
# JSON
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
# GGUF
# =============================================================================

is_valid_gguf() {
    local file="$1"
    local magic

    [[ -f "$file" ]] || return 1
    [[ -s "$file" ]] || return 1

    magic="$(
        head -c 4 "$file" 2>/dev/null |
            od -An -tc |
            tr -d '[:space:]'
    )"

    [[ "$magic" == "GGUF" ]]
}

verify_gguf() {
    local file="$1"

    if ! is_valid_gguf "$file"; then
        warn "invalid GGUF: $file"
        return 1
    fi

    return 0
}

# =============================================================================
# MODEL SEARCH
# =============================================================================

find_exact_gguf() {
    local root="$1"
    local name="$2"

    [[ -d "$root" ]] || return 1

    find "$root" \
        -type f \
        -iname "$name" \
        -print \
        -quit \
        2>/dev/null
}

find_any_gguf() {
    local root="$1"

    [[ -d "$root" ]] || return 1

    find "$root" \
        -type f \
        -iname '*.gguf' \
        -print \
        2>/dev/null |
        sort |
        head -n 1
}

# =============================================================================
# MODEL RESOLUTION
# =============================================================================

find_primary_model() {
    local model=""

    if [[ -n "$AI_MODEL_PATH" &&
          -f "$AI_MODEL_PATH" &&
          -s "$AI_MODEL_PATH" ]]; then

        verify_gguf "$AI_MODEL_PATH" || return 1
        printf '%s\n' "$AI_MODEL_PATH"
        return 0
    fi

    if [[ -f "$PRIMARY_LOCAL_PATH" ]] &&
       verify_gguf "$PRIMARY_LOCAL_PATH"; then

        printf '%s\n' "$PRIMARY_LOCAL_PATH"
        return 0
    fi

    model="$(
        find_exact_gguf \
            "$MODEL_DIR" \
            "$AI_PRIMARY_FILE" ||
            true
    )"

    if [[ -n "$model" ]] &&
       verify_gguf "$model"; then

        printf '%s\n' "$model"
        return 0
    fi

    model="$(
        find_exact_gguf \
            "$PRIMARY_HF_CACHE" \
            "$AI_PRIMARY_FILE" ||
            true
    )"

    if [[ -n "$model" ]] &&
       verify_gguf "$model"; then

        printf '%s\n' "$model"
        return 0
    fi

    model="$(
        find_any_gguf \
            "$PRIMARY_HF_CACHE" ||
            true
    )"

    if [[ -n "$model" ]] &&
       verify_gguf "$model"; then

        printf '%s\n' "$model"
        return 0
    fi

    return 1
}

find_fallback_model() {
    local model=""

    if [[ -n "$AI_FALLBACK_PATH" &&
          -f "$AI_FALLBACK_PATH" &&
          -s "$AI_FALLBACK_PATH" ]]; then

        verify_gguf "$AI_FALLBACK_PATH" || return 1
        printf '%s\n' "$AI_FALLBACK_PATH"
        return 0
    fi

    if [[ -f "$FALLBACK_LOCAL_PATH" ]] &&
       verify_gguf "$FALLBACK_LOCAL_PATH"; then

        printf '%s\n' "$FALLBACK_LOCAL_PATH"
        return 0
    fi

    model="$(
        find_exact_gguf \
            "$MODEL_DIR" \
            "$AI_FALLBACK_FILE" ||
            true
    )"

    if [[ -n "$model" ]] &&
       verify_gguf "$model"; then

        printf '%s\n' "$model"
        return 0
    fi

    model="$(
        find_exact_gguf \
            "$FALLBACK_HF_CACHE" \
            "$AI_FALLBACK_FILE" ||
            true
    )"

    if [[ -n "$model" ]] &&
       verify_gguf "$model"; then

        printf '%s\n' "$model"
        return 0
    fi

    model="$(
        find_any_gguf \
            "$FALLBACK_HF_CACHE" ||
            true
    )"

    if [[ -n "$model" ]] &&
       verify_gguf "$model"; then

        printf '%s\n' "$model"
        return 0
    fi

    return 1
}

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
# RUNTIME
# =============================================================================

check_runtime() {
    [[ -x "$LLAMA_CLI" ]] || {
        LAST_ERROR="llama runtime is not executable: $LLAMA_CLI"
        printf '%s\n' "$LAST_ERROR" > "$LAST_ERROR_FILE"
        return 127
    }

    return 0
}

# =============================================================================
# LLAMA EXECUTION
# =============================================================================
#
# v17 deliberately uses:
#
#   llama cli -m MODEL
#
# and sends the complete prompt to stdin.
#
# This avoids:
#
#   --prompt "$huge_string"
#
# and:
#
#   --file "$temporary_file"
#
# which vary between llama.cpp builds.
#
# =============================================================================

run_llama() {
    local prompt="${1:-}"
    local model="${2:-}"
    local stderr_file
    local output
    local rc
    local -a cmd

    LAST_OUTPUT=""
    LAST_ERROR=""
    LAST_EXIT_CODE=0

    [[ -n "$prompt" ]] || {
        LAST_ERROR="empty prompt"
        printf '%s\n' "$LAST_ERROR" > "$LAST_ERROR_FILE"
        LAST_EXIT_CODE=2
        return 2
    }

    check_runtime || {
        LAST_EXIT_CODE=$?
        printf '%s\n' "$LAST_ERROR" > "$LAST_ERROR_FILE" 2>/dev/null || true
        return "$LAST_EXIT_CODE"
    }

    if [[ -z "$model" || ! -f "$model" ]]; then
        model="$(resolve_model || true)"
    fi

    if [[ -z "$model" || ! -f "$model" ]]; then
        LAST_ERROR="no physical GGUF model resolved"
        LAST_EXIT_CODE=2

        {
            printf '[%s] exit=2\n' "$(now_iso)"
            printf '%s\n' "$LAST_ERROR"
            printf 'MODEL_DIR=%s\n' "$MODEL_DIR"
            printf 'HF_CACHE=%s\n' "$AI_HF_ROOT"
        } > "$LAST_ERROR_FILE"

        return 2
    fi

    verify_gguf "$model" || {
        LAST_ERROR="invalid GGUF: $model"
        LAST_EXIT_CODE=2
        printf '%s\n' "$LAST_ERROR" > "$LAST_ERROR_FILE"
        return 2
    }

    # -------------------------------------------------------------------------
    # HARD RUNTIME CONTRACT
    # -------------------------------------------------------------------------

    cmd=(
        "$LLAMA_CLI"
        cli
        -m "$model"
    )

    # -------------------------------------------------------------------------
    # Optional flags.
    #
    # These are intentionally supplied only when explicitly enabled through
    # AI_LLAMA_FLAGS. The base invocation remains universally compatible with
    # the user's known-good `llama cli -m MODEL` runtime.
    #
    # Example:
    #
    # AI_LLAMA_FLAGS='--ctx-size 4096 --threads 8 --temp 0.65'
    #
    # -------------------------------------------------------------------------

    if [[ -n "${AI_LLAMA_FLAGS:-}" ]]; then
        # shellcheck disable=SC2206
        local extra_flags=( $AI_LLAMA_FLAGS )
        cmd+=("${extra_flags[@]}")
    fi

    stderr_file="$(safe_tmp llama-stderr)"

    if [[ "${AI_VERBOSE:-false}" == "true" ]]; then
        printf '%sCOMMAND:%s' \
            "$C_DIM" "$C_RESET" >&2

        printf ' %q' "${cmd[@]}" >&2
        printf '\n' >&2
    fi

    debug "llama stdin execution"

    # IMPORTANT:
    #
    # printf -> llama stdin
    #
    # EOF terminates the input stream. This prevents the interactive REPL
    # from waiting for another user turn.
    #
    if have timeout; then
        if output="$(
            printf '%s\n' "$prompt" |
                timeout \
                    "$AI_TIMEOUT" \
                    "${cmd[@]}" \
                    < /dev/stdin \
                    2>"$stderr_file"
        )"; then
            rc=0
        else
            rc=$?
        fi
    else
        if output="$(
            printf '%s\n' "$prompt" |
                "${cmd[@]}" \
                < /dev/stdin \
                2>"$stderr_file"
        )"; then
            rc=0
        else
            rc=$?
        fi
    fi

    if (( rc != 0 )); then
        LAST_ERROR="$(
            cat "$stderr_file" 2>/dev/null || true
        )"

        LAST_EXIT_CODE="$rc"

        {
            printf '[%s] exit=%s\n' "$(now_iso)" "$rc"

            if [[ -n "$LAST_ERROR" ]]; then
                printf '%s\n' "$LAST_ERROR"
            else
                printf '%s\n' \
                    "(llama produced no stderr; check timeout/model/runtime)"
            fi
        } > "$LAST_ERROR_FILE"

        return "$rc"
    fi

    LAST_OUTPUT="$output"
    LAST_EXIT_CODE=0

    printf '%s\n' "$output"

    return 0
}

# =============================================================================
# LEDGER
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
    local text_file
    local json_file

    hash="$(sha256_string "$content")"

    text_file="$OBJECT_DIR/$hash.txt"
    json_file="$OBJECT_DIR/$hash.json"

    if [[ ! -f "$text_file" ]]; then
        printf '%s\n' "$content" > "$text_file"
    fi

    cat > "$json_file" <<EOF
{
  "hash":"$(json_escape "$hash")",
  "kind":"$(json_escape "$kind")",
  "parent":"$(json_escape "$parent")",
  "created":"$(now_iso")",
  "file":"$(json_escape "$text_file")"
}
EOF

    printf '%s\n' "$hash"
}

# =============================================================================
# NORMALIZATION
# =============================================================================

normalize_prompt() {
    local prompt="$1"

    prompt="${prompt//$'\r'/}"

    # Strip only leading/trailing blank lines.
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

    GENESIS_HASH="$(
        sha256_string "$material"
    )"

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
# POV
# =============================================================================

POV_NAMES=(
    analytical
    architectural
    critical
    creative
    implementation
    adversarial
    systems
    synthesis
)

POV_ANGLES=(
    0
    45
    90
    135
    180
    225
    270
    315
)

build_pov_prompt() {
    local original="$1"
    local index="$2"

    cat <<EOF
You are a reasoning node.

TASK:
$original

POV:
${POV_NAMES[$index]}

ANGLE:
${POV_ANGLES[$index]} degrees

GENESIS:
$GENESIS_HASH

TASK HASH:
$TASK_HASH

Produce an independent analysis from this viewpoint.

Requirements:

1. Stay focused on the task.
2. Identify assumptions.
3. Separate facts from inference.
4. Preserve concrete implementation details.
5. Detect contradictions.
6. Identify missing requirements.
7. Prefer testable statements.
8. Do not invent execution results.
9. Do not discuss this orchestration protocol.
10. Return only the useful analysis.

VIEW OBJECTIVE:
${POV_NAMES[$index]}
EOF
}

# =============================================================================
# SCORING
# =============================================================================

count_words() {
    printf '%s\n' "$1" |
        awk '{n+=NF} END {print n+0}'
}

structure_score() {
    local text="$1"
    local score=0

    grep -Eq \
        '(^|[[:space:]])(1\.|2\.|3\.|4\.|5\.|- |\* )' \
        <<< "$text" &&
        score=$((score + 1))

    grep -Eiq \
        '(because|therefore|however|implementation|solution|problem|constraint)' \
        <<< "$text" &&
        score=$((score + 1))

    grep -q ':' <<< "$text" &&
        score=$((score + 1))

    printf '%s\n' "$score"
}

directness_score() {
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
    local length_score
    local structure_score
    local direct_score
    local hash_score
    local completeness

    words="$(count_words "$text")"
    structure="$(structure_score "$text")"
    directness="$(directness_score "$text")"

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

    structure_score=$((structure * 3333 / 100))
    direct_score=$((directness * 5000 / 100))
    hash_score=$((16#${hash:0:2} * 100 / 255))

    if (( structure >= 2 )); then
        completeness=100
    else
        completeness=$((structure * 50))
    fi

    awk \
        -v l="$length_score" \
        -v s="$structure_score" \
        -v d="$direct_score" \
        -v h="$hash_score" \
        -v c="$completeness" \
        'BEGIN {
            total =
                l * 0.20 +
                s * 0.20 +
                d * 0.20 +
                h * 0.10 +
                c * 0.30

            printf "%.3f\n", total
        }'
}

# =============================================================================
# RUN ONE POV
# =============================================================================

run_pov() {
    local original="$1"
    local index="$2"

    local prompt
    local output
    local hash
    local score
    local artifact

    prompt="$(
        build_pov_prompt \
            "$original" \
            "$index"
    )"

    info \
        "POV $((index + 1))/8 — ${POV_NAMES[$index]} @ ${POV_ANGLES[$index]}°"

    if ! output="$(
        run_llama "$prompt"
    )"; then

        warn "POV failed: ${POV_NAMES[$index]}"
        show_last_error
        return 1
    fi

    if (( ${#output} < AI_MIN_OUTPUT )); then
        warn \
            "POV produced insufficient output: ${POV_NAMES[$index]}"
        return 1
    fi

    hash="$(sha256_string "$output")"

    score="$(
        score_candidate \
            "$output" \
            "$hash"
    )"

    artifact="$(
        write_artifact \
            "pov:${POV_NAMES[$index]}" \
            "$output" \
            "$TASK_HASH"
    )"

    CANDIDATE_FILES+=("$artifact")
    CANDIDATE_SCORES+=("$score")
    CANDIDATE_HASHES+=("$hash")

    log_event \
        "pov" \
        "task=$TASK_HASH pov=${POV_NAMES[$index]} angle=${POV_ANGLES[$index]} hash=$hash score=$score" \
        >/dev/null

    return 0
}

# =============================================================================
# BEST CANDIDATE
# =============================================================================

best_candidate_index() {
    local i
    local best=-1
    local best_score=-1

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
    local prompt
    local output
    local hash

    if [[ "${AI_SYNTHESIS,,}" != "true" ]]; then

        best="$(best_candidate_index)"

        if (( best >= 0 )); then
            get_candidate_text \
                "${CANDIDATE_FILES[$best]}"
        fi

        return 0
    fi

    prompt=$(
        cat <<EOF
You are the final synthesis node.

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

SYNTHESIS:

1. Reconcile useful information.
2. Resolve contradictions.
3. Do not average incorrect claims.
4. Prefer concrete implementation.
5. Preserve constraints.
6. Remove redundancy.
7. Produce one coherent answer.
8. Do not mention the candidate machinery.
9. Do not claim execution that did not occur.
10. Return only the final answer.
EOF
    )

    info "SYNTHESIS"

    if ! output="$(
        run_llama "$prompt"
    )"; then

        warn "synthesis failed; selecting best candidate"
        show_last_error

        best="$(best_candidate_index)"

        if (( best >= 0 )); then
            get_candidate_text \
                "${CANDIDATE_FILES[$best]}"
        fi

        return 0
    fi

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
# ROUND
# =============================================================================

run_round() {
    local original="$1"
    local depth="$2"

    local i
    local output

    CANDIDATE_FILES=()
    CANDIDATE_SCORES=()
    CANDIDATE_HASHES=()

    info "ROUND $depth/$AI_DEPTH"

    for ((i = 0; i < AI_VIEWS; i++)); do
        run_pov "$original" "$i" >/dev/null || true
    done

    (( ${#CANDIDATE_FILES[@]} > 0 )) ||
        return 1

    output="$(
        synthesize_candidates "$original"
    )"

    printf '%s\n' "$output"
}

# =============================================================================
# ENGINE
# =============================================================================

run_engine() {
    local prompt="$1"

    local normalized
    local depth
    local result=""
    local parent_hash
    local result_hash

    normalized="$(
        normalize_prompt "$prompt"
    )"

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

        if ! result="$(
            run_round \
                "$normalized" \
                "$depth"
        )"; then

            die "round $depth failed: no usable candidate"
        fi

        result_hash="$(
            sha256_string "$result"
        )"

        log_event \
            "round" \
            "depth=$depth parent=$parent_hash result=$result_hash" \
            >/dev/null

        write_artifact \
            "round:$depth" \
            "$result" \
            "$parent_hash" >/dev/null

        parent_hash="$result_hash"

        if (( depth < AI_DEPTH )); then

            normalized=$(
                cat <<EOF
Continue solving the following task.

ORIGINAL TASK:
$prompt

PREVIOUS RESULT:
$result

CONTINUATION:

- identify unresolved issues
- correct contradictions
- improve implementation precision
- retain useful information
- produce an improved result
EOF
            )

            create_task_hash "$normalized" >/dev/null
        fi
    done

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
    local prompt
    local response

    info "interactive session: $AI_SESSION"
    info "type /help or /exit"

    while true; do

        printf '> '

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
                    '/help    show commands' \
                    '/exit    leave session' \
                    '/clear   clear session' \
                    '/status  runtime status' \
                    '/models  model registry'
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
# FILE SANDBOX
# =============================================================================

init_file_index() {
    [[ -f "$FILE_INDEX" ]] ||
        printf '{"entries":[]}\n' > "$FILE_INDEX"
}

resolve_file_path() {
    local input="$1"
    local path

    if [[ "$input" = /* ]]; then
        path="$input"
    else
        path="$FILE_ROOT/$input"
    fi

    have realpath ||
        die "realpath is required for sandboxed file operations"

    path="$(realpath -m -- "$path")"

    if [[ "${AI_ALLOW_UNSAFE_PATHS:-false}" != "true" ]]; then

        case "$path" in
            "$FILE_ROOT"|"$FILE_ROOT"/*)
                ;;
            *)
                die \
                    "sandbox violation: $path"
                ;;
        esac
    fi

    printf '%s\n' "$path"
}

file_index_record() {
    local action="$1"
    local path="$2"
    local hash="${3:-}"
    local size="${4:-0}"

    init_file_index

    have jq ||
        die "jq is required for file index operations"

    jq \
        --arg timestamp "$(now_iso)" \
        --arg action "$action" \
        --arg path "$path" \
        --arg hash "$hash" \
        --argjson size "$size" \
        '.entries += [{
            "timestamp":$timestamp,
            "action":$action,
            "path":$path,
            "hash":$hash,
            "size":$size
        }]' \
        "$FILE_INDEX" \
        > "$FILE_INDEX.tmp"

    mv \
        "$FILE_INDEX.tmp" \
        "$FILE_INDEX"

    log_event \
        "file_$action" \
        "path=$path hash=$hash size=$size" \
        >/dev/null
}

file_create() {
    local rel="$1"
    local content="$2"
    local path

    path="$(resolve_file_path "$rel")"

    [[ ! -e "$path" ]] ||
        die "already exists: $path"

    mkdir -p "$(dirname "$path")"

    printf '%s' "$content" > "$path"

    file_index_record \
        create \
        "$path" \
        "$(sha256_file "$path")" \
        "$(wc -c < "$path")"

    ok "created: $path"
}

file_read() {
    local path

    path="$(resolve_file_path "$1")"

    [[ -f "$path" ]] ||
        die "not found: $path"

    cat "$path"
}

file_write() {
    local rel="$1"
    local content="$2"
    local path

    path="$(resolve_file_path "$rel")"

    mkdir -p "$(dirname "$path")"

    printf '%s' "$content" > "$path"

    file_index_record \
        write \
        "$path" \
        "$(sha256_file "$path")" \
        "$(wc -c < "$path")"

    ok "wrote: $path"
}

file_append() {
    local rel="$1"
    local content="$2"
    local path

    path="$(resolve_file_path "$rel")"

    mkdir -p "$(dirname "$path")"

    printf '%s' "$content" >> "$path"

    file_index_record \
        append \
        "$path" \
        "$(sha256_file "$path")" \
        "$(wc -c < "$path")"

    ok "appended: $path"
}

file_delete() {
    local path

    path="$(resolve_file_path "$1")"

    [[ -e "$path" ]] ||
        die "not found: $path"

    rm -rf -- "$path"

    file_index_record \
        delete \
        "$path" \
        "" \
        0

    ok "deleted: $path"
}

file_list() {
    local path

    path="$(resolve_file_path "${1:-.}")"

    [[ -d "$path" ]] ||
        die "not a directory: $path"

    find "$path" \
        -mindepth 1 \
        -maxdepth 4 \
        -printf '%y %10s  %p\n' \
        2>/dev/null |
        sort -k3
}

cmd_file() {
    local sub="${1:-}"
    shift || true

    local rel
    local content

    case "$sub" in

        create)
            rel="${1:-}"
            shift || true

            [[ -n "$rel" ]] ||
                die "usage: ai file create PATH [CONTENT|-]"

            content="${1:-}"

            if [[ "$content" == "-" ||
                  ( -z "$content" && ! -t 0 ) ]]; then
                content="$(cat)"
            fi

            file_create "$rel" "$content"
            ;;

        read|cat)
            rel="${1:-}"

            [[ -n "$rel" ]] ||
                die "usage: ai file read PATH"

            file_read "$rel"
            ;;

        write)
            rel="${1:-}"
            shift || true

            [[ -n "$rel" ]] ||
                die "usage: ai file write PATH [CONTENT|-]"

            content="${1:-}"

            if [[ "$content" == "-" ||
                  ( -z "$content" && ! -t 0 ) ]]; then
                content="$(cat)"
            fi

            file_write "$rel" "$content"
            ;;

        append)
            rel="${1:-}"
            shift || true

            [[ -n "$rel" ]] ||
                die "usage: ai file append PATH [CONTENT|-]"

            content="${1:-}"

            if [[ "$content" == "-" ||
                  ( -z "$content" && ! -t 0 ) ]]; then
                content="$(cat)"
            fi

            file_append "$rel" "$content"
            ;;

        delete|rm)
            rel="${1:-}"

            [[ -n "$rel" ]] ||
                die "usage: ai file delete PATH"

            file_delete "$rel"
            ;;

        list|ls)
            file_list "${1:-.}"
            ;;

        root)
            printf '%s\n' "$FILE_ROOT"
            ;;

        *)
            die \
                "usage: ai file {create|read|write|append|delete|list|root}"
            ;;
    esac
}

# =============================================================================
# SCAN
# =============================================================================

cmd_scan() {
    local dir="${1:-.}"
    shift || true

    local instruction="$*"

    [[ -n "$instruction" ]] ||
        die 'usage: ai scan DIR "instruction"'

    [[ -d "$dir" ]] ||
        die "not a directory: $dir"

    local extensions="${AI_SCAN_EXTENSIONS:-html,htm,js,mjs,ts,css,json,sh,md}"
    local depth="${AI_SCAN_DEPTH:-3}"

    local -a find_expr=()
    local -a exts=()

    local ext
    local f
    local size
    local content

    local combined=""
    local included=0
    local skipped=0

    IFS=',' read -ra exts <<< "$extensions"

    for ext in "${exts[@]}"; do

        [[ ${#find_expr[@]} -gt 0 ]] &&
            find_expr+=(-o)

        find_expr+=(
            -iname
            "*.${ext}"
        )
    done

    # Approximate byte budget.
    #
    # 4 bytes/token is deliberately conservative for source code.
    local max_total_bytes=$((AI_CONTEXT * 3))
    local max_file_bytes="${AI_SCAN_FILE_BYTES:-4000}"

    while IFS= read -r -d '' f; do

        size="$(wc -c < "$f" 2>/dev/null || echo 0)"

        if (( ${#combined} + size > max_total_bytes )); then
            skipped=$((skipped + 1))
            continue
        fi

        content="$(
            head \
                -c "$max_file_bytes" \
                -- "$f" \
                2>/dev/null ||
                true
        )"

        combined+=$'\n\n--- FILE: '"$f"$' ---\n'"$content"

        included=$((included + 1))

    done < <(
        find "$dir" \
            -maxdepth "$depth" \
            -type f \
            \( "${find_expr[@]}" \) \
            -print0 \
            2>/dev/null |
            sort -z
    )

    [[ -n "$combined" ]] ||
        die \
            "no matching files under $dir"

    info \
        "scan: $included file(s), skipped $skipped, root=$dir"

    local prompt

    prompt=$(
        cat <<EOF
TASK:
$instruction

SOURCE DIRECTORY:
$dir

The following source files were actually read.

Base your analysis only on the contents supplied below.

$combined
EOF
    )

    run_engine "$prompt"
}

# =============================================================================
# INSTALL
# =============================================================================

download_model() {
    local url="$1"
    local target="$2"
    local tmp

    have curl ||
        die "curl is required for model installation"

    tmp="$(
        mktemp "$MODEL_DIR/.download.XXXXXX"
    )"

    TMP_FILES+=("$tmp")

    info "downloading model"
    printf 'URL    : %s\n' "$url"
    printf 'TARGET : %s\n' "$target"

    if ! curl \
        --fail \
        --location \
        --retry 5 \
        --retry-delay 3 \
        --connect-timeout 20 \
        --continue-at - \
        --output "$tmp" \
        "$url"
    then

        rm -f "$tmp"

        die "download failed"
    fi

    verify_gguf "$tmp" ||
        die "downloaded object is not valid GGUF"

    mv -f \
        "$tmp" \
        "$target"

    ok "installed: $target"
}

install_primary() {
    local url

    if [[ -f "$PRIMARY_LOCAL_PATH" ]] &&
       verify_gguf "$PRIMARY_LOCAL_PATH"; then

        ok "primary already installed"
        return
    fi

    url="https://huggingface.co/${PRIMARY_HF_REPO}/resolve/main/${AI_PRIMARY_FILE}"

    download_model \
        "$url" \
        "$PRIMARY_LOCAL_PATH"
}

install_fallback() {
    local url

    if [[ -f "$FALLBACK_LOCAL_PATH" ]] &&
       verify_gguf "$FALLBACK_LOCAL_PATH"; then

        ok "fallback already installed"
        return
    fi

    url="https://huggingface.co/${FALLBACK_HF_REPO}/resolve/main/${AI_FALLBACK_FILE}"

    download_model \
        "$url" \
        "$FALLBACK_LOCAL_PATH"
}

cmd_install() {
    case "${1:-primary}" in

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
            die \
                "usage: ai install {primary|fallback|all}"
            ;;
    esac
}

# =============================================================================
# MODELS
# =============================================================================

cmd_models() {
    local primary
    local fallback

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

    printf '\nPRIMARY\n'
    printf '  logical : %s\n' "$AI_MODEL"
    printf '  local   : %s\n' "$PRIMARY_LOCAL_PATH"

    if [[ -n "$primary" ]]; then
        printf '  resolved: %s\n' "$primary"
        printf '  size    : %s\n' \
            "$(du -h "$primary" | awk '{print $1}')"
    else
        printf '  resolved: NOT FOUND\n'
    fi

    printf '\nFALLBACK\n'
    printf '  logical : %s\n' "$AI_FALLBACK"
    printf '  local   : %s\n' "$FALLBACK_LOCAL_PATH"

    if [[ -n "$fallback" ]]; then
        printf '  resolved: %s\n' "$fallback"
        printf '  size    : %s\n' \
            "$(du -h "$fallback" | awk '{print $1}')"
    else
        printf '  resolved: NOT FOUND\n'
    fi

    printf '\n'

    if [[ -n "$primary" ]]; then
        ok "PRIMARY READY"
    elif [[ -n "$fallback" ]]; then
        warn "PRIMARY MISSING — FALLBACK READY"
    else
        warn "NO GGUF MODEL FOUND"
    fi

    printf '\n'
}

# =============================================================================
# STATUS
# =============================================================================

cmd_status() {
    local model

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

    printf '\nInference\n'
    printf 'Context       : %s\n' "$AI_CONTEXT"
    printf 'Batch         : %s\n' "$AI_BATCH"
    printf 'UBatch        : %s\n' "$AI_UBATCH"
    printf 'Predict       : %s\n' "$AI_PREDICT"
    printf 'Threads       : %s\n' "$AI_THREADS"
    printf 'GPU layers    : %s\n' "$AI_GPU_LAYERS"
    printf 'Temperature   : %s\n' "$AI_TEMPERATURE"
    printf 'Top-K         : %s\n' "$AI_TOP_K"
    printf 'Top-P         : %s\n' "$AI_TOP_P"
    printf 'Repeat        : %s\n' "$AI_REPEAT_PENALTY"
    printf 'Timeout       : %s\n' "$AI_TIMEOUT"

    printf '\nOrchestration\n'
    printf 'POV views     : %s\n' "$AI_VIEWS"
    printf 'Depth         : %s\n' "$AI_DEPTH"
    printf 'Synthesis     : %s\n' "$AI_SYNTHESIS"

    printf '\nState\n'
    printf 'State         : %s\n' "$STATE_DIR"
    printf 'Objects       : %s\n' "$OBJECT_DIR"
    printf 'Files         : %s\n' "$FILE_ROOT"

    printf '\n'
}

# =============================================================================
# DOCTOR
# =============================================================================

cmd_doctor() {
    local model
    local version

    printf '\n'
    printf '%sAI RUNTIME DOCTOR%s\n' \
        "$C_CYAN" "$C_RESET"

    printf '%s==============================%s\n\n' \
        "$C_DIM" "$C_RESET"

    printf 'Bash:\n'
    printf '  %s\n' "$BASH_VERSION"

    printf '\nRuntime:\n'
    printf '  path: %s\n' "$LLAMA_CLI"

    if [[ -x "$LLAMA_CLI" ]]; then
        ok "llama executable"
    else
        warn "llama executable missing"
    fi

    if [[ -x "$LLAMA_CLI" ]]; then

        version="$(
            "$LLAMA_CLI" \
                --version \
                2>&1 |
                head -n 1 ||
                true
        )"

        printf '  version: %s\n' "$version"

        printf '  contract: llama cli -m MODEL\n'
    fi

    printf '\nTools:\n'

    for tool in \
        awk \
        sed \
        grep \
        find \
        sort \
        head \
        tail \
        od \
        sha256sum \
        realpath \
        jq \
        curl \
        timeout
    do

        if have "$tool"; then
            printf '  %-12s OK\n' "$tool"
        else
            printf '  %-12s MISSING\n' "$tool"
        fi
    done

    printf '\nModel:\n'

    model="$(resolve_model || true)"

    if [[ -n "$model" ]]; then
        ok "GGUF resolved"

        printf '  tier: %s\n' "$CURRENT_MODEL_TIER"
        printf '  file: %s\n' "$model"
        printf '  size: %s\n' \
            "$(du -h "$model" | awk '{print $1}')"
    else
        warn "no GGUF model resolved"
    fi

    printf '\nConfiguration:\n'
    printf '  context     = %s\n' "$AI_CONTEXT"
    printf '  batch       = %s\n' "$AI_BATCH"
    printf '  ubatch      = %s\n' "$AI_UBATCH"
    printf '  predict     = %s\n' "$AI_PREDICT"
    printf '  threads     = %s\n' "$AI_THREADS"
    printf '  views       = %s\n' "$AI_VIEWS"
    printf '  depth       = %s\n' "$AI_DEPTH"
    printf '  synthesis   = %s\n' "$AI_SYNTHESIS"

    printf '\n'
}

# =============================================================================
# TEST
# =============================================================================

cmd_test() {
    local model

    model="$(resolve_model || true)"

    [[ -n "$model" ]] ||
        die "no GGUF model available"

    verify_gguf "$model" ||
        die "invalid model: $model"

    info "LLAMA TEST"
    printf 'Model : %s\n' "$model"
    printf 'Size  : %s\n\n' \
        "$(du -h "$model" | awk '{print $1}')"

    run_llama \
        "Reply with exactly: OK"
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

PHYSICAL
  AI_MODEL_PATH=$AI_MODEL_PATH
  AI_FALLBACK_PATH=$AI_FALLBACK_PATH
  AI_MODEL_DIR=$MODEL_DIR
  AI_PRIMARY_FILE=$AI_PRIMARY_FILE
  AI_FALLBACK_FILE=$AI_FALLBACK_FILE

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

SCAN
  AI_SCAN_EXTENSIONS=${AI_SCAN_EXTENSIONS:-html,htm,js,mjs,ts,css,json,sh,md}
  AI_SCAN_DEPTH=${AI_SCAN_DEPTH:-3}
  AI_SCAN_FILE_BYTES=${AI_SCAN_FILE_BYTES:-4000}

FILES
  FILE_ROOT=$FILE_ROOT
  AI_ALLOW_UNSAFE_PATHS=${AI_ALLOW_UNSAFE_PATHS:-false}

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
        die 'usage: ai hash TEXT'

    sha256_string "$input"
}

# =============================================================================
# DB
# =============================================================================

cmd_db() {
    local sub="${1:-summary}"
    shift || true

    init_file_index

    case "$sub" in

        summary)
            printf '\n'
            printf '%sDB SUMMARY%s\n' \
                "$C_CYAN" "$C_RESET"

            printf '%s==============================%s\n' \
                "$C_DIM" "$C_RESET"

            printf 'Objects : %s\n' "$OBJECT_DIR"
            printf 'Files   : %s\n' "$FILE_INDEX"
            printf 'Root    : %s\n\n' "$FILE_ROOT"

            printf 'Events:\n'

            find "$OBJECT_DIR" \
                -maxdepth 1 \
                -name '*.json' \
                -exec jq -r \
                    'if .type then .type else "artifact:" + .kind end' \
                    {} \; \
                2>/dev/null |
                sort |
                uniq -c |
                sort -rn

            printf '\nFile actions:\n'

            jq -r \
                '.entries[].action' \
                "$FILE_INDEX" \
                2>/dev/null |
                sort |
                uniq -c |
                sort -rn

            printf '\nObjects: %s\n' \
                "$(find "$OBJECT_DIR" -maxdepth 1 -name '*.json' | wc -l)"

            printf '\n'
            ;;

        events)
            local filter="${1:-}"

            find "$OBJECT_DIR" \
                -maxdepth 1 \
                -name '*.json' \
                -exec cat {} \; \
                2>/dev/null |
                jq -s \
                    --arg type "$filter" \
                    '
                    if $type == ""
                    then .
                    else map(select(.type == $type))
                    end
                    | sort_by(.timestamp)
                    '
            ;;

        files)
            jq '.entries' "$FILE_INDEX"
            ;;

        find)
            local hash="${1:-}"

            [[ -n "$hash" ]] ||
                die "usage: ai db find HASH"

            local json="$OBJECT_DIR/$hash.json"
            local text="$OBJECT_DIR/$hash.txt"

            if [[ -f "$json" ]]; then
                cat "$json"
            fi

            if [[ -f "$text" ]]; then
                printf '\n--- content ---\n'
                cat "$text"
            fi

            [[ -f "$json" || -f "$text" ]] ||
                die "object not found: $hash"
            ;;

        *)
            die \
                "usage: ai db {summary|events [type]|files|find HASH}"
            ;;
    esac
}

# =============================================================================
# RUN
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
# HELP
# =============================================================================

cmd_help() {
    cat <<EOF

ai.sh $AI_VERSION

DIRECT LLAMA.CPP CONTROLLER

USAGE

  ai "prompt"
  ai run "prompt"
  ai chat

RUNTIME

  llama cli -m /path/model.gguf

  Prompt is delivered through stdin.

COMMANDS

  ai "prompt"
  ai run "prompt"

  ai chat
  ai test

  ai models
  ai doctor
  ai status
  ai config
  ai version

  ai install primary
  ai install fallback
  ai install all

  ai hash "text"

  ai scan DIR "instruction"

  ai file create PATH CONTENT
  ai file read PATH
  ai file write PATH CONTENT
  ai file append PATH CONTENT
  ai file delete PATH
  ai file list PATH
  ai file root

  ai db summary
  ai db events [TYPE]
  ai db files
  ai db find HASH

MODEL RESOLUTION

  1. AI_MODEL_PATH
  2. $MODEL_DIR/$AI_PRIMARY_FILE
  3. Hugging Face primary cache
  4. primary cache GGUF
  5. AI_FALLBACK_PATH
  6. fallback local GGUF
  7. fallback Hugging Face cache

MODEL INVARIANT

  llama receives only a verified physical GGUF path.

  Logical identifiers such as:

    Qwen/Qwen2.5-Coder-3B-Instruct-GGUF:Q4_K_M

  are never passed to llama.

2PI / 8 POV

    0°    analytical
   45°    architectural
   90°    critical
  135°    creative
  180°    implementation
  225°    adversarial
  270°    systems
  315°    synthesis

  AI_VIEWS=1..8

RECURSION

  AI_DEPTH=1

  Example:

    AI_DEPTH=2 ai "analyze this architecture"

SYNTHESIS

  AI_SYNTHESIS=true ai "design a local AI controller"

SCAN

  ai scan ~/project "find architectural problems"

  Default extensions:

    html,htm,js,mjs,ts,css,json,sh,md

  Override:

    AI_SCAN_EXTENSIONS=py,rs,go ai scan DIR "..."

  Depth:

    AI_SCAN_DEPTH=3

  Per-file read limit:

    AI_SCAN_FILE_BYTES=4000

FILES

  Default sandbox:

    $FILE_ROOT

  To explicitly allow paths outside the sandbox:

    AI_ALLOW_UNSAFE_PATHS=true

LEDGER

  $OBJECT_DIR

FILE INDEX

  $FILE_INDEX

RUNTIME OVERRIDE

  LLAMA_CLI=/path/to/llama ai test

OPTIONAL LLAMA FLAGS

  The base runtime intentionally uses only:

    llama cli -m MODEL

  If your installed llama build accepts additional flags:

    AI_LLAMA_FLAGS='--ctx-size 4096 --threads 8 --temp 0.65' ai test

  This is optional.

EXAMPLES

  ai doctor

  ai models

  ai test

  ai "explain this bash function"

  ai scan ~/project "analyze the codebase"

  AI_VIEWS=4 ai "quick architecture analysis"

  AI_SYNTHESIS=true ai "design a robust local runtime"

  AI_DEPTH=2 AI_SYNTHESIS=true ai "refine this architecture"

SAFETY

  llama is never invoked without:

    - executable runtime
    - physical model path
    - regular model file
    - non-empty model file
    - valid GGUF magic

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
            run_chat "$@"
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

        scan)
            shift
            cmd_scan "$@"
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
