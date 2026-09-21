#!/usr/bin/env bash
# =============================================================================
# ai.sh v101.0.0
# =============================================================================
# Single-file local AI controller
#
# Runtime:
#   llama.cpp -> llama cli -> local GGUF
#
# Design:
#   normalize
#      ↓
#   genesis SHA256
#      ↓
#   8 logical POV passes
#      ↓
#   entropy detoxification
#      ↓
#   structural scoring
#      ↓
#   convergence
#      ↓
#   optional synthesis
#      ↓
#   immutable-ish JSONL lineage
#      ↓
#   file-indexed CRUD / reparse
#
# No Ollama.
# No Python.
# No external database.
# No concurrent model loading.
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="101.0.0"
PROG="${0##*/}"

# -----------------------------------------------------------------------------
# PATHS
# -----------------------------------------------------------------------------

AI_HOME="${AI_HOME:-$HOME/.ai}"
STATE="${AI_STATE_DIR:-$AI_HOME/.ai-state}"

MODEL_DIR="${AI_MODEL_DIR:-$AI_HOME/models}"
FILE_ROOT="${AI_FILE_ROOT:-$AI_HOME/files}"

DB_DIR="$STATE/db"
OBJECT_DIR="$STATE/objects"
RUN_DIR="$STATE/run"
LOG_DIR="$STATE/log"
SESSION_DIR="$STATE/sessions"
CACHE_DIR="$STATE/cache"

INDEX="$DB_DIR/file_index.jsonl"
EVENTS="$DB_DIR/events.jsonl"
LEDGER="$DB_DIR/ledger.jsonl"
ERROR_LOG="$RUN_DIR/last_error.log"

mkdir -p \
    "$MODEL_DIR" \
    "$FILE_ROOT" \
    "$DB_DIR" \
    "$OBJECT_DIR" \
    "$RUN_DIR" \
    "$LOG_DIR" \
    "$SESSION_DIR" \
    "$CACHE_DIR"

# -----------------------------------------------------------------------------
# LLAMA RUNTIME
# -----------------------------------------------------------------------------

LLAMA_CLI="${LLAMA_CLI:-$HOME/.local/bin/llama}"

PRIMARY_MODEL="${AI_MODEL_PATH:-$MODEL_DIR/qwen2.5-coder-3b-instruct-q4_k_m.gguf}"
FALLBACK_MODEL="${AI_FALLBACK_MODEL_PATH:-$MODEL_DIR/qwen2.5-1.5b-instruct-q4_k_m.gguf}"

AI_CONTEXT="${AI_CONTEXT:-4096}"
AI_BATCH="${AI_BATCH:-256}"
AI_UBATCH="${AI_UBATCH:-128}"
AI_PREDICT="${AI_PREDICT:-512}"

AI_THREADS="${AI_THREADS:-8}"
AI_THREADS_BATCH="${AI_THREADS_BATCH:-8}"

AI_TEMP="${AI_TEMP:-0.65}"
AI_TOP_K="${AI_TOP_K:-40}"
AI_TOP_P="${AI_TOP_P:-0.95}"
AI_REPEAT="${AI_REPEAT:-1.10}"

AI_TIMEOUT="${AI_TIMEOUT:-600}"

# Eight logical reasoning dimensions.
VIEWS=(
    analytical
    architectural
    critical
    creative
    implementation
    adversarial
    systems
    synthesis
)

# -----------------------------------------------------------------------------
# META CONSTANTS
# -----------------------------------------------------------------------------

GENESIS="2PI/8"
ENTROPY_DECAY="0.6180339887"
SCHEMA_VERSION="101"
MOVEMENT_ID="2244-1"

# Score weights.
W_LENGTH="0.20"
W_STRUCTURE="0.20"
W_DIRECTNESS="0.20"
W_HASH="0.10"
W_COMPLETENESS="0.30"

# -----------------------------------------------------------------------------
# BASIC UTILITIES
# -----------------------------------------------------------------------------

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

warn() {
    printf 'WARN: %s\n' "$*" >&2
}

info() {
    printf '%s\n' "$*"
}

now() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    else
        openssl dgst -sha256 -r | awk '{print $1}'
    fi
}

sha256_string() {
    printf '%s' "$1" | sha256
}

json_escape() {
    # Bash-only JSON string escaping.
    local s="${1-}"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    printf '%s' "$s"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 ||
        die "required command unavailable: $1"
}

