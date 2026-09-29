#!/usr/bin/env bash
# =============================================================================
# GENESIS/HX ai.sh v253.1.0
# Unified local AI controller: llama.cpp + bounded state + SHA lineage
# Android/Termux/PRoot safe profile. Python is optional; Ollama is not used.
# =============================================================================
set -Eeuo pipefail
IFS=$'\n\t'

AI_VERSION="253.1.0"
AI_GENESIS="2244-1"
AI_TOPOLOGY="2pi/8"
AI_LANES=(analytical architectural critical creative implementation adversarial systems synthesis)

# ---- canonical filesystem ---------------------------------------------------
AI_HOME="${AI_HOME:-$HOME/.ai}"
AI_PROJECT_ROOT="${AI_PROJECT_ROOT:-$HOME/_}"
AI_BIN="${AI_BIN:-$AI_PROJECT_ROOT/ai.sh}"
AI_STATE_DIR="${AI_STATE_DIR:-$AI_HOME/state}"
AI_FILE_ROOT="${AI_FILE_ROOT:-$AI_HOME/files}"
AI_MODEL_DIR="${AI_MODEL_DIR:-$AI_HOME/models}"
LLAMA_CLI="${LLAMA_CLI:-$HOME/.local/bin/llama}"

RUN_DIR="$AI_STATE_DIR/run"
LOG_DIR="$AI_STATE_DIR/logs"
OBJECTS="$AI_STATE_DIR/objects"
SESSIONS="$AI_STATE_DIR/sessions"
LOCKS="$AI_STATE_DIR/locks"
REALTIME_DIR="$AI_STATE_DIR/realtime"
EVENTS="$AI_STATE_DIR/events.jsonl"
LEDGER="$AI_STATE_DIR/ledger.jsonl"
MEMORY="$AI_STATE_DIR/memory.json"
FILE_INDEX="$AI_STATE_DIR/file_index.json"
CONFIG_FILE="$AI_HOME/env"
LAST_ERROR_FILE="$RUN_DIR/last_error.log"

PRIMARY_MODEL="$AI_MODEL_DIR/qwen2.5-coder-3b-instruct-q4_k_m.gguf"
FALLBACK_MODEL="$AI_MODEL_DIR/qwen2.5-1.5b-instruct-q4_k_m.gguf"

# ---- safe mobile defaults ---------------------------------------------------
AI_CTX="${AI_CTX:-2048}"
AI_BATCH="${AI_BATCH:-128}"
AI_UBATCH="${AI_UBATCH:-64}"
AI_THREADS="${AI_THREADS:-4}"
AI_THREADS_BATCH="${AI_THREADS_BATCH:-4}"
AI_PREDICT="${AI_PREDICT:-192}"
AI_GPU_LAYERS="${AI_GPU_LAYERS:-0}"
AI_TEMP="${AI_TEMP:-0.65}"
AI_TOP_K="${AI_TOP_K:-40}"
AI_TOP_P="${AI_TOP_P:-0.95}"
AI_REPEAT="${AI_REPEAT:-1.10}"
AI_MLOCK="${AI_MLOCK:-0}"
AI_VIEWS="${AI_VIEWS:-8}"
AI_CONCURRENCY="${AI_CONCURRENCY:-1}"
AI_DEPTH="${AI_DEPTH:-1}"
AI_SYNTHESIS="${AI_SYNTHESIS:-0}"
AI_TIMEOUT="${AI_TIMEOUT:-600}"
AI_PROMPT_BYTES="${AI_PROMPT_BYTES:-5500}"
AI_REALTIME_MAX_BYTES="${AI_REALTIME_MAX_BYTES:-1200}"
AI_RECALL_TOP="${AI_RECALL_TOP:-4}"
AI_MAX_FILE_BYTES="${AI_MAX_FILE_BYTES:-262144}"
AI_CHUNK_BYTES="${AI_CHUNK_BYTES:-4096}"
AI_AUTO_REINDEX="${AI_AUTO_REINDEX:-0}"
AI_AUTO_REVIEW="${AI_AUTO_REVIEW:-0}"
AI_REALTIME="${AI_REALTIME:-1}"
AI_REALTIME_TIMEOUT="${AI_REALTIME_TIMEOUT:-12}"
AI_MEM_RESERVE_MB="${AI_MEM_RESERVE_MB:-2200}"
AI_MAX_LEDGER_LINES="${AI_MAX_LEDGER_LINES:-5000}"
AI_MAX_EVENTS_LINES="${AI_MAX_EVENTS_LINES:-5000}"
AI_KEEP_OBJECTS="${AI_KEEP_OBJECTS:-2000}"
AI_WORKSPACE_MAX_FILES="${AI_WORKSPACE_MAX_FILES:-4000}"
AI_SSH_HOST="${AI_SSH_HOST:-127.0.0.1}"
AI_SSH_PORT="${AI_SSH_PORT:-2222}"
AI_MODEL="${AI_MODEL:-primary}"

export LC_ALL="${LC_ALL:-C.UTF-8}"

