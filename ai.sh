#!/usr/bin/env bash
# ============================================================================
# AI // 2244.1122
# Single-file Bash + Python3 + optional Node.js + llama.cpp controller
#
# Append-only architecture:
#   prompt
#     -> event
#     -> transform
#     -> capability gate
#     -> resource governor
#     -> llama
#     -> observe
#     -> validate
#     -> SHA256 lineage
#     -> JSONL ledger
#
# No Ollama.
# No Python dependency for basic execution.
# Python3 enhances structured hashing/ledger operations.
# Node.js is optional and never required for core execution.
# ============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

AI_VERSION="2244.1122.2"
AI_NAME="ai"

ROOT="${AI_ROOT:-${HOME}/_}"
AI_HOME="${AI_HOME:-${HOME}/.ai}"
STATE="${AI_STATE:-${AI_HOME}/.ai-state}"

MODEL_DIR="${AI_MODEL_DIR:-${AI_HOME}/models}"
RUN_DIR="${STATE}/run"
LOG_DIR="${STATE}/log"
DB_DIR="${STATE}/db"
OBJ_DIR="${STATE}/objects"
SESSION_DIR="${STATE}/sessions"

LEDGER="${DB_DIR}/events.jsonl"
STATE_JSON="${DB_DIR}/state.json"
LAST_ERROR="${RUN_DIR}/last_error.log"

mkdir -p \
    "$AI_HOME" \
    "$MODEL_DIR" \
    "$RUN_DIR" \
    "$LOG_DIR" \
    "$DB_DIR" \
    "$OBJ_DIR" \
    "$SESSION_DIR"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

AI_MODEL="${AI_MODEL:-${MODEL_DIR}/qwen2.5-coder-3b-instruct-q4_k_m.gguf}"
AI_THREADS="${AI_THREADS:-8}"
AI_CONTEXT="${AI_CONTEXT:-4096}"
AI_BATCH="${AI_BATCH:-256}"
AI_UBATCH="${AI_UBATCH:-128}"
AI_PREDICT="${AI_PREDICT:-512}"
AI_TIMEOUT="${AI_TIMEOUT:-600}"

AI_TEMP="${AI_TEMP:-0.65}"
AI_TOP_K="${AI_TOP_K:-40}"
AI_TOP_P="${AI_TOP_P:-0.95}"
AI_REPEAT="${AI_REPEAT:-1.10}"

AI_DIRECTION="${AI_DIRECTION:-balanced}"
AI_MODE="${AI_MODE:-normal}"
AI_GRADE="${AI_GRADE:-0}"

AI_SEQUENCE="${AI_SEQUENCE:-0}"
AI_PARENT_HASH="${AI_PARENT_HASH:-GENESIS}"

# bounded by design
AI_MAX_BRANCHES="${AI_MAX_BRANCHES:-4}"
AI_MAX_PROMPT_BYTES="${AI_MAX_PROMPT_BYTES:-32768}"

# ---------------------------------------------------------------------------
# Runtime discovery
# ---------------------------------------------------------------------------

find_llama() {
    local candidates=(
        "${LLAMA_CLI:-}"
        "${HOME}/.local/bin/llama"
        "/home/linuxbrew/.linuxbrew/bin/llama"
        "$(command -v llama 2>/dev/null || true)"
        "$(command -v llama-cli 2>/dev/null || true)"
    )

    local p
    for p in "${candidates[@]}"; do
        [[ -n "$p" ]] || continue
        [[ -x "$p" ]] && {
            printf '%s\n' "$p"
            return 0
        }
    done

    return 1
}

LLAMA="$(find_llama || true)"

# ---------------------------------------------------------------------------
# SHA256
# ---------------------------------------------------------------------------

sha256_text() {
    local value="${1-}"

    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$value" |
            sha256sum |
            awk '{print $1}'
        return
    fi

    if command -v openssl >/dev/null 2>&1; then
        printf '%s' "$value" |
            openssl dgst -sha256 -r |
            awk '{print $1}'
        return
    fi

    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$value" |
            python3 -c '
import sys,hashlib
print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())
'
        return
    fi

    return 127
}

sha256_file() {
    local file="$1"

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 -r "$file" | awk '{print $1}'
    else
        python3 - "$file" <<'PY'
import hashlib
import sys
h = hashlib.sha256()
with open(sys.argv[1], "rb") as f:
    for block in iter(lambda: f.read(1048576), b""):
        h.update(block)
print(h.hexdigest())
PY
    fi
}

# ---------------------------------------------------------------------------
# Time
# ---------------------------------------------------------------------------

utc_now() {
    date -u '+%Y-%m-%dT%H:%M:%S.%NZ'
}