# -----------------------------------------------------------------------------
# MODEL RESOLUTION
# -----------------------------------------------------------------------------

valid_gguf() {
    local f="$1"

    [[ -f "$f" ]] || return 1
    [[ -r "$f" ]] || return 1

    # GGUF magic is "GGUF".
    [[ "$(dd if="$f" bs=1 count=4 2>/dev/null || true)" == "GGUF" ]]
}

resolve_model() {
    local candidate

    if [[ -n "${AI_MODEL_PATH:-}" ]] && valid_gguf "$AI_MODEL_PATH"; then
        printf '%s\n' "$AI_MODEL_PATH"
        return
    fi

    for candidate in \
        "$PRIMARY_MODEL" \
        "$FALLBACK_MODEL" \
        "$HOME/.ai/models/qwen2.5-coder-3b-instruct-q4_k_m.gguf" \
        "$HOME/.ai/models/qwen2.5-1.5b-instruct-q4_k_m.gguf" \
        "$HOME/_/models/qwen2.5-coder-3b-instruct-q4_k_m.gguf"
    do
        if valid_gguf "$candidate"; then
            printf '%s\n' "$candidate"
            return
        fi
    done

    die "no valid GGUF model found"
}

# -----------------------------------------------------------------------------
# LLAMA INVOCATION
# -----------------------------------------------------------------------------
#
# Important:
#   llama.cpp supports:
#
#       llama cli -m model.gguf
#
# and current CLI builds expose the generation parameters used here.
#
# We feed the prompt through stdin to remain compatible with the user's
# known-good local invocation.
# -----------------------------------------------------------------------------

run_llama() {
    local prompt="${1:-}"
    local model="${2:-$(resolve_model)}"
    local outfile="${3:-}"

    [[ -n "$prompt" ]] || {
        printf 'run_llama: empty prompt\n' > "$ERROR_LOG"
        return 2
    }

    [[ -x "$LLAMA_CLI" ]] || {
        printf 'llama executable not found: %s\n' "$LLAMA_CLI" > "$ERROR_LOG"
        return 127
    }

    valid_gguf "$model" || {
        printf 'invalid GGUF model: %s\n' "$model" > "$ERROR_LOG"
        return 3
    }

    local args=(
        cli
        -m "$model"
        -t "$AI_THREADS"
        -tb "$AI_THREADS_BATCH"
        -c "$AI_CONTEXT"
        -b "$AI_BATCH"
        -ub "$AI_UBATCH"
        -n "$AI_PREDICT"
        --temp "$AI_TEMP"
        --top-k "$AI_TOP_K"
        --top-p "$AI_TOP_P"
        --repeat-penalty "$AI_REPEAT"
        --no-display-prompt
        --single-turn
    )

    local rc=0

    if [[ -n "$outfile" ]]; then
        if command -v timeout >/dev/null 2>&1; then
            printf '%s\n' "$prompt" |
                timeout "$AI_TIMEOUT" "$LLAMA_CLI" "${args[@]}" \
                >"$outfile" 2>"$ERROR_LOG" || rc=$?
        else
            printf '%s\n' "$prompt" |
                "$LLAMA_CLI" "${args[@]}" \
                >"$outfile" 2>"$ERROR_LOG" || rc=$?
        fi

        return "$rc"
    fi

    if command -v timeout >/dev/null 2>&1; then
        printf '%s\n' "$prompt" |
            timeout "$AI_TIMEOUT" "$LLAMA_CLI" "${args[@]}" 2>"$ERROR_LOG" ||
            return $?
    else
        printf '%s\n' "$prompt" |
            "$LLAMA_CLI" "${args[@]}" 2>"$ERROR_LOG" ||
            return $?
    fi
}

# -----------------------------------------------------------------------------
# INPUT NORMALIZATION / ENTROPY DETOX
# -----------------------------------------------------------------------------

normalize() {
    local input="${1:-}"

    # Normalize CRLF.
    input="${input//$'\r'/}"

    # Collapse pathological horizontal whitespace.
    input="$(printf '%s' "$input" |
        sed -E 's/[[:space:]]+/ /g')"

    # Remove zero-width/control characters.
    input="$(printf '%s' "$input" |
        LC_ALL=C sed 's/[^[:print:]\t\n]//g')"

    # Trim.
    input="${input#"${input%%[![:space:]]*}"}"
    input="${input%"${input##*[![:space:]]}"}"

    printf '%s' "$input"
}