mkdirs() { mkdir -p "$AI_HOME" "$AI_STATE_DIR" "$RUN_DIR" "$LOG_DIR" "$OBJECTS" "$SESSIONS" "$LOCKS" "$REALTIME_DIR" "$AI_FILE_ROOT" "$AI_MODEL_DIR"; }
mkdirs

# ---- logging / errors -------------------------------------------------------
timestamp() { date +%s; }
iso_now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log() { printf '[%s] %s\n' "$(iso_now)" "$*" >&2; }
info() { log "INFO $*"; }
warn() { log "WARN $*"; }
die() { log "ERROR $*"; exit 1; }

on_err() {
    local rc=$? line=${1:-?} cmd=${2:-?}
    printf 'rc=%s line=%s cmd=%s\n' "$rc" "$line" "$cmd" > "$LAST_ERROR_FILE" || true
}
trap 'on_err "$LINENO" "$BASH_COMMAND"' ERR

# ---- validation -------------------------------------------------------------
is_uint() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }
is_num() { [[ "${1:-}" =~ ^[0-9]+([.][0-9]+)?$ ]]; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

validate_config() {
    local x
    for x in AI_CTX AI_BATCH AI_UBATCH AI_THREADS AI_THREADS_BATCH AI_PREDICT AI_GPU_LAYERS AI_VIEWS AI_CONCURRENCY AI_DEPTH AI_TIMEOUT AI_PROMPT_BYTES AI_REALTIME_MAX_BYTES AI_RECALL_TOP AI_MAX_FILE_BYTES AI_CHUNK_BYTES AI_MEM_RESERVE_MB; do
        is_uint "${!x}" || die "$x must be an integer"
    done
    for x in AI_TEMP AI_TOP_K AI_TOP_P AI_REPEAT; do is_num "${!x}" || die "$x must be numeric"; done
    (( AI_CTX >= 256 && AI_CTX <= 8192 )) || die 'AI_CTX outside safe range 256..8192'
    (( AI_VIEWS >= 1 && AI_VIEWS <= 8 )) || die 'AI_VIEWS must be 1..8'
    (( AI_CONCURRENCY == 1 )) || die 'AI_CONCURRENCY must remain 1 on this mobile profile'
    (( AI_DEPTH >= 1 && AI_DEPTH <= 32 )) || die 'AI_DEPTH must be 1..32'
    (( AI_PROMPT_BYTES >= 512 )) || die 'AI_PROMPT_BYTES too small'
    (( AI_REALTIME_MAX_BYTES >= 0 )) || die 'AI_REALTIME_MAX_BYTES invalid'
}
validate_config

# ---- JSON safety ------------------------------------------------------------
json_or_null() {
    local v="${1-}"
    if [[ -n "$v" ]] && jq -e . >/dev/null 2>&1 <<<"$v"; then printf '%s' "$v"; else printf 'null'; fi
}
require_json() { jq -e . >/dev/null 2>&1 <<<"${1-}"; }

atomic_write() {
    local target="$1"; shift
    local tmp="${target}.tmp.$$"
    cat > "$tmp"
    mv -f "$tmp" "$target"
}

append_event() {
    local type="${1:?event type required}" payload="${2:-}" payload_json
    payload_json="$(json_or_null "$payload")"
    jq -cn --arg timestamp "$(timestamp)" --arg iso "$(iso_now)" --arg type "$type" \
      --arg version "$AI_VERSION" --arg genesis "$AI_GENESIS" --argjson payload "$payload_json" \
      '{timestamp:($timestamp|tonumber),iso:$iso,schema:"GENESIS/HX",version:$version,genesis:$genesis,type:$type,payload:$payload}' >> "$EVENTS"
    rotate_jsonl "$EVENTS" "$AI_MAX_EVENTS_LINES"
}

append_ledger() {
    local type="${1:?ledger type required}" material="${2-}" payload="${3-}"
    local ts sha md5 mod7 prev payload_json
    ts="$(timestamp)"; sha="$(sha256_text "$material")"; md5="$(md5_text "$material")"; mod7=$((ts % 7))
    prev="$(tail -n 1 "$LEDGER" 2>/dev/null | jq -r '.sha256 // ""' 2>/dev/null || true)"
    payload_json="$(json_or_null "$payload")"
    jq -cn --arg type "$type" --arg genesis "$AI_GENESIS" --arg version "$AI_VERSION" \
      --arg timestamp "$ts" --arg sha "$sha" --arg md5 "$md5" --arg prev "$prev" \
      --argjson mod7 "$mod7" --argjson payload "$payload_json" \
      '{schema:"GENESIS/HX",genesis:$genesis,version:$version,type:$type,timestamp:($timestamp|tonumber),timestamp_mod7:$mod7,prev_sha256:$prev,sha256:$sha,md5_legacy:$md5,payload:$payload}' >> "$LEDGER"
    rotate_jsonl "$LEDGER" "$AI_MAX_LEDGER_LINES"
    printf '%s\n' "$sha"
}

rotate_jsonl() {
    local file="$1" max="$2" lines
    [[ -f "$file" ]] || return 0
    lines=$(wc -l < "$file" 2>/dev/null || echo 0)
    (( lines > max )) || return 0
    tail -n "$max" "$file" > "${file}.tmp.$$" && mv -f "${file}.tmp.$$" "$file"
}

# ---- hashes -----------------------------------------------------------------
sha256_text() { printf '%s' "${1-}" | sha256sum | awk '{print $1}'; }
md5_text() { printf '%s' "${1-}" | md5sum | awk '{print $1}'; }
hash_file() { sha256sum "$1" | awk '{print $1}'; }
normalize_text() { tr '\r' ' ' <<<"${1-}" | sed -E 's/[[:space:]]+/ /g; s/^ +//; s/ +$//'; }
mod7() { printf '%s' "$(( $(timestamp) % 7 ))"; }

# ---- UTF-8-safe-ish bounded text -------------------------------------------
fit_bytes() {
    local text="${1-}" max="${2:-$AI_PROMPT_BYTES}"
    LC_ALL=C printf '%s' "$text" | head -c "$max"
}
fit_prompt() { fit_bytes "$1" "$AI_PROMPT_BYTES"; }

# ---- runtime / memory -------------------------------------------------------
mem_available_mb() {
    awk '/MemAvailable:/ {printf "%d", $2/1024; exit}' /proc/meminfo 2>/dev/null || printf '0'
}
resource_ok() {
    local avail; avail="$(mem_available_mb)"
    [[ "$avail" =~ ^[0-9]+$ ]] || return 0
    (( avail >= AI_MEM_RESERVE_MB ))
}

# ---- model resolution -------------------------------------------------------
resolve_model() {
    local requested="${1:-$AI_MODEL}"
    case "$requested" in
      primary|main) [[ -f "$PRIMARY_MODEL" ]] && printf '%s' "$PRIMARY_MODEL" || printf '%s' "$FALLBACK_MODEL";;
      fallback|small) printf '%s' "$FALLBACK_MODEL";;
      /*) printf '%s' "$requested";;
      *) die "unknown model selector: $requested";;
    esac
}
valid_gguf() { [[ -f "$1" ]] && [[ "$(head -c 4 "$1" 2>/dev/null || true)" == 'GGUF' ]]; }
select_model() {
    local m; m="$(resolve_model "$AI_MODEL")"
    valid_gguf "$m" && { printf '%s' "$m"; return; }
    if valid_gguf "$FALLBACK_MODEL"; then warn "primary unavailable; using fallback"; printf '%s' "$FALLBACK_MODEL"; return; fi
    die "no valid GGUF model available"
}

# ---- llama.cpp adapter ------------------------------------------------------
LLAMA_HELP_CACHE=""
llama_help() {
    if [[ -z "$LLAMA_HELP_CACHE" ]]; then
        LLAMA_HELP_CACHE="$($LLAMA_CLI cli --help 2>&1 || true)"
    fi
    printf '%s' "$LLAMA_HELP_CACHE"
}
llama_help_has() { llama_help | grep -q -- "$1"; }
llama_infer_once() {
    local model="$1" prompt="$2" out="$3"
    local -a args
    args=(cli -m "$model")
    llama_help_has '--ctx-size' && args+=(--ctx-size "$AI_CTX") || llama_help_has ' -c ' && args+=(-c "$AI_CTX") || true
    llama_help_has '--batch-size' && args+=(--batch-size "$AI_BATCH") || llama_help_has ' -b ' && args+=(-b "$AI_BATCH") || true
    llama_help_has '--ubatch-size' && args+=(--ubatch-size "$AI_UBATCH") || true
    llama_help_has '--predict' && args+=(--predict "$AI_PREDICT") || llama_help_has ' -n ' && args+=(-n "$AI_PREDICT") || true
    llama_help_has '--threads' && args+=(--threads "$AI_THREADS") || llama_help_has ' -t ' && args+=(-t "$AI_THREADS") || true
    llama_help_has '--threads-batch' && args+=(--threads-batch "$AI_THREADS_BATCH") || true
    llama_help_has '--temp' && args+=(--temp "$AI_TEMP") || true
    llama_help_has '--top-k' && args+=(--top-k "$AI_TOP_K") || true
    llama_help_has '--top-p' && args+=(--top-p "$AI_TOP_P") || true
    llama_help_has '--repeat-penalty' && args+=(--repeat-penalty "$AI_REPEAT") || true
    llama_help_has '--n-gpu-layers' && args+=(--n-gpu-layers "$AI_GPU_LAYERS") || true
    [[ "$AI_MLOCK" == 1 ]] && llama_help_has '--mlock' && args+=(--mlock) || true
    : > "$LAST_ERROR_FILE"
    if timeout "$AI_TIMEOUT" "$LLAMA_CLI" "${args[@]}" >"$out" 2>"$RUN_DIR/llama.stderr" <<<"$prompt"; then
        [[ -s "$out" ]]
    else
        local rc=$?
        printf 'llama rc=%s model=%s\n' "$rc" "$model" > "$LAST_ERROR_FILE"
        return "$rc"
    fi
}
llama_infer() {
    local model="$1" prompt="$2" out="$3"
    if llama_infer_once "$model" "$prompt" "$out"; then return 0; fi
    if [[ "$model" != "$FALLBACK_MODEL" ]] && valid_gguf "$FALLBACK_MODEL"; then
        warn 'primary inference failed; retrying once with fallback model'
        AI_CTX=1536; AI_BATCH=96; AI_UBATCH=48; AI_THREADS=3; AI_THREADS_BATCH=3; AI_PREDICT=128
        llama_infer_once "$FALLBACK_MODEL" "$prompt" "$out" && return 0
    fi
    return 1
}

# ---- initialization ---------------------------------------------------------
init_state() {
    mkdirs
    [[ -f "$MEMORY" ]] || printf '{"schema":"GENESIS/HX/MEMORY/1","genesis":"%s","items":[]}\n' "$AI_GENESIS" > "$MEMORY"
    [[ -f "$FILE_INDEX" ]] || printf '{"schema":"GENESIS/HX/INDEX/1","root":"%s","files":[],"count":0}\n' "$AI_PROJECT_ROOT" > "$FILE_INDEX"
    : > /dev/null
}

# ---- safe indexing: NEVER command-substitute NUL streams -------------------
should_skip_path() {
    local f="$1"
    case "$f" in
      */.git/*|*/.ai/models/*|*/.ai/state/*|*/node_modules/*|*/__pycache__/*|*.gguf) return 0;;
      *) return 1;;
    esac
}
index_tree() {
    local root="${1:-$AI_PROJECT_ROOT}" tmp count=0 f sha size mtime rel
    [[ -d "$root" ]] || die "index root not found: $root"
    tmp="$FILE_INDEX.tmp.$$"
    printf '{"schema":"GENESIS/HX/INDEX/1","root":%s,"generated_at":%s,"files":[' \
      "$(jq -Rn --arg x "$root" '$x')" "$(timestamp)" > "$tmp"
    local first=1
    while IFS= read -r -d '' f; do
        should_skip_path "$f" && continue
        [[ -f "$f" ]] || continue
        size=$(wc -c < "$f" 2>/dev/null || echo 0)
        (( size <= AI_MAX_FILE_BYTES )) || continue
        sha=$(hash_file "$f")
        mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
        rel="${f#"$root"/}"
        if (( first == 0 )); then printf ',' >> "$tmp"; fi
        first=0
        jq -cn --arg path "$rel" --arg sha "$sha" --arg size "$size" --arg mtime "$mtime" \
          '{path:$path,sha256:$sha,bytes:($size|tonumber),mtime:($mtime|tonumber)}' >> "$tmp"
        count=$((count+1))
        (( count >= AI_WORKSPACE_MAX_FILES )) && break
    done < <(find "$root" -type f -print0 2>/dev/null)
    printf '],"count":%d}\n' "$count" >> "$tmp"
    jq -e . "$tmp" >/dev/null || { rm -f "$tmp"; die 'index JSON validation failed'; }
    mv -f "$tmp" "$FILE_INDEX"
    append_event index "$(jq -cn --arg root "$root" --arg count "$count" '{root:$root,count:($count|tonumber)}')"
    info "indexed $count files under $root"
}

hydrate_file() {
    local f="${1:?file required}" sha chunk_dir i=0 chunk chunk_sha
    [[ -f "$f" ]] || return 1
    sha="$(hash_file "$f")"; chunk_dir="$OBJECTS/$sha"; mkdir -p "$chunk_dir"
    : > "$chunk_dir/manifest.jsonl"
    while IFS= read -r chunk; do
        [[ -n "$chunk" ]] || continue
        chunk_sha="$(sha256_text "$chunk")"
        printf '%s\n' "$chunk" > "$chunk_dir/$i.txt"
        jq -cn --arg file "$f" --arg parent "$sha" --arg chunk_sha "$chunk_sha" --arg index "$i" \
          '{type:"chunk",file:$file,parent_sha256:$parent,chunk_sha256:$chunk_sha,index:($index|tonumber)}' >> "$chunk_dir/manifest.jsonl"
        i=$((i+1))
    done < <(awk -v n="$AI_CHUNK_BYTES" '{ line=$0 ORS; while(length(line)>n){print substr(line,1,n); line=substr(line,n+1)} if(length(line)) print line }' "$f" 2>/dev/null)
    jq -cn --arg file "$f" --arg sha "$sha" --arg chunks "$i" \
      '{schema:"GENESIS/HX/CHUNKS/1",file:$file,parent_sha256:$sha,chunks:($chunks|tonumber)}' > "$chunk_dir/manifest.json"
    printf '%s\n' "$sha"
}

# ---- recall -----------------------------------------------------------------
recall() {
    local q="${1-}" top="${2:-$AI_RECALL_TOP}"
    [[ -f "$FILE_INDEX" ]] || return 0
    local terms; terms="$(normalize_text "$q")"
    jq -r --arg q "$terms" --argjson top "$top" '
      .files // [] | map(select(.path|test("ai\\.sh|bootstrap|bashrc|env|README|schema|state";"i"))) |
      .[:$top][] | [.path,.sha256,.bytes] | @tsv' "$FILE_INDEX" 2>/dev/null || true
}

# ---- realtime: compact public observation, not identity inference ----------
btc_snapshot() {
    [[ "$AI_REALTIME" == 1 ]] || return 0
    require_cmd curl
    local tmp="$REALTIME_DIR/latest.json.tmp.$$" body json
    if ! body="$(curl -fsS --max-time "$AI_REALTIME_TIMEOUT" 'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd,eur' 2>/dev/null)"; then
        warn 'realtime snapshot unavailable'
        return 0
    fi
    json="$(jq -cn --arg fetched "$(iso_now)" --argjson data "$(json_or_null "$body")" \
      '{schema:"GENESIS/HX/REALTIME/1",source:"CoinGecko",fetched_at:$fetched,data:$data}')"
    printf '%s\n' "$(fit_bytes "$json" "$AI_REALTIME_MAX_BYTES")" > "$tmp"
    mv -f "$tmp" "$REALTIME_DIR/latest.json"
    printf '%s\n' "$json" >> "$REALTIME_DIR/ledger.jsonl"
    rotate_jsonl "$REALTIME_DIR/ledger.jsonl" 200
}

# ---- prompts / POVs ---------------------------------------------------------
lane_instruction() {
    case "$1" in
      analytical) printf 'Analyze the task as a constrained problem. Separate facts, assumptions, dependencies, and uncertainty.';;
      architectural) printf 'Design the smallest robust architecture. Identify boundaries, interfaces, state, failure modes, and migration steps.';;
      critical) printf 'Try to falsify the proposed approach. Find contradictions, hidden coupling, unsafe assumptions, and failure cases.';;
      creative) printf 'Generate practical alternatives that preserve the constraints. Prefer simple mechanisms over ornamental complexity.';;
      implementation) printf 'Turn the task into executable implementation steps. Focus on Bash, llama.cpp, JSONL, SHA256, and bounded resources.';;
      adversarial) printf 'Act as a hostile test engineer. Look for injection, malformed JSON, NUL bytes, races, resource exhaustion, and corrupted state.';;
      systems) printf 'Evaluate the whole lifecycle: input, normalization, inference, persistence, recovery, observability, and storage growth.';;
      synthesis) printf 'Reconcile the strongest compatible findings into one concise actionable plan. Do not invent evidence.';;
    esac
}

build_prompt() {
    local task="$1" lane="$2" genesis="$3" tasksha="$4" recall_text="$5" realtime="$6"
    fit_prompt "You are one logical lane in GENESIS/HX.
GENESIS=$AI_GENESIS
TOPOLOGY=$AI_TOPOLOGY
LANE=$lane
TASK_SHA256=$tasksha
GENESIS_SHA256=$genesis

ROLE:
$(lane_instruction "$lane")

SEMANTIC INVARIANTS:
- SHA256 denotes lineage/integrity, not truth or causality.
- MD5 is legacy metadata only.
- mod7 is a deterministic time bucket only.
- entropy is statistical unless explicitly stated otherwise.
- realtime data is an external observation and must be attributed.
- never expose, infer, or request private keys, seed phrases, passwords, or tokens.
- do not claim a tool was executed unless its result is present.

TASK:
$task

BOUNDED RECALL:
$recall_text

REALTIME SNAPSHOT:
$realtime

OUTPUT:
Return a concise analysis with: FINDINGS, RISKS, ACTIONS. Preserve uncertainty. Do not emit JSON unless asked."
}

persist_pov() {
    local runid="$1" round="$2" lane="$3" tasksha="$4" genesis="$5" text="$6"
    local sha obj
    sha="$(sha256_text "$text")"; obj="$OBJECTS/$sha"
    mkdir -p "$obj"
    printf '%s\n' "$text" > "$obj/pov.txt"
    jq -cn --arg schema 'GENESIS/HX/POV/1' --arg run "$runid" --arg round "$round" --arg lane "$lane" \
      --arg task "$tasksha" --arg genesis "$genesis" --arg sha "$sha" --arg created "$(iso_now)" \
      '{schema:$schema,run_id:$run,round:($round|tonumber),lane:$lane,task_sha256:$task,genesis_sha256:$genesis,sha256:$sha,created_at:$created}' > "$obj/pov.json"
    printf '%s\n' "$sha"
}

select_povs() {
    local tasksha="$1" genesis="$2" round="$3" tmp="$RUN_DIR/selected.$$"
    : > "$tmp"
    find "$OBJECTS" -mindepth 2 -maxdepth 2 -type f -name pov.json -print0 2>/dev/null |
    while IFS= read -r -d '' f; do
        jq -e --arg task "$tasksha" --arg gen "$genesis" --arg round "$round" \
          'select(.task_sha256==$task and .genesis_sha256==$gen and (.round|tostring)==$round)' "$f" >/dev/null 2>&1 && printf '%s\n' "$f" >> "$tmp"
    done
    cat "$tmp"; rm -f "$tmp"
}

consensus() {
    local runid="$1" tasksha="$2" genesis="$3" round="$4" out="$RUN_DIR/consensus.txt"
    : > "$out"
    local files=() f lane text
    while IFS= read -r f; do files+=("$f"); done < <(select_povs "$tasksha" "$genesis" "$round")
    for f in "${files[@]}"; do
        lane="$(jq -r '.lane' "$f")"; text="$(cat "${f%/pov.json}/pov.txt")"
        printf '\n[%s]\n%s\n' "$lane" "$text" >> "$out"
    done
    printf '%s\n' "$out"
}

# ---- run engine -------------------------------------------------------------
run_engine() {
    local raw_task="${1:?task required}" task tasksha genesis runid round=1 model
    task="$(normalize_text "$raw_task")"; [[ -n "$task" ]] || die 'empty task'
    tasksha="$(sha256_text "$task")"; genesis="$(sha256_text "$AI_GENESIS:$AI_VERSION:$AI_TOPOLOGY")"
    runid="$(sha256_text "$tasksha:$(timestamp):$$")"
    model="$(select_model)"
    printf '%s\n' "$runid" > "$RUN_DIR/current"
    jq -cn --arg run "$runid" --arg task "$tasksha" --arg genesis "$genesis" --arg started "$(iso_now)" \
      '{schema:"GENESIS/HX/RUN/1",run_id:$run,task_sha256:$task,genesis_sha256:$genesis,started_at:$started,status:"running"}' > "$RUN_DIR/start.json"
    append_event run_start "$(jq -cn --arg run "$runid" --arg task "$tasksha" '{run_id:$run,task_sha256:$task}')"
    append_ledger run_start "$task" "$(jq -cn --arg run "$runid" '{run_id:$run}')" >/dev/null

    if ! resource_ok; then
        warn 'memory reserve is below threshold; switching to fallback/single-view profile'
        model="$FALLBACK_MODEL"; AI_VIEWS=1; AI_PREDICT=128; AI_CTX=1536; AI_BATCH=96; AI_UBATCH=48; AI_THREADS=3; AI_THREADS_BATCH=3
    fi

    local recall_text realtime="none" lane prompt out text sha i=0
    recall_text="$(recall "$task" "$AI_RECALL_TOP")"
    if [[ "$AI_AUTO_REINDEX" == 1 ]]; then index_tree "$AI_PROJECT_ROOT"; fi
    btc_snapshot || true
    [[ -f "$REALTIME_DIR/latest.json" ]] && realtime="$(fit_bytes "$(cat "$REALTIME_DIR/latest.json")" "$AI_REALTIME_MAX_BYTES")"

    for lane in "${AI_LANES[@]}"; do
        (( i < AI_VIEWS )) || break
        prompt="$(build_prompt "$task" "$lane" "$genesis" "$tasksha" "$recall_text" "$realtime")"
        out="$RUN_DIR/${runid}.${lane}.txt"
        info "lane=$lane view=$((i+1))/$AI_VIEWS"
        if llama_infer "$model" "$prompt" "$out"; then
            text="$(cat "$out")"
            sha="$(persist_pov "$runid" "$round" "$lane" "$tasksha" "$genesis" "$text")"
            append_event pov "$(jq -cn --arg run "$runid" --arg lane "$lane" --arg sha "$sha" '{run_id:$run,lane:$lane,sha256:$sha}')"
        else
            warn "lane=$lane inference failed"
        fi
        i=$((i+1))
    done

    local selected consensus_file
    selected="$(select_povs "$tasksha" "$genesis" "$round" | wc -l | tr -d ' ')"
    consensus_file="$(consensus "$runid" "$tasksha" "$genesis" "$round")"
    printf '%s\n' "$(cat "$consensus_file")"
    if [[ "$AI_SYNTHESIS" == 1 && -s "$consensus_file" ]]; then
        local synth_prompt synth_out
        synth_prompt="$(fit_prompt "Synthesize these GENESIS/HX lane findings into one implementation plan. Do not add unsupported facts.\n\n$(cat "$consensus_file")")"
        synth_out="$RUN_DIR/${runid}.synthesis.txt"
        if llama_infer "$model" "$synth_prompt" "$synth_out"; then
            printf '\n[SYNTHESIS]\n%s\n' "$(cat "$synth_out")"
        fi
    fi
    jq -cn --arg run "$runid" --arg task "$tasksha" --arg status completed --arg views "$selected" --arg ended "$(iso_now)" \
      '{schema:"GENESIS/HX/RUN/1",run_id:$run,task_sha256:$task,status:$status,successful_views:($views|tonumber),ended_at:$ended}' > "$RUN_DIR/end.json"
    append_event run_end "$(jq -cn --arg run "$runid" --arg views "$selected" '{run_id:$run,successful_views:($views|tonumber)}')"
    append_ledger run_end "$runid:$tasksha:$selected" "$(jq -cn --arg run "$runid" --arg views "$selected" '{run_id:$run,successful_views:($views|tonumber)}')" >/dev/null
}

# ---- file operations --------------------------------------------------------
file_add() { local src="$1" dst="$AI_FILE_ROOT/$(basename "$1")"; [[ -f "$src" ]] || die 'file not found'; cp -f "$src" "$dst"; printf '%s\n' "$dst"; }
file_get() { local p="$1"; [[ -f "$p" ]] && cat "$p" || [[ -f "$AI_FILE_ROOT/$p" ]] && cat "$AI_FILE_ROOT/$p" || die "file not found: $p"; }
file_put() { local p="$1"; shift; mkdir -p "$(dirname "$p")"; printf '%s\n' "$*" > "$p"; printf '%s\n' "$p"; }
file_delete() { local p="$1"; [[ -f "$p" ]] || die "file not found: $p"; rm -f -- "$p"; }

# ---- review / modernize -----------------------------------------------------
review_context() {
    local root="$AI_PROJECT_ROOT" f rel content
    local -a candidates=("$root/ai.sh" "$root/bootstrap-ai.sh" "$HOME/.bashrc" "$AI_HOME/env")
    for f in "${candidates[@]}"; do
        [[ -f "$f" ]] || continue
        rel="$f"; [[ "$f" == "$root"/* ]] && rel="${f#"$root"/}"
        content="$(LC_ALL=C head -c "$AI_MAX_FILE_BYTES" "$f" 2>/dev/null || true)"
        printf '\n===== FILE: %s =====\n%s\n' "$rel" "$content"
    done
    # Add a bounded set of indexed source files not already in the priority list.
    if [[ -f "$FILE_INDEX" ]]; then
        jq -r --argjson n 6 '.files // [] | .[:$n][] | .path' "$FILE_INDEX" 2>/dev/null |
        while IFS= read -r rel; do
            [[ -n "$rel" ]] || continue
            case "$rel" in ai.sh|bootstrap-ai.sh) continue;; esac
            f="$root/$rel"; [[ -f "$f" ]] || continue
            content="$(LC_ALL=C head -c 1200 "$f" 2>/dev/null || true)"
            printf '\n===== FILE: %s =====\n%s\n' "$rel" "$content"
        done
    fi
}
review_workspace() {
    local task="${1:-review all files and focus on ai.sh; identify concrete optimizations for the overall workflow}"
    [[ -f "$FILE_INDEX" ]] || index_tree "$AI_PROJECT_ROOT"
    local ctx
    ctx="$(review_context)"
    # Keep the review task bounded: the engine receives only a compact file window.
    run_engine "$task

BOUNDED WORKSPACE REVIEW WINDOW:
$(fit_bytes "$ctx" 4200)"
}

modernize() {
    local target="${1:-$AI_BIN}"
    [[ -f "$target" ]] || die "target not found: $target"
    bash -n "$target"
    local sha; sha="$(hash_file "$target")"
    append_ledger modernize_check "$sha" "$(jq -cn --arg file "$target" --arg sha "$sha" '{file:$file,sha256:$sha}')" >/dev/null
    printf 'syntax=ok\nsha256=%s\nfile=%s\n' "$sha" "$target"
}

# ---- diagnostics / status --------------------------------------------------
doctor() {
    local rc=0
    require_cmd jq || rc=1; require_cmd curl || rc=1; require_cmd timeout || rc=1; require_cmd sha256sum || rc=1
    [[ -x "$LLAMA_CLI" ]] || { warn "llama not executable: $LLAMA_CLI"; rc=1; }
    valid_gguf "$PRIMARY_MODEL" || warn "primary GGUF unavailable/invalid"
    valid_gguf "$FALLBACK_MODEL" || { warn "fallback GGUF unavailable/invalid"; rc=1; }
    bash -n "$AI_BIN" || rc=1
    [[ -f "$EVENTS" ]] && tail -n 1 "$EVENTS" | jq -e . >/dev/null 2>&1 || true
    [[ -f "$LEDGER" ]] && tail -n 1 "$LEDGER" | jq -e . >/dev/null 2>&1 || true
    printf 'doctor_rc=%s\nmem_available_mb=%s\nstate=%s\nllama=%s\n' "$rc" "$(mem_available_mb)" "$AI_STATE_DIR" "$LLAMA_CLI"
    return "$rc"
}
status() {
    printf 'GENESIS/HX %s\n' "$AI_VERSION"
    printf 'genesis=%s topology=%s lanes=%s physical_concurrency=%s\n' "$AI_GENESIS" "$AI_TOPOLOGY" "$AI_VIEWS" "$AI_CONCURRENCY"
    printf 'model=%s\n' "$(resolve_model "$AI_MODEL")"
    printf 'ctx=%s batch=%s ubatch=%s threads=%s predict=%s\n' "$AI_CTX" "$AI_BATCH" "$AI_UBATCH" "$AI_THREADS" "$AI_PREDICT"
    printf 'prompt_bytes=%s realtime_bytes=%s reserve_mb=%s\n' "$AI_PROMPT_BYTES" "$AI_REALTIME_MAX_BYTES" "$AI_MEM_RESERVE_MB"
    printf 'mem_available_mb=%s\n' "$(mem_available_mb)"
    printf 'state=%s\n' "$AI_STATE_DIR"
}
models() {
    for m in "$PRIMARY_MODEL" "$FALLBACK_MODEL"; do
        if valid_gguf "$m"; then printf 'READY %s %s bytes\n' "$m" "$(wc -c < "$m")"; else printf 'MISSING %s\n' "$m"; fi
    done
}
ledger_verify() {
    local prev='' line n=0 sha got
    [[ -f "$LEDGER" ]] || { echo 'ledger empty'; return 0; }
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        jq -e . >/dev/null 2>&1 <<<"$line" || die "invalid ledger JSON at line $((n+1))"
        got="$(jq -r '.prev_sha256 // ""' <<<"$line")"
        if (( n > 0 )); then
            [[ "$got" == "$prev" ]] || die "ledger chain break at line $((n+1))"
        fi
        prev="$(jq -r '.sha256 // ""' <<<"$line")"
        n=$((n+1))
    done < "$LEDGER"
    printf 'ledger_ok lines=%s tip=%s\n' "$n" "$prev"
}
config() {
    cat <<CFG
AI_VERSION=$AI_VERSION
AI_GENESIS=$AI_GENESIS
AI_TOPOLOGY=$AI_TOPOLOGY
AI_HOME=$AI_HOME
AI_STATE_DIR=$AI_STATE_DIR
AI_PROJECT_ROOT=$AI_PROJECT_ROOT
LLAMA_CLI=$LLAMA_CLI
AI_CTX=$AI_CTX
AI_BATCH=$AI_BATCH
AI_UBATCH=$AI_UBATCH
AI_THREADS=$AI_THREADS
AI_PREDICT=$AI_PREDICT
AI_VIEWS=$AI_VIEWS
AI_CONCURRENCY=$AI_CONCURRENCY
AI_DEPTH=$AI_DEPTH
AI_SYNTHESIS=$AI_SYNTHESIS
AI_PROMPT_BYTES=$AI_PROMPT_BYTES
AI_REALTIME_MAX_BYTES=$AI_REALTIME_MAX_BYTES
AI_AUTO_REINDEX=$AI_AUTO_REINDEX
AI_AUTO_REVIEW=$AI_AUTO_REVIEW
AI_MEM_RESERVE_MB=$AI_MEM_RESERVE_MB
AI_SSH=$AI_SSH_HOST:$AI_SSH_PORT
CFG
}
help_text() {
    cat <<'HELP'
GENESIS/HX ai.sh v253.1.0

Usage:
  ai "TASK"                         run bounded GENESIS/HX inference
  ai run "TASK"                    same as above
  ai index [ROOT]                  NUL-safe workspace index
  ai hydrate FILE                  SHA-addressed chunk hydration
  ai review [TASK]                 bounded workspace review
  ai modernize [FILE]              syntax + lineage check
  ai doctor                        runtime/state diagnostics
  ai status                        controller status
  ai models                        model availability
  ai config                        effective configuration
  ai ledger verify                 verify JSONL hash chain
  ai rehash FILE                   print SHA256
  ai get FILE                      read file
  ai put FILE TEXT                 write file
  ai delete FILE                   delete file
  ai init                          initialize state
  ai realtime                      refresh BTC observation
  ai repl                          interactive shell
  ai help                         this help

Safety invariants:
  llama.cpp only; physical concurrency=1; logical lanes<=8;
  bounded prompts/realtime; SHA256 lineage; NUL-safe traversal;
  no secrets in prompts/ledger; Python is optional, not core inference.
HELP
}
repl() { while true; do printf 'ai> '; IFS= read -r line || break; [[ -z "$line" ]] && continue; [[ "$line" == exit || "$line" == quit ]] && break; eval "$(printf '%q ' ai $line)"; done; }

main() {
    init_state
    local cmd="${1:-}"
    case "$cmd" in
      ''|help|-h|--help) help_text;;
      run) shift; run_engine "$*";;
      index) index_tree "${2:-$AI_PROJECT_ROOT}";;
      hydrate) hydrate_file "${2:?file required}";;
      review) shift; review_workspace "${*:-review the workspace and focus on ai.sh; identify concrete optimizations}";;
      modernize) modernize "${2:-$AI_BIN}";;
      doctor) doctor;;
      status|env) status;;
      models) models;;
      config) config;;
      ledger) [[ "${2:-}" == verify ]] || die 'usage: ai ledger verify'; ledger_verify;;
      rehash) hash_file "${2:?file required}";;
      realtime) btc_snapshot; [[ -f "$REALTIME_DIR/latest.json" ]] && cat "$REALTIME_DIR/latest.json";;
      init) init_state; echo "initialized $AI_STATE_DIR";;
      get) file_get "${2:?file required}";;
      put) file_put "${2:?file required}" "${*:3}";;
      delete|rm) file_delete "${2:?file required}";;
      repl) repl;;
      *) run_engine "$*";;
    esac
}

main "$@"