epoch_now() {
    date +%s
}

# ---------------------------------------------------------------------------
# Python structured-data bridge
# ---------------------------------------------------------------------------

py() {
    command -v python3 >/dev/null 2>&1 || return 127

    python3 - "$@"
}

json_escape() {
    py <<'PY'
import json,sys
print(json.dumps(sys.stdin.read().rstrip("\n"), ensure_ascii=False))
PY
}

# ---------------------------------------------------------------------------
# Optional Node bridge
# ---------------------------------------------------------------------------

node_available() {
    command -v node >/dev/null 2>&1
}

node_transform() {
    local input="${1-}"

    node_available || {
        printf '%s' "$input"
        return 0
    }

    NODE_INPUT="$input" node <<'JS'
const input = process.env.NODE_INPUT ?? "";
const result = {
    length: [...input].length,
    bytes: Buffer.byteLength(input, "utf8"),
    normalized: input.normalize("NFC")
};
process.stdout.write(JSON.stringify(result));
JS
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

load_state() {
    [[ -f "$STATE_JSON" ]] || {
        printf '%s\n' \
            '{"sequence":0,"parent":"GENESIS","direction":"balanced","mode":"normal","grade":0}' \
            > "$STATE_JSON"
        return
    }

    if command -v python3 >/dev/null 2>&1; then
        AI_SEQUENCE="$(
            python3 - "$STATE_JSON" <<'PY'
import json,sys
try:
    x=json.load(open(sys.argv[1]))
    print(int(x.get("sequence",0)))
except Exception:
    print(0)
PY
        )"

        AI_PARENT_HASH="$(
            python3 - "$STATE_JSON" <<'PY'
import json,sys
try:
    x=json.load(open(sys.argv[1]))
    print(x.get("parent","GENESIS"))
except Exception:
    print("GENESIS")
PY
        )"
    fi
}

save_state() {
    local sequence="$1"
    local parent="$2"
    local direction="$3"
    local mode="$4"
    local grade="$5"

    if command -v python3 >/dev/null 2>&1; then
        python3 - \
            "$STATE_JSON" \
            "$sequence" \
            "$parent" \
            "$direction" \
            "$mode" \
            "$grade" <<'PY'
import json,sys,tempfile,os

path=sys.argv[1]
obj={
    "sequence":int(sys.argv[2]),
    "parent":sys.argv[3],
    "direction":sys.argv[4],
    "mode":sys.argv[5],
    "grade":int(sys.argv[6])
}

fd,tmp=tempfile.mkstemp(prefix=".state.",dir=os.path.dirname(path))
with os.fdopen(fd,"w",encoding="utf-8") as f:
    json.dump(obj,f,separators=(",",":"),ensure_ascii=False)
    f.write("\n")

os.replace(tmp,path)
PY
    else
        printf \
            '{"sequence":%s,"parent":"%s","direction":"%s","mode":"%s","grade":%s}\n' \
            "$sequence" "$parent" "$direction" "$mode" "$grade" \
            > "$STATE_JSON"
    fi
}

# ---------------------------------------------------------------------------
# Event creation
# ---------------------------------------------------------------------------

event_hash() {
    local sequence="$1"
    local timestamp="$2"
    local prompt_hash="$3"
    local direction="$4"
    local mode="$5"
    local grade="$6"
    local parent="$7"

    sha256_text \
        "${AI_VERSION}|seq=${sequence}|time=${timestamp}|prompt=${prompt_hash}|direction=${direction}|mode=${mode}|grade=${grade}|parent=${parent}"
}

crossfire_hash() {
    local origin="$1"
    local reference="$2"
    local grade="$3"

    sha256_text \
        "${AI_VERSION}|crossfire|origin=${origin}|reference=${reference}|grade=${grade}"
}

# ---------------------------------------------------------------------------
# Resource governor
# ---------------------------------------------------------------------------

memory_percent() {
    if [[ -r /proc/meminfo ]]; then
        awk '
            /MemTotal:/ {total=$2}
            /MemAvailable:/ {avail=$2}
            END {
                if (total > 0)
                    printf "%.0f\n",100*((total-avail)/total)
                else
                    print 0
            }
        ' /proc/meminfo
    else
        printf '0\n'
    fi
}

pressure_level() {
    local used
    used="$(memory_percent)"

    if (( used >= 90 )); then
        printf 'P3\n'
    elif (( used >= 75 )); then
        printf 'P2\n'
    elif (( used >= 55 )); then
        printf 'P1\n'
    else
        printf 'P0\n'
    fi
}