detox() {
    local input
    input="$(normalize "${1:-}")"

    # Remove repeated prompt wrappers without attempting semantic rewriting.
    input="$(printf '%s' "$input" |
        sed -E \
            -e 's/^[[:space:]]*(PROMPT|REQUEST|QUERY)[[:space:]]*:[[:space:]]*//I' \
            -e 's/[[:space:]]{3,}/  /g')"

    printf '%s' "$input"
}

# -----------------------------------------------------------------------------
# EVENT / LEDGER
# -----------------------------------------------------------------------------

event() {
    local type="${1:-event}"
    local payload="${2:-{}}"
    local ts
    local id
    local prev

    ts="$(now)"
    prev=""

    if [[ -s "$EVENTS" ]]; then
        prev="$(tail -n 1 "$EVENTS" |
            sha256_string)"
    fi

    id="$(
        printf '%s|%s|%s|%s' \
            "$ts" "$type" "$prev" "$payload" |
            sha256_string
    )"

    printf \
        '{"schema":%s,"id":"%s","ts":"%s","type":"%s","prev":"%s","payload":%s}\n' \
        "$SCHEMA_VERSION" \
        "$id" \
        "$ts" \
        "$(json_escape "$type")" \
        "$prev" \
        "$payload" \
        >> "$EVENTS"
}

ledger() {
    local task="$1"
    local result="$2"
    local genesis="$3"
    local score="$4"
    local ts
    local id
    local prev

    ts="$(now)"
    prev=""

    [[ -s "$LEDGER" ]] &&
        prev="$(tail -n 1 "$LEDGER" | sha256_string)"

    id="$(
        printf '%s|%s|%s|%s|%s' \
            "$ts" "$task" "$result" "$genesis" "$prev" |
            sha256_string
    )"

    printf \
        '{"schema":%s,"id":"%s","ts":"%s","genesis":"%s","task":"%s","result":"%s","score":%s,"prev":"%s"}\n' \
        "$SCHEMA_VERSION" \
        "$id" \
        "$ts" \
        "$(json_escape "$genesis")" \
        "$(json_escape "$task")" \
        "$(json_escape "$result")" \
        "${score:-0}" \
        "$prev" \
        >> "$LEDGER"

    printf '%s\n' "$id"
}

# -----------------------------------------------------------------------------
# FILE INDEX
# -----------------------------------------------------------------------------

file_hash() {
    local f="$1"

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$f" | awk '{print $1}'
    else
        openssl dgst -sha256 -r "$f" | awk '{print $1}'
    fi
}