govern() {
    local p
    p="$(pressure_level)"

    case "$p" in
        P0)
            AI_THREADS="${AI_THREADS_BASE:-8}"
            AI_CONTEXT="${AI_CONTEXT_BASE:-4096}"
            AI_PREDICT="${AI_PREDICT_BASE:-512}"
            ;;
        P1)
            AI_THREADS=6
            AI_CONTEXT=3072
            AI_PREDICT=384
            ;;
        P2)
            AI_THREADS=4
            AI_CONTEXT=2048
            AI_PREDICT=256
            ;;
        P3)
            AI_THREADS=2
            AI_CONTEXT=1024
            AI_PREDICT=128
            ;;
    esac

    printf '%s\n' "$p"
}

# ---------------------------------------------------------------------------
# Prompt transformation
# ---------------------------------------------------------------------------

normalize_prompt() {
    local prompt="$1"

    # Preserve meaning while normalizing control characters.
    printf '%s' "$prompt" |
        tr '\r' ' ' |
        tr '\000' ' ' |
        head -c "$AI_MAX_PROMPT_BYTES"
}

transform_prompt() {
    local prompt="$1"
    local mode="$2"
    local direction="$3"

    case "$mode:$direction" in
        normal:*)
            printf '%s' "$prompt"
            ;;

        explore:ascending)
            printf '%s\n\n' "$prompt"
            printf '%s\n' \
                "Explore independent interpretations, identify assumptions, and distinguish evidence from hypothesis."
            ;;

        verify:descending)
            printf '%s\n\n' "$prompt"
            printf '%s\n' \
                "Reduce to the smallest reproducible claim set. Verify hashes, references, constraints, and observable results."
            ;;

        retro:*)
            printf '%s\n\n' "$prompt"
            printf '%s\n' \
                "Compare the current request with its recorded parent state. Do not invent missing history."
            ;;

        *)
            printf '%s' "$prompt"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Capability gate
# ---------------------------------------------------------------------------

capability_check() {
    local action="${1:-model}"

    case "$action" in
        model|read|hash|ledger|inspect)
            return 0
            ;;

        write)
            [[ "${AI_ALLOW_WRITE:-0}" == 1 ]]
            ;;

        execute)
            [[ "${AI_ALLOW_EXEC:-0}" == 1 ]]
            ;;

        network)
            [[ "${AI_ALLOW_NETWORK:-0}" == 1 ]]
            ;;

        *)
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Llama execution
# ---------------------------------------------------------------------------

run_llama() {
    local prompt="$1"
    local output_file="$2"

    : > "$LAST_ERROR"

    [[ -n "$LLAMA" ]] || {
        printf 'llama executable not found\n' > "$LAST_ERROR"
        return 127
    }

    [[ -f "$AI_MODEL" ]] || {
        printf 'model not found: %s\n' "$AI_MODEL" > "$LAST_ERROR"
        return 66
    }

    local prompt_file
    prompt_file="$(mktemp "${RUN_DIR}/prompt.XXXXXX")"

    printf '%s' "$prompt" > "$prompt_file"

    timeout "$AI_TIMEOUT" \
        "$LLAMA" cli \
        -m "$AI_MODEL" \
        -c "$AI_CONTEXT" \
        -b "$AI_BATCH" \
        -ub "$AI_UBATCH" \
        -t "$AI_THREADS" \
        -n "$AI_PREDICT" \
        --temp "$AI_TEMP" \
        --top-k "$AI_TOP_K" \
        --top-p "$AI_TOP_P" \
        --repeat-penalty "$AI_REPEAT" \
        < "$prompt_file" \
        > "$output_file" \
        2> "$LAST_ERROR"

    local rc=$?
    rm -f "$prompt_file"

    return "$rc"
}

# ---------------------------------------------------------------------------
# Ledger
# ---------------------------------------------------------------------------

append_event() {
    local timestamp="$1"
    local sequence="$2"
    local parent="$3"
    local event="$4"
    local prompt_hash="$5"
    local result_hash="$6"
    local direction="$7"
    local mode="$8"
    local grade="$9"
    local pressure="${10}"
    local status="${11}"
    local crossfire="${12}"

    if command -v python3 >/dev/null 2>&1; then
        python3 - \
            "$LEDGER" \
            "$timestamp" \
            "$sequence" \
            "$parent" \
            "$event" \
            "$prompt_hash" \
            "$result_hash" \
            "$direction" \
            "$mode" \
            "$grade" \
            "$pressure" \
            "$status" \
            "$crossfire" <<'PY'
import json,sys,os

(
    path,
    timestamp,
    sequence,
    parent,
    event,
    prompt_hash,
    result_hash,
    direction,
    mode,
    grade,
    pressure,
    status,
    crossfire
)=sys.argv[1:]

obj={
    "version":"2244.1122.2",
    "datetime":timestamp,
    "sequence":int(sequence),
    "parent":parent,
    "event":event,
    "prompt_sha256":prompt_hash,
    "result_sha256":result_hash,
    "direction":direction,
    "mode":mode,
    "grade":int(grade),
    "pressure":pressure,
    "status":status,
    "crossfire_sha256":crossfire
}

with open(path,"a",encoding="utf-8") as f:
    f.write(json.dumps(obj,separators=(",",":"),ensure_ascii=False))
    f.write("\n")
PY
    else
        printf \
            '{"version":"2244.1122.2","datetime":"%s","sequence":%s,"parent":"%s","event":"%s","prompt_sha256":"%s","result_sha256":"%s","direction":"%s","mode":"%s","grade":%s,"pressure":"%s","status":"%s","crossfire_sha256":"%s"}\n' \
            "$timestamp" "$sequence" "$parent" "$event" \
            "$prompt_hash" "$result_hash" "$direction" \
            "$mode" "$grade" "$pressure" "$status" "$crossfire" \
            >> "$LEDGER"
    fi
}

# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------

process_prompt() {
    local raw="$1"

    load_state

    local timestamp
    timestamp="$(utc_now)"

    local sequence=$((AI_SEQUENCE + 1))
    local parent="$AI_PARENT_HASH"

    local normalized
    normalized="$(normalize_prompt "$raw")"

    local prompt_hash
    prompt_hash="$(sha256_text "$normalized")"

    local transformed
    transformed="$(
        transform_prompt \
            "$normalized" \
            "$AI_MODE" \
            "$AI_DIRECTION"
    )"

    local pressure
    pressure="$(govern)"

    local event
    event="$(event_hash \
        "$sequence" \
        "$timestamp" \
        "$prompt_hash" \
        "$AI_DIRECTION" \
        "$AI_MODE" \
        "$AI_GRADE" \
        "$parent"
    )"

    local crossfire
    crossfire="$(
        crossfire_hash \
            "$event" \
            "${AI_REFERENCE:-origin}" \
            "$AI_GRADE"
    )"

    local output
    output="${RUN_DIR}/result-${sequence}.txt"

    printf '\n[%s] seq=%s mode=%s direction=%s pressure=%s\n' \
        "$timestamp" \
        "$sequence" \
        "$AI_MODE" \
        "$AI_DIRECTION" \
        "$pressure" \
        >&2

    if ! capability_check model; then
        printf 'model capability unavailable\n' >&2
        return 77
    fi

    if run_llama "$transformed" "$output"; then
        local status="complete"
        local result_hash
        result_hash="$(sha256_file "$output")"

        append_event \
            "$timestamp" \
            "$sequence" \
            "$parent" \
            "$event" \
            "$prompt_hash" \
            "$result_hash" \
            "$AI_DIRECTION" \
            "$AI_MODE" \
            "$AI_GRADE" \
            "$pressure" \
            "$status" \
            "$crossfire"

        save_state \
            "$sequence" \
            "$event" \
            "$AI_DIRECTION" \
            "$AI_MODE" \
            "$AI_GRADE"

        AI_SEQUENCE="$sequence"
        AI_PARENT_HASH="$event"

        cat "$output"
        return 0
    fi

    local rc=$?
    local result_hash
    result_hash="$(sha256_text "ERROR:${rc}:$(cat "$LAST_ERROR" 2>/dev/null || true)")"

    append_event \
        "$timestamp" \
        "$sequence" \
        "$parent" \
        "$event" \
        "$prompt_hash" \
        "$result_hash" \
        "$AI_DIRECTION" \
        "$AI_MODE" \
        "$AI_GRADE" \
        "$pressure" \
        "failed:${rc}" \
        "$crossfire"

    printf 'execution failed rc=%s\n' "$rc" >&2
    cat "$LAST_ERROR" >&2 2>/dev/null || true

    return "$rc"
}

# ---------------------------------------------------------------------------
# Interactive commands
# ---------------------------------------------------------------------------

show_status() {
    load_state

    printf '%s\n' \
        "AI_VERSION   = $AI_VERSION" \
        "SEQUENCE     = $AI_SEQUENCE" \
        "PARENT       = $AI_PARENT_HASH" \
        "MODEL        = $AI_MODEL" \
        "LLAMA        = ${LLAMA:-missing}" \
        "DIRECTION    = $AI_DIRECTION" \
        "MODE         = $AI_MODE" \
        "GRADE        = $AI_GRADE" \
        "PRESSURE     = $(pressure_level)" \
        "MEMORY       = $(memory_percent)%" \
        "LEDGER       = $LEDGER"
}