safe_file() {
    local rel="$1"
    local abs

    [[ -n "$rel" ]] || return 1

    # Reject absolute paths.
    [[ "$rel" != /* ]] || return 1

    # Reject traversal.
    [[ "$rel" != *".."* ]] || return 1

    abs="$FILE_ROOT/$rel"

    case "$abs" in
        "$FILE_ROOT"/*) ;;
        *) return 1 ;;
    esac

    printf '%s\n' "$abs"
}

index_file() {
    local rel="$1"
    local abs
    local hash
    local size
    local ts

    abs="$(safe_file "$rel")" ||
        die "unsafe file path"

    [[ -f "$abs" ]] ||
        die "file does not exist: $rel"

    hash="$(file_hash "$abs")"
    size="$(wc -c < "$abs")"
    ts="$(now)"

    printf \
        '{"path":"%s","sha256":"%s","bytes":%s,"ts":"%s"}\n' \
        "$(json_escape "$rel")" \
        "$hash" \
        "$size" \
        "$ts" >> "$INDEX"

    event "file.index" \
        "{\"path\":\"$(json_escape "$rel")\",\"sha256\":\"$hash\",\"bytes\":$size}"

    printf '%s\n' "$hash"
}

# -----------------------------------------------------------------------------
# CRUD
# -----------------------------------------------------------------------------

cmd_create() {
    local rel="${1:-}"
    shift || true

    [[ -n "$rel" ]] || die "usage: ai file create PATH [CONTENT]"

    local abs
    abs="$(safe_file "$rel")" ||
        die "unsafe path"

    mkdir -p "$(dirname "$abs")"

    if [[ $# -gt 0 ]]; then
        printf '%s\n' "$*" > "$abs"
    else
        cat > "$abs"
    fi

    index_file "$rel" >/dev/null

    info "CREATED $rel"
}

cmd_read() {
    local rel="${1:-}"
    [[ -n "$rel" ]] || die "usage: ai file read PATH"

    local abs
    abs="$(safe_file "$rel")" ||
        die "unsafe path"

    [[ -f "$abs" ]] || die "not found: $rel"

    cat "$abs"
}

cmd_update() {
    local rel="${1:-}"
    shift || true

    [[ -n "$rel" ]] || die "usage: ai file update PATH CONTENT"

    local abs
    abs="$(safe_file "$rel")" ||
        die "unsafe path"

    [[ -f "$abs" ]] || die "not found: $rel"

    printf '%s\n' "$*" > "$abs"
    index_file "$rel" >/dev/null

    info "UPDATED $rel"
}

cmd_delete() {
    local rel="${1:-}"
    [[ -n "$rel" ]] || die "usage: ai file delete PATH"

    local abs
    abs="$(safe_file "$rel")" ||
        die "unsafe path"

    [[ -f "$abs" ]] || die "not found: $rel"

    rm -f "$abs"

    event "file.delete" \
        "{\"path\":\"$(json_escape "$rel")\"}"

    info "DELETED $rel"
}

cmd_reparse() {
    local count=0
    local f rel

    while IFS= read -r -d '' f; do
        rel="${f#"$FILE_ROOT"/}"
        index_file "$rel" >/dev/null
        count=$((count + 1))
    done < <(find "$FILE_ROOT" -type f -print0)

    event "file.reparse" "{\"count\":$count}"

    info "REPARSED $count FILES"
}

# -----------------------------------------------------------------------------
# SCORE
# -----------------------------------------------------------------------------

score_candidate() {
    local text="${1:-}"
    local prompt="${2:-}"

    local len structure direct complete hash_component
    local score

    len="${#text}"

    # Length saturation: useful output without rewarding unlimited verbosity.
    if (( len < 80 )); then
        length_score="0.20"
    elif (( len < 250 )); then
        length_score="0.60"
    elif (( len < 1200 )); then
        length_score="1.00"
    else
        length_score="0.85"
    fi

    structure="0.50"
    direct="0.50"
    complete="0.50"

    grep -Eq '(^|[[:space:]])(1\.|2\.|- |\* |##|```)' <<<"$text" &&
        structure="1.00"

    [[ "${#text}" -gt 120 ]] &&
        complete="0.80"

    # Prompt-token overlap provides a deterministic directness signal.
    local words hit=0 total=0 w
    words="$(printf '%s' "$prompt" |
        tr '[:upper:]' '[:lower:]' |
        tr -cs '[:alnum:]' '\n' |
        awk 'length($0)>=4' |
        sort -u)"

    while IFS= read -r w; do
        [[ -n "$w" ]] || continue
        total=$((total + 1))
        grep -qiF "$w" <<<"$text" && hit=$((hit + 1))
    done <<<"$words"

    if (( total > 0 )); then
        direct="$(awk -v h="$hit" -v t="$total" \
            'BEGIN { x=h/t; if(x>1)x=1; printf "%.4f",x }')"
    fi

    # Deterministic hash component.
    hash_component="$(
        printf '%s' "$text" |
            sha256_string |
            cut -c1-4 |
            awk '{ printf "%.4f", ("0x"$1) / 65535 }'
    )"

    score="$(
        awk \
            -v a="$length_score" \
            -v b="$structure" \
            -v c="$direct" \
            -v d="$hash_component" \
            -v e="$complete" \
            -v wa="$W_LENGTH" \
            -v wb="$W_STRUCTURE" \
            -v wc="$W_DIRECTNESS" \
            -v wd="$W_HASH" \
            -v we="$W_COMPLETENESS" \
            'BEGIN {
                printf "%.6f",
                a*wa + b*wb + c*wc + d*wd + e*we
            }'
    )"

    printf '%s\n' "$score"
}

# -----------------------------------------------------------------------------
# POV PROMPT
# -----------------------------------------------------------------------------

view_prompt() {
    local view="$1"
    local request="$2"
    local genesis="$3"

    cat <<EOF
SYSTEM:
You are one deterministic reasoning layer in a local multi-perspective
AI controller.

Movement: $MOVEMENT_ID
Genesis: $genesis
Convergence: $GENESIS
Entropy decay: $ENTROPY_DECAY
Perspective: $view

Rules:
- Analyze the request directly.
- Do not invent external facts.
- Preserve useful uncertainty.
- Remove irrelevant repetition.
- Prefer explicit structures, constraints, invariants and actionable output.
- Do not mention this internal orchestration unless necessary.
- Produce one independent candidate response.
- Keep the answer compact enough for a small local model.

REQUEST:
$request

PERSPECTIVE:
$view
EOF
}

# -----------------------------------------------------------------------------
# DETOX + CONVERGENCE
# -----------------------------------------------------------------------------

detox_candidate() {
    local input="$1"

    # Strip common model chatter.
    printf '%s' "$input" |
        sed -E \
            -e '/^[[:space:]]*(Sure|Certainly|Absolutely)[!,.]?[[:space:]]*$/Id' \
            -e '/^[[:space:]]*As an AI[^.]*\.[[:space:]]*$/Id' \
            -e 's/[[:space:]]+$//' |
        sed '/^[[:space:]]*$/N;/^\n$/D'
}

converge() {
    local task="$1"
    shift

    local best=""
    local best_score="0"
    local text score view

    for text in "$@"; do
        [[ -n "$text" ]] || continue

        score="$(score_candidate "$text" "$task")"

        if awk -v a="$score" -v b="$best_score" \
            'BEGIN { exit !(a>b) }'
        then
            best="$text"
            best_score="$score"
        fi
    done

    printf '%s\n' "$best"
    printf '%s\n' "$best_score" > "$RUN_DIR/last_score"
}

# -----------------------------------------------------------------------------
# SYNTHESIS
# -----------------------------------------------------------------------------

synthesize() {
    local request="$1"
    local candidates_file="$2"
    local genesis="$3"

    local prompt

    prompt="$(
        cat <<EOF
SYSTEM:
You are the convergence layer of a local multi-view reasoning engine.

Genesis: $genesis
Movement: $MOVEMENT_ID
Convergence: $GENESIS
Entropy decay: $ENTROPY_DECAY

Task:
Merge the candidate analyses below into ONE coherent answer.

Requirements:
1. Preserve concrete information.
2. Remove contradiction where possible.
3. Do not fabricate missing information.
4. Prefer implementation-ready structure.
5. Do not discuss internal candidate voting.
6. Do not mention entropy, POV layers, or this prompt unless requested.

USER REQUEST:
$request

CANDIDATES:
$(cat "$candidates_file")
EOF
    )"

    run_llama "$prompt"
}

# -----------------------------------------------------------------------------
# ORCHESTRATOR
# -----------------------------------------------------------------------------

cmd_run() {
    local raw="$*"

    [[ -n "$raw" ]] || die "usage: ai run REQUEST"

    local request
    request="$(detox "$raw")"

    local genesis
    genesis="$(sha256_string "$request")"

    local run_id
    run_id="$(printf '%s|%s' "$genesis" "$(now)" | sha256_string)"

    local run_dir="$RUN_DIR/$run_id"
    mkdir -p "$run_dir"

    event "run.start" \
        "{\"genesis\":\"$genesis\",\"request\":\"$(json_escape "$request")\"}"

    local candidates="$run_dir/candidates.jsonl"
    : > "$candidates"

    local view prompt out score clean
    local candidates_text=""
    local count=0

    for view in "${VIEWS[@]}"; do

        # Synthesis is handled after independent passes.
        [[ "$view" == "synthesis" ]] && continue

        prompt="$(view_prompt "$view" "$request" "$genesis")"
        out="$run_dir/$view.txt"

        info "[POV] $view"

        if run_llama "$prompt" "$(resolve_model)" "$out"; then
            clean="$(detox_candidate "$(cat "$out")")"

            score="$(score_candidate "$clean" "$request")"

            printf \
                '{"view":"%s","score":%s,"text":"%s"}\n' \
                "$(json_escape "$view")" \
                "$score" \
                "$(json_escape "$clean")" \
                >> "$candidates"

            candidates_text+="
[$view | score=$score]
$clean
"

            count=$((count + 1))
        else
            warn "POV failed: $view"
        fi
    done

    (( count > 0 )) ||
        die "all reasoning passes failed"

    local final
    local final_score

    # Default: deterministic local convergence.
    final="$(awk -F'"text":"' '{
        if (NF>1) {
            x=$2
            sub(/".*$/, "", x)
            gsub(/\\"/, "\"", x)
            print x
        }
    }' "$candidates" |
        head -n 1)"

    # Better convergence: select highest scored candidate.
    final="$(
        awk '
            {
                match($0, /"score":([0-9.]+)/, s)
                match($0, /"text":"(.*)"}/, t)
                if (s[1] > best) {
                    best=s[1]
                    text=t[1]
                }
            }
            END {
                gsub(/\\"/, "\"", text)
                print text
            }
        ' "$candidates"
    )"

    final_score="$(score_candidate "$final" "$request")"

    # Optional synthesis.
    if [[ "${AI_SYNTHESIS:-0}" == "1" ]]; then
        info "[SYNTHESIS]"

        local synthesized
        synthesized="$(
            synthesize \
                "$request" \
                "$candidates" \
                "$genesis" ||
                true
        )"

        if [[ -n "$synthesized" ]]; then
            final="$(detox_candidate "$synthesized")"
            final_score="$(score_candidate "$final" "$request")"
        fi
    fi

    printf '%s\n' "$final" > "$run_dir/result.txt"

    local result_hash
    result_hash="$(sha256_string "$final")"

    cp "$run_dir/result.txt" \
       "$OBJECT_DIR/$result_hash.txt"

    ledger \
        "$request" \
        "$result_hash" \
        "$genesis" \
        "$final_score" >/dev/null

    event "run.complete" \
        "{\"genesis\":\"$genesis\",\"result\":\"$result_hash\",\"score\":$final_score,\"views\":$count}"

    printf '%s\n' "$final"
}

# -----------------------------------------------------------------------------
# INTERPRETER
# -----------------------------------------------------------------------------

cmd_interpret() {
    local request="$*"

    [[ -n "$request" ]] ||
        die "usage: ai interpret REQUEST"

    cmd_run "$request"
}

# -----------------------------------------------------------------------------
# HASH
# -----------------------------------------------------------------------------

cmd_hash() {
    local input="$*"

    [[ -n "$input" ]] ||
        die "usage: ai hash TEXT"

    printf '%s\n' "$input" | sha256
}

# -----------------------------------------------------------------------------
# SCORE COMMAND
# -----------------------------------------------------------------------------

cmd_score() {
    local request="${1:-}"
    shift || true

    [[ -n "$request" ]] ||
        die "usage: ai score REQUEST TEXT"

    local text="$*"

    [[ -n "$text" ]] ||
        die "missing candidate text"

    score_candidate "$text" "$request"
}

# -----------------------------------------------------------------------------
# MODELS
# -----------------------------------------------------------------------------

cmd_models() {
    printf '\nMODEL REGISTRY\n'
    printf '%s\n' '=============================='
    printf 'Runtime:\n  %s\n' "$LLAMA_CLI"

    if [[ -x "$LLAMA_CLI" ]]; then
        printf '  status: READY\n'
    else
        printf '  status: MISSING\n'
    fi

    printf '\nPRIMARY\n'
    printf '  logical : Qwen/Qwen2.5-Coder-3B-Instruct-GGUF:Q4_K_M\n'
    printf '  local   : %s\n' "$PRIMARY_MODEL"

    if valid_gguf "$PRIMARY_MODEL"; then
        printf '  status  : [OK] READY\n'
    else
        printf '  status  : [--] unavailable\n'
    fi

    printf '\nFALLBACK\n'
    printf '  logical : Qwen/Qwen2.5-1.5B-Instruct-GGUF:Q4_K_M\n'
    printf '  local   : %s\n' "$FALLBACK_MODEL"

    if valid_gguf "$FALLBACK_MODEL"; then
        printf '  status  : [OK] READY\n'
    else
        printf '  status  : [--] unavailable\n'
    fi

    printf '\nCONFIG\n'
    printf '  context : %s\n' "$AI_CONTEXT"
    printf '  batch   : %s\n' "$AI_BATCH"
    printf '  ubatch  : %s\n' "$AI_UBATCH"
    printf '  predict : %s\n' "$AI_PREDICT"
    printf '  threads : %s\n' "$AI_THREADS"
    printf '  views   : %s\n' "${#VIEWS[@]}"
    printf '  entropy : %s\n' "$ENTROPY_DECAY"
}

# -----------------------------------------------------------------------------
# STATUS
# -----------------------------------------------------------------------------

cmd_status() {
    printf '\nAI // STATUS\n'
    printf '%s\n' '=============================='
    printf 'version       : %s\n' "$VERSION"
    printf 'movement      : %s\n' "$MOVEMENT_ID"
    printf 'convergence   : %s\n' "$GENESIS"
    printf 'state         : %s\n' "$STATE"
    printf 'file root     : %s\n' "$FILE_ROOT"
    printf 'llama         : %s\n' "$LLAMA_CLI"

    if [[ -x "$LLAMA_CLI" ]]; then
        printf 'runtime       : READY\n'
    else
        printf 'runtime       : MISSING\n'
    fi

    printf 'model         : %s\n' "$(resolve_model 2>/dev/null || printf 'NONE')"
    printf 'logical views : %s\n' "${#VIEWS[@]}"

    if [[ -f "$RUN_DIR/last_score" ]]; then
        printf 'last score    : %s\n' "$(cat "$RUN_DIR/last_score")"
    else
        printf 'last score    : --\n'
    fi
}

# -----------------------------------------------------------------------------
# HELP
# -----------------------------------------------------------------------------

usage() {
    cat <<EOF

ai.sh v$VERSION

LOCAL LLAMA ORCHESTRATOR
========================

Core:
  ai run REQUEST
  ai interpret REQUEST
  ai hash TEXT
  ai score REQUEST CANDIDATE

Models:
  ai models
  ai status

Files:
  ai file create PATH [CONTENT]
  ai file read PATH
  ai file update PATH CONTENT
  ai file delete PATH
  ai file reparse

Examples:

  ai "explain this architecture"

  ai run "rebuild the parser as a deterministic state machine"

  ai interpret "review this shell architecture for race conditions"

  ai file create notes/test.txt "hello"
  ai file read notes/test.txt
  ai file update notes/test.txt "updated"
  ai file reparse

Environment:

  AI_HOME
  AI_STATE_DIR
  AI_MODEL_DIR
  AI_FILE_ROOT
  AI_MODEL_PATH
  AI_FALLBACK_MODEL_PATH

  LLAMA_CLI

  AI_CONTEXT
  AI_BATCH
  AI_UBATCH
  AI_PREDICT
  AI_THREADS
  AI_THREADS_BATCH

  AI_TEMP
  AI_TOP_K
  AI_TOP_P
  AI_REPEAT
  AI_TIMEOUT

  AI_SYNTHESIS=1

Architecture:

  REQUEST
      |
      v
  NORMALIZE / DETOX
      |
      v
  SHA256 GENESIS
      |
      +-------------------------------+
      |                               |
      v                               v
   analytical                    architectural
   critical                      creative
   implementation                adversarial
   systems                       ...
      |                               |
      +---------------+---------------+
                      |
                      v
                SCORE / CONVERGE
                      |
                      v
                 RESULT HASH
                      |
                      v
              JSONL EVENT LEDGER
                      |
                      v
              FILE-INDEXED OBJECT

EOF
}

# -----------------------------------------------------------------------------
# DISPATCH
# -----------------------------------------------------------------------------

main() {
    local cmd="${1:-}"

    case "$cmd" in
        run|ask)
            shift
            cmd_run "$@"
            ;;

        interpret|i)
            shift
            cmd_interpret "$@"
            ;;

        hash)
            shift
            cmd_hash "$@"
            ;;

        score)
            shift
            cmd_score "$@"
            ;;

        models)
            cmd_models
            ;;

        status)
            cmd_status
            ;;

        file)
            shift
            case "${1:-}" in
                create)
                    shift
                    cmd_create "$@"
                    ;;
                read)
                    shift
                    cmd_read "$@"
                    ;;
                update)
                    shift
                    cmd_update "$@"
                    ;;
                delete|rm)
                    shift
                    cmd_delete "$@"
                    ;;
                reparse|index)
                    cmd_reparse
                    ;;
                *)
                    die "usage: ai file {create|read|update|delete|reparse}"
                    ;;
            esac
            ;;

        version|--version|-v)
            printf '%s v%s\n' "$PROG" "$VERSION"
            ;;

        help|--help|-h|"")
            usage
            ;;

        *)
            # Bare text becomes an AI request.
            cmd_run "$*"
            ;;
    esac
}

main "$@"