show_last() {
    [[ -f "$LEDGER" ]] || return 0
    tail -n "${1:-1}" "$LEDGER"
}

show_help() {
    cat <<'EOF'
ai — 2244/1122 interactive controller

Execution:
  ai run "prompt"
  ai repl

State:
  ai status
  ai last [N]

Modes:
  ai mode normal
  ai mode explore
  ai mode retro
  ai mode verify

Directions:
  ai direction ascending
  ai direction balanced
  ai direction descending

Grades:
  ai grade 0..3

References:
  ai reference NAME

Hashes:
  ai hash "text"
  ai crossfire HASH REFERENCE GRADE

System:
  ai doctor
  ai env
  ai help

Environment:
  AI_MODEL
  AI_THREADS
  AI_CONTEXT
  AI_PREDICT
  AI_TIMEOUT
  AI_ALLOW_WRITE=1
  AI_ALLOW_EXEC=1
  AI_ALLOW_NETWORK=1
EOF
}

doctor() {
    printf 'AI doctor\n'
    printf '---------\n'

    command -v bash >/dev/null &&
        printf 'bash       OK\n' ||
        printf 'bash       MISSING\n'

    command -v sha256sum >/dev/null &&
        printf 'sha256sum  OK\n' ||
        printf 'sha256sum  FALLBACK\n'

    command -v python3 >/dev/null &&
        printf 'python3    OK\n' ||
        printf 'python3    OPTIONAL/MISSING\n'

    node_available &&
        printf 'node       OK\n' ||
        printf 'node       OPTIONAL/MISSING\n'

    [[ -n "$LLAMA" ]] &&
        printf 'llama      OK: %s\n' "$LLAMA" ||
        printf 'llama      MISSING\n'

    [[ -f "$AI_MODEL" ]] &&
        printf 'model      OK: %s\n' "$AI_MODEL" ||
        printf 'model      MISSING: %s\n' "$AI_MODEL"

    printf 'memory     %s%%\n' "$(memory_percent)"
    printf 'pressure   %s\n' "$(pressure_level)"
}

repl() {
    printf 'AI interactive REPL — type /help or /quit\n'

    while IFS= read -r -p 'ai> ' line; do
        [[ -n "$line" ]] || continue

        case "$line" in
            /quit|/exit)
                break
                ;;

            /help)
                show_help
                ;;

            /status)
                show_status
                ;;

            /last*)
                set -- $line
                show_last "${2:-1}"
                ;;

            /mode\ *)
                AI_MODE="${line#"/mode "}"
                printf 'mode=%s\n' "$AI_MODE"
                ;;

            /direction\ *)
                AI_DIRECTION="${line#"/direction "}"
                printf 'direction=%s\n' "$AI_DIRECTION"
                ;;

            /grade\ *)
                AI_GRADE="${line#"/grade "}"
                printf 'grade=%s\n' "$AI_GRADE"
                ;;

            /reference\ *)
                AI_REFERENCE="${line#"/reference "}"
                printf 'reference=%s\n' "$AI_REFERENCE"
                ;;

            *)
                process_prompt "$line"
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

main() {
    load_state

    case "${1:-repl}" in
        run)
            shift
            process_prompt "${*:-}"
            ;;

        repl)
            repl
            ;;

        status)
            show_status
            ;;

        last)
            show_last "${2:-1}"
            ;;

        hash)
            sha256_text "${2:-}"
            ;;

        crossfire)
            crossfire_hash \
                "${2:?origin hash}" \
                "${3:?reference}" \
                "${4:-0}"
            ;;

        mode)
            AI_MODE="${2:?mode}"
            printf 'mode=%s\n' "$AI_MODE"
            ;;

        direction)
            AI_DIRECTION="${2:?direction}"
            printf 'direction=%s\n' "$AI_DIRECTION"
            ;;

        grade)
            AI_GRADE="${2:?grade}"
            printf 'grade=%s\n' "$AI_GRADE"
            ;;

        reference)
            AI_REFERENCE="${2:?reference}"
            printf 'reference=%s\n' "$AI_REFERENCE"
            ;;

        doctor)
            doctor
            ;;

        env)
            env | grep '^AI_' | sort
            ;;

        help|-h|--help)
            show_help
            ;;

        *)
            process_prompt "$*"
            ;;
    esac
}

trap '
    rc=$?
    printf "[ai] interrupted/error rc=%s at %s\n" "$rc" "$(utc_now)" >&2
    exit "$rc"
' ERR

main "$@"
