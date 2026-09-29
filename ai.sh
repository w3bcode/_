#!/usr/bin/env bash
# =============================================================================
# GENESIS/HX ai.sh v252.0.0
# =============================================================================
# Single-file local AI controller
#
# GENESIS   = 2244-1
# TOPOLOGY  = 2π / 8
# LANES     = 8 logical POVs
# WORKERS   = 1 physical llama.cpp inference worker
#
# Core principles:
#   SHA256    -> lineage / integrity
#   MD5      -> legacy attribution metadata only
#   mod7     -> deterministic temporal bucket
#   entropy  -> statistical property
#   BTC      -> external public observation
#   AI       -> model inference
#
# Runtime:
#   direct llama.cpp
#   no Ollama
#   Python NOT required for inference
#   SSH NOT required for inference
#
# Canonical:
#   source:  ~/ _ /ai.sh       (actual: $HOME/_/ai.sh)
#   models:  ~/.ai/models/
#   state:   ~/.ai/state/
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

# -----------------------------------------------------------------------------
# Identity
# -----------------------------------------------------------------------------

readonly AI_VERSION="252.0.0"
readonly AI_GENESIS="2244-1"
readonly AI_TOPOLOGY="2pi/8"
readonly AI_SCHEMA="GENESIS/HX"

# -----------------------------------------------------------------------------
# Canonical filesystem
# -----------------------------------------------------------------------------

AI_HOME="${AI_HOME:-$HOME/.ai}"
AI_PROJECT_ROOT="${AI_PROJECT_ROOT:-$HOME/_}"
AI_STATE_DIR="${AI_STATE_DIR:-$AI_HOME/state}"
AI_FILE_ROOT="${AI_FILE_ROOT:-$AI_HOME/files}"
AI_MODEL_DIR="${AI_MODEL_DIR:-$AI_HOME/models}"

LLAMA_CLI="${LLAMA_CLI:-$HOME/.local/bin/llama}"

STATE="$AI_STATE_DIR"
RUN="$STATE/run"
LOG="$STATE/logs"
DB="$STATE/db"
OBJECTS="$STATE/objects"
REFERENCE="$STATE/reference"
REALTIME="$STATE/realtime"
SESSIONS="$STATE/sessions"
LOCKS="$STATE/locks"

MEMORY_FILE="$STATE/memory.json"
FILE_INDEX="$STATE/file_index.json"
LEDGER="$STATE/ledger.jsonl"
EVENTS="$DB/events.jsonl"
LAST_ERROR_FILE="$RUN/last_error.log"
LLAMA_STDERR="$RUN/llama.stderr"

mkdir -p \
  "$STATE" "$RUN" "$LOG" "$DB" "$OBJECTS" "$REFERENCE" \
  "$REALTIME" "$SESSIONS" "$LOCKS" "$AI_FILE_ROOT"

# -----------------------------------------------------------------------------
# Safe mobile defaults
# -----------------------------------------------------------------------------

AI_CTX="${AI_CTX:-2048}"
AI_BATCH="${AI_BATCH:-128}"
AI_UBATCH="${AI_UBATCH:-64}"
AI_THREADS="${AI_THREADS:-4}"
AI_THREADS_BATCH="${AI_THREADS_BATCH:-4}"
AI_PREDICT="${AI_PREDICT:-192}"

AI_TEMP="${AI_TEMP:-0.65}"
AI_TOP_K="${AI_TOP_K:-40}"
AI_TOP_P="${AI_TOP_P:-0.95}"
AI_REPEAT="${AI_REPEAT:-1.10}"

AI_GPU_LAYERS="${AI_GPU_LAYERS:-0}"
AI_MLOCK="${AI_MLOCK:-0}"

AI_VIEWS="${AI_VIEWS:-8}"
AI_CONCURRENCY="${AI_CONCURRENCY:-1}"
AI_DEPTH="${AI_DEPTH:-1}"
AI_SYNTHESIS="${AI_SYNTHESIS:-0}"

AI_PROMPT_BYTES="${AI_PROMPT_BYTES:-5500}"
AI_REALTIME_MAX_BYTES="${AI_REALTIME_MAX_BYTES:-1200}"
AI_RECALL_TOP="${AI_RECALL_TOP:-4}"

AI_MAX_FILE_BYTES="${AI_MAX_FILE_BYTES:-262144}"
AI_CHUNK_BYTES="${AI_CHUNK_BYTES:-4096}"

AI_AUTO_REINDEX="${AI_AUTO_REINDEX:-0}"
AI_AUTO_REVIEW="${AI_AUTO_REVIEW:-0}"

AI_MEM_RESERVE_MB="${AI_MEM_RESERVE_MB:-2200}"
AI_TIMEOUT="${AI_TIMEOUT:-600}"

AI_REALTIME="${AI_REALTIME:-1}"
AI_REALTIME_TIMEOUT="${AI_REALTIME_TIMEOUT:-12}"

AI_REALTIME_HOST="${AI_REALTIME_HOST:-https://api.coingecko.com}"
AI_REALTIME_ASSET="${AI_REALTIME_ASSET:-bitcoin}"
AI_REALTIME_CURRENCY="${AI_REALTIME_CURRENCY:-usd}"

AI_MODEL_PATH="${AI_MODEL_PATH:-$AI_MODEL_DIR/qwen2.5-coder-3b-instruct-q4_k_m.gguf}"
AI_FALLBACK_PATH="${AI_FALLBACK_PATH:-$AI_MODEL_DIR/qwen2.5-1.5b-instruct-q4_k_m.gguf}"

# -----------------------------------------------------------------------------
# Lane definitions
# -----------------------------------------------------------------------------

LANE_NAMES=(
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
# Utilities
# -----------------------------------------------------------------------------

die() {
  printf 'ERROR: %s\n' "$*" >&2
  return 1
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

info() {
  printf '%s\n' "$*"
}

timestamp() {
  date +%s
}

iso_now() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 ||
    die "required command not found: $1"
}

sha256_text() {
  printf '%s' "$1" | sha256sum | awk '{print $1}'
}

md5_text() {
  printf '%s' "$1" | md5sum | awk '{print $1}'
}

json_string() {
  jq -Rs '.' <<<"${1-}"
}

atomic_write() {
  local target="$1"
  local tmp="${target}.tmp.$$"

  cat > "$tmp"
  mv -f "$tmp" "$target"
}

mem_available_mb() {
  awk '
    /MemAvailable:/ {
      printf "%.0f\n", $2/1024
      found=1
      exit
    }
    END {
      if (!found) print 0
    }
  ' /proc/meminfo 2>/dev/null
}

swap_available_mb() {
  awk '
    /SwapFree:/ {
      printf "%.0f\n", $2/1024
      exit
    }
  ' /proc/meminfo 2>/dev/null || printf '0\n'
}

disk_available_mb() {
  df -Pm "$HOME" 2>/dev/null |
    awk 'NR==2 {print $4; exit}'
}

memory_class() {
  local m
  m="$(mem_available_mb)"

  if (( m >= 3000 )); then
    printf 'GREEN\n'
  elif (( m >= 1800 )); then
    printf 'YELLOW\n'
  else
    printf 'RED\n'
  fi
}

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------

validate_uint() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

validate_runtime() {
  validate_uint "$AI_CTX" || die "AI_CTX invalid"
  validate_uint "$AI_BATCH" || die "AI_BATCH invalid"
  validate_uint "$AI_UBATCH" || die "AI_UBATCH invalid"
  validate_uint "$AI_THREADS" || die "AI_THREADS invalid"
  validate_uint "$AI_PREDICT" || die "AI_PREDICT invalid"
  validate_uint "$AI_VIEWS" || die "AI_VIEWS invalid"

  (( AI_CTX > 0 )) || die "AI_CTX must be > 0"
  (( AI_BATCH > 0 )) || die "AI_BATCH must be > 0"
  (( AI_UBATCH > 0 )) || die "AI_UBATCH must be > 0"
  (( AI_THREADS > 0 )) || die "AI_THREADS must be > 0"
  (( AI_VIEWS >= 1 && AI_VIEWS <= 8 )) ||
    die "AI_VIEWS must be 1..8"

  # Mobile safety invariant.
  (( AI_CONCURRENCY >= 1 )) || AI_CONCURRENCY=1
  (( AI_CONCURRENCY = 1 )) || {
    warn "forcing physical inference concurrency to 1 for mobile stability"
    AI_CONCURRENCY=1
  }
}

# -----------------------------------------------------------------------------
# UTF-8-safe prompt fitting
# -----------------------------------------------------------------------------

fit_prompt() {
  local input="${1-}"
  local max="${2:-$AI_PROMPT_BYTES}"
  local bytes clipped

  bytes="$(printf '%s' "$input" | wc -c)"

  if (( bytes <= max )); then
    printf '%s' "$input"
    return 0
  fi

  if command -v iconv >/dev/null 2>&1; then
    clipped="$(
      printf '%s' "$input" |
        head -c "$max" |
        iconv -f UTF-8 -t UTF-8 -c 2>/dev/null || true
    )"
  else
    clipped="$(printf '%s' "$input" | head -c "$max")"
  fi

  printf '%s\n' "$clipped"
  printf '[TRUNCATED_UTF8 bytes=%s limit=%s]\n' "$bytes" "$max"
}

# -----------------------------------------------------------------------------
# Model resolution
# -----------------------------------------------------------------------------

find_model() {
  local p

  for p in "$AI_MODEL_PATH" "$AI_FALLBACK_PATH"; do
    [[ -f "$p" ]] || continue

    if [[ "$(head -c 4 "$p" 2>/dev/null || true)" == "GGUF" ]]; then
      printf '%s\n' "$p"
      return 0
    fi
  done

  return 1
}

model_name() {
  local p="$1"

  case "$p" in
    *qwen2.5-coder-3b*) printf 'Qwen2.5-Coder-3B-Instruct-Q4_K_M\n' ;;
    *qwen2.5-1.5b*)     printf 'Qwen2.5-1.5B-Instruct-Q4_K_M\n' ;;
    *)                  basename "$p" ;;
  esac
}

# -----------------------------------------------------------------------------
# llama adapter
# -----------------------------------------------------------------------------

llama_help() {
  "$LLAMA_CLI" cli --help 2>&1 || "$LLAMA_CLI" --help 2>&1 || true
}

llama_has_arg() {
  local arg="$1"

  llama_help |
    grep -Eq -- "(^|[[:space:],])${arg}([=[:space:],]|$)"
}

llama_infer() {
  local model="$1"
  local prompt="$2"

  [[ -f "$model" ]] || {
    printf 'model missing: %s\n' "$model" > "$LAST_ERROR_FILE"
    return 1
  }

  [[ "$(head -c 4 "$model" 2>/dev/null || true)" == "GGUF" ]] || {
    printf 'invalid GGUF: %s\n' "$model" > "$LAST_ERROR_FILE"
    return 1
  }

  command -v "$LLAMA_CLI" >/dev/null 2>&1 || {
    printf 'llama executable missing: %s\n' "$LLAMA_CLI" > "$LAST_ERROR_FILE"
    return 1
  }

  : > "$LAST_ERROR_FILE"
  : > "$LLAMA_STDERR"

  local -a cmd
  cmd=("$LLAMA_CLI" cli -m "$model")

  # Runtime flags are added only when supported.
  if llama_has_arg "--ctx-size"; then
    cmd+=(--ctx-size "$AI_CTX")
  elif llama_has_arg "-c"; then
    cmd+=(-c "$AI_CTX")
  fi

  if llama_has_arg "--batch-size"; then
    cmd+=(--batch-size "$AI_BATCH")
  elif llama_has_arg "-b"; then
    cmd+=(-b "$AI_BATCH")
  fi

  if llama_has_arg "--ubatch-size"; then
    cmd+=(--ubatch-size "$AI_UBATCH")
  fi

  if llama_has_arg "--predict"; then
    cmd+=(--predict "$AI_PREDICT")
  elif llama_has_arg "-n"; then
    cmd+=(-n "$AI_PREDICT")
  fi

  if llama_has_arg "--threads"; then
    cmd+=(--threads "$AI_THREADS")
  elif llama_has_arg "-t"; then
    cmd+=(-t "$AI_THREADS")
  fi

  if llama_has_arg "--threads-batch"; then
    cmd+=(--threads-batch "$AI_THREADS_BATCH")
  fi

  if llama_has_arg "--temp"; then
    cmd+=(--temp "$AI_TEMP")
  fi

  if llama_has_arg "--top-k"; then
    cmd+=(--top-k "$AI_TOP_K")
  fi

  if llama_has_arg "--top-p"; then
    cmd+=(--top-p "$AI_TOP_P")
  fi

  if llama_has_arg "--repeat-penalty"; then
    cmd+=(--repeat-penalty "$AI_REPEAT")
  fi

  if llama_has_arg "--no-mmap"; then
    # Keep mmap enabled by default; mobile memory pressure benefits from it.
    :
  fi

  if llama_has_arg "--n-gpu-layers"; then
    cmd+=(--n-gpu-layers "$AI_GPU_LAYERS")
  fi

  if llama_has_arg "--no-mmap"; then
    :
  fi

  # Prompt enters stdin. This avoids command-line length/escaping problems.
  if ! timeout "$AI_TIMEOUT" \
      "${cmd[@]}" \
      < <(printf '%s' "$prompt") \
      >"$RUN/llama.stdout" \
      2>"$LLAMA_STDERR"; then

    {
      printf 'timestamp=%s\n' "$(iso_now)"
      printf 'model=%s\n' "$model"
      printf 'rc=1\n'
      cat "$LLAMA_STDERR"
    } > "$LAST_ERROR_FILE"

    return 1
  fi

  cat "$RUN/llama.stdout"
}

# -----------------------------------------------------------------------------
# Event / ledger
# -----------------------------------------------------------------------------

append_event() {
  local type="$1"
  local payload="${2:-{}}"
  local ts

  ts="$(timestamp)"

  jq -cn \
    --arg ts "$ts" \
    --arg iso "$(iso_now)" \
    --arg type "$type" \
    --arg version "$AI_VERSION" \
    --arg genesis "$AI_GENESIS" \
    --argjson payload "$payload" \
    '{
      timestamp:($ts|tonumber),
      iso:$iso,
      schema:"GENESIS/HX",
      version:$version,
      genesis:$genesis,
      type:$type,
      payload:$payload
    }' >> "$EVENTS"
}

append_ledger() {
  local type="$1"
  local material="$2"
  local payload="${3:-{}}"

  local ts sha md5 mod7 prev

  ts="$(timestamp)"
  sha="$(sha256_text "$material")"
  md5="$(md5_text "$material")"
  mod7="$((ts % 7))"

  prev="$(
    tail -n 1 "$LEDGER" 2>/dev/null |
      jq -r '.sha256 // ""' 2>/dev/null || true
  )"

  jq -cn \
    --arg type "$type" \
    --arg genesis "$AI_GENESIS" \
    --arg version "$AI_VERSION" \
    --arg timestamp "$ts" \
    --arg sha "$sha" \
    --arg md5 "$md5" \
    --arg prev "$prev" \
    --argjson mod7 "$mod7" \
    --argjson payload "$payload" \
    '{
      schema:"GENESIS/HX",
      genesis:$genesis,
      version:$version,
      type:$type,
      timestamp:($timestamp|tonumber),
      timestamp_mod7:$mod7,
      prev_sha256:$prev,
      sha256:$sha,
      md5_legacy:$md5,
      payload:$payload
    }' >> "$LEDGER"

  printf '%s\n' "$sha"
}

# -----------------------------------------------------------------------------
# Run lifecycle / recovery
# -----------------------------------------------------------------------------

run_begin() {
  local run_id="$1"

  mkdir -p "$RUN/$run_id"

  jq -n \
    --arg id "$run_id" \
    --arg iso "$(iso_now)" \
    --arg version "$AI_VERSION" \
    --arg genesis "$AI_GENESIS" \
    --arg topology "$AI_TOPOLOGY" \
    '{
      status:"running",
      run_id:$id,
      started:$iso,
      version:$version,
      genesis:$genesis,
      topology:$topology,
      physical_concurrency:1,
      recoverable:true
    }' > "$RUN/$run_id/start.json"
}

run_end() {
  local run_id="$1"
  local status="${2:-complete}"

  jq -n \
    --arg id "$run_id" \
    --arg iso "$(iso_now)" \
    --arg status "$status" \
    '{
      status:$status,
      run_id:$id,
      ended:$iso
    }' > "$RUN/$run_id/end.json"
}

# -----------------------------------------------------------------------------
# Entropy / signatures
# -----------------------------------------------------------------------------

entropy_text() {
  python3 - "$1" 2>/dev/null <<'PY' || true
import math
from collections import Counter
import sys

s = sys.argv[1]
if not s:
    print("0")
    raise SystemExit

c = Counter(s.encode("utf-8", "replace"))
n = len(s.encode("utf-8", "replace"))

h = -sum((v/n) * math.log2(v/n) for v in c.values())
print(f"{h:.8f}")
PY
}

# Python is deliberately optional here.
# Core inference does not depend on it.
entropy_fallback() {
  printf '0\n'
}

entropy() {
  if command -v python3 >/dev/null 2>&1; then
    entropy_text "$1"
  else
    entropy_fallback
  fi
}

# -----------------------------------------------------------------------------
# Workspace classification
# -----------------------------------------------------------------------------

classify_file() {
  local f="$1"
  local base ext shebang

  base="$(basename "$f")"
  ext="${base##*.}"
  shebang="$(head -n 1 "$f" 2>/dev/null || true)"

  case "$shebang" in
    '#!'*) printf 'shebang=%s' "$shebang" ;;
    *)     printf 'extension=%s' "$ext" ;;
  esac
}

# -----------------------------------------------------------------------------
# File hashing / indexing
# -----------------------------------------------------------------------------

hash_file() {
  local f="$1"

  sha256sum "$f" |
    awk '{print $1}'
}

index_file() {
  local f="$1"

  [[ -f "$f" ]] || return 0

  local bytes sha md5 type entropy_value

  bytes="$(wc -c < "$f")"

  (( bytes <= AI_MAX_FILE_BYTES )) || return 0

  sha="$(hash_file "$f")"
  md5="$(md5sum "$f" | awk '{print $1}')"
  type="$(classify_file "$f")"
  entropy_value="$(entropy "$(head -c "$AI_CHUNK_BYTES" "$f" 2>/dev/null || true)")"

  jq -cn \
    --arg path "$f" \
    --arg sha "$sha" \
    --arg md5 "$md5" \
    --arg type "$type" \
    --arg bytes "$bytes" \
    --arg entropy "$entropy_value" \
    '{
      path:$path,
      sha256:$sha,
      md5_legacy:$md5,
      bytes:($bytes|tonumber),
      classification:$type,
      entropy:$entropy
    }'
}

index_tree() {
  local root="${1:-$AI_PROJECT_ROOT}"
  local tmp="$FILE_INDEX.tmp.$$"

  [[ -d "$root" ]] || die "directory not found: $root"

  printf '{"schema":"GENESIS/HX","genesis":"%s","root":%s,"files":[' \
    "$AI_GENESIS" "$(json_string "$root")" > "$tmp"

  local first=1
  local f rec

  while IFS= read -r -d '' f; do
    rec="$(index_file "$f")" || continue
    [[ -n "$rec" ]] || continue

    if (( first )); then
      first=0
    else
      printf ',' >> "$tmp"
    fi

    printf '%s' "$rec" >> "$tmp"
  done < <(
    find "$root" \
      -type f \
      ! -path '*/.git/*' \
      ! -path '*/.ai/*' \
      -print0 2>/dev/null
  )

  printf ']}\n' >> "$tmp"
  mv -f "$tmp" "$FILE_INDEX"

  append_event index "$(jq -cn --arg root "$root" '{root:$root}')"

  info "indexed: $root"
  info "index:   $FILE_INDEX"
}

# -----------------------------------------------------------------------------
# Chunk hydration
# -----------------------------------------------------------------------------

hydrate_file() {
  local f="$1"

  [[ -f "$f" ]] || return 1

  local sha chunk_dir i chunk chunk_sha

  sha="$(hash_file "$f")"
  chunk_dir="$OBJECTS/$sha"

  mkdir -p "$chunk_dir"

  i=0

  while IFS= read -r -d '' chunk; do
    chunk_sha="$(sha256_text "$chunk")"

    printf '%s' "$chunk" > "$chunk_dir/$i.txt"

    jq -cn \
      --arg file "$f" \
      --arg parent "$sha" \
      --arg sha "$chunk_sha" \
      --arg index "$i" \
      '{
        type:"chunk",
        file:$file,
        parent_sha256:$parent,
        chunk_sha256:$sha,
        index:($index|tonumber)
      }' >> "$chunk_dir/manifest.jsonl"

    i=$((i + 1))
  done < <(
    awk -v n="$AI_CHUNK_BYTES" '
      {
        line=$0 ORS
        while (length(line) > n) {
          printf "%s%c", substr(line,1,n), 0
          line=substr(line,n+1)
        }
        rest=line
      }
      END {
        if (length(rest)) printf "%s%c", rest, 0
      }
    ' "$f" 2>/dev/null
  )

  info "hydrated: $f -> $chunk_dir"
}

hydrate_tree() {
  local root="${1:-$AI_PROJECT_ROOT}"
  local count=0

  while IFS= read -r -d '' f; do
    hydrate_file "$f" || true
    count=$((count + 1))
  done < <(
    find "$root" \
      -type f \
      ! -path '*/.git/*' \
      ! -path '*/.ai/*' \
      -print0 2>/dev/null
  )

  info "hydrated files: $count"
}

# -----------------------------------------------------------------------------
# Recall
# -----------------------------------------------------------------------------

recall() {
  local query="${1-}"
  local top="${2:-$AI_RECALL_TOP}"

  [[ -f "$FILE_INDEX" ]] || {
    printf '[]\n'
    return 0
  }

  # Lightweight deterministic lexical recall.
  # No embedding server and no second AI process.
  jq -c \
    --arg q "$query" \
    --argjson top "$top" '
      .files
      | map(
          .score =
            (
              (
                (.path | ascii_downcase | contains($q|ascii_downcase))
                | if . then 1 else 0 end
              )
            )
        )
      | sort_by(-.score, .path)
      | .[:$top]
    ' "$FILE_INDEX"
}

# -----------------------------------------------------------------------------
# Realtime BTC
# -----------------------------------------------------------------------------

btc_snapshot() {
  local tmp raw compact timestamp_value prev material sha md5 mod7

  [[ "$AI_REALTIME" == "1" ]] || {
    printf '{"enabled":false}\n'
    return 0
  }

  require_cmd curl
  require_cmd jq

  tmp="$REALTIME/.raw.$$"
  timestamp_value="$(timestamp)"

  if ! curl -fsS \
      --max-time "$AI_REALTIME_TIMEOUT" \
      "$AI_REALTIME_HOST/api/v3/simple/price?ids=$AI_REALTIME_ASSET&vs_currencies=$AI_REALTIME_CURRENCY" \
      > "$tmp"; then
    rm -f "$tmp"

    printf '{"enabled":true,"status":"unavailable","timestamp":%s}\n' \
      "$timestamp_value"

    return 0
  fi

  raw="$(cat "$tmp")"
  rm -f "$tmp"

  compact="$(
    jq -cn \
      --arg schema "GENESIS/HX/BTC/3" \
      --arg timestamp "$timestamp_value" \
      --arg network "bitcoin-public-market-observation" \
      --arg asset "$AI_REALTIME_ASSET" \
      --arg currency "$AI_REALTIME_CURRENCY" \
      --argjson raw "$raw" \
      '{
        schema:$schema,
        timestamp:($timestamp|tonumber),
        network:$network,
        asset:$asset,
        currency:$currency,
        price_usd:($raw.bitcoin.usd // null)
      }'
  )"

  compact="$(fit_prompt "$compact" "$AI_REALTIME_MAX_BYTES")"

  prev="$(
    jq -r '.sha256 // ""' "$REALTIME/latest.json" 2>/dev/null || true
  )"

  material="$(printf '%s\0%s\0%s' "$prev" "$timestamp_value" "$compact")"
  sha="$(sha256_text "$material")"
  md5="$(md5_text "$material")"
  mod7="$((timestamp_value % 7))"

  jq -cn \
    --arg schema "GENESIS/HX/BTC/3" \
    --arg timestamp "$timestamp_value" \
    --arg prev "$prev" \
    --arg sha "$sha" \
    --arg md5 "$md5" \
    --argjson mod7 "$mod7" \
    --argjson state "$compact" \
    '{
      schema:$schema,
      timestamp:($timestamp|tonumber),
      prev_sha256:$prev,
      sha256:$sha,
      md5_legacy:$md5,
      timestamp_mod7:$mod7,
      state:$state
    }' > "$REALTIME/latest.json"

  jq -cn \
    --arg timestamp "$timestamp_value" \
    --arg sha "$sha" \
    --arg prev "$prev" \
    --arg md5 "$md5" \
    --argjson mod7 "$mod7" \
    --argjson state "$compact" \
    '{
      timestamp:($timestamp|tonumber),
      prev_sha256:$prev,
      sha256:$sha,
      md5_legacy:$md5,
      timestamp_mod7:$mod7,
      state:$state
    }' >> "$REALTIME/ledger.jsonl"

  printf '%s\n' "$compact"
}

realtime_cmd() {
  local mode="${1:-show}"

  case "$mode" in
    refresh)
      btc_snapshot
      ;;
    show)
      if [[ -f "$REALTIME/latest.json" ]]; then
        jq . "$REALTIME/latest.json"
      else
        printf '{"status":"none"}\n'
      fi
      ;;
    ledger)
      tail -n 50 "$REALTIME/ledger.jsonl" 2>/dev/null || true
      ;;
    *)
      die "usage: ai realtime {refresh|show|ledger}"
      ;;
  esac
}

# -----------------------------------------------------------------------------
# Prompt construction
# -----------------------------------------------------------------------------

lane_instruction() {
  case "$1" in
    analytical)
      printf '%s' \
        'Analyze constraints, assumptions, evidence, dependencies, and failure modes. Separate facts from inference.'
      ;;
    architectural)
      printf '%s' \
        'Design the system structure, interfaces, state transitions, boundaries, and invariants.'
      ;;
    critical)
      printf '%s' \
        'Identify contradictions, hidden assumptions, unsafe behavior, ambiguity, and likely implementation failures.'
      ;;
    creative)
      printf '%s' \
        'Generate useful alternative formulations or mechanisms without violating the explicit constraints.'
      ;;
    implementation)
      printf '%s' \
        'Focus on concrete implementation details, commands, algorithms, interfaces, and testable changes.'
      ;;
    adversarial)
      printf '%s' \
        'Attempt to break the proposed solution. Look for resource exhaustion, stale state, corruption, races, and prompt failures.'
      ;;
    systems)
      printf '%s' \
        'Evaluate runtime, filesystem, process, memory, persistence, recovery, and operating-environment behavior.'
      ;;
    synthesis)
      printf '%s' \
        'Integrate the strongest compatible observations into a concise executable plan.'
      ;;
    *)
      printf '%s' 'Produce a precise technical response.'
      ;;
  esac
}

build_prompt() {
  local lane="$1"
  local task="$2"
  local genesis="$3"
  local round="$4"
  local reference="$5"
  local recall_data="$6"
  local btc="$7"

  local prompt

  prompt="$(
    cat <<EOF
GENESIS/HX LOCAL INFERENCE CONTRACT

GENESIS: $genesis
TASK: $task
ROUND: $round
LANE: $lane
TOPOLOGY: 2pi/8

ROLE:
$(lane_instruction "$lane")

RUNTIME:
- direct llama.cpp
- physical inference concurrency = 1
- logical lanes = 8
- context = $AI_CTX
- prompt byte ceiling = $AI_PROMPT_BYTES

SEMANTIC INVARIANTS:
- SHA256 means integrity/lineage, not truth or causality.
- MD5 is legacy attribution metadata only.
- mod7 is a deterministic temporal bucket.
- entropy is a statistical measurement.
- external BTC data is an observation, not a private-key or identity source.
- market price is not equivalent to blockchain state.
- never request, expose, infer, or fabricate secrets.
- inference failure must never be represented as a valid result.

REFERENCE:
$reference

RECALL:
$recall_data

BTC PUBLIC OBSERVATION:
$btc

TASK:
$task

OUTPUT CONTRACT:
1. Stay inside the assigned lane.
2. Distinguish evidence from inference.
3. Do not invent unavailable state.
4. Prefer concrete, testable technical reasoning.
5. Keep the response compact.
EOF
  )"

  fit_prompt "$prompt" "$AI_PROMPT_BYTES"
}

# -----------------------------------------------------------------------------
# POV persistence
# -----------------------------------------------------------------------------

persist_pov() {
  local run_id="$1"
  local task="$2"
  local genesis="$3"
  local round="$4"
  local lane="$5"
  local output="$6"

  local hash md5 entropy_value path

  hash="$(sha256_text "$output")"
  md5="$(md5_text "$output")"
  entropy_value="$(entropy "$output")"

  path="$OBJECTS/$hash.json"

  jq -n \
    --arg type "pov" \
    --arg run "$run_id" \
    --arg task "$task" \
    --arg genesis "$genesis" \
    --arg round "$round" \
    --arg lane "$lane" \
    --arg sha "$hash" \
    --arg md5 "$md5" \
    --arg entropy "$entropy_value" \
    --arg output "$output" \
    '{
      type:$type,
      run:$run,
      task:$task,
      genesis:$genesis,
      round:($round|tonumber),
      name:$lane,
      sha256:$sha,
      md5_legacy:$md5,
      entropy:$entropy,
      output:$output
    }' > "$path"

  jq -cn \
    --arg type "pov" \
    --arg run "$run_id" \
    --arg task "$task" \
    --arg genesis "$genesis" \
    --arg round "$round" \
    --arg lane "$lane" \
    --arg sha "$hash" \
    '{
      type:$type,
      run:$run,
      task:$task,
      genesis:$genesis,
      round:($round|tonumber),
      name:$lane,
      sha256:$sha
    }' >> "$LEDGER"

  printf '%s\n' "$hash"
}

# -----------------------------------------------------------------------------
# Single physical worker
# -----------------------------------------------------------------------------

run_views() {
  local run_id="$1"
  local task="$2"
  local genesis="$3"
  local round="$4"
  local reference="$5"
  local recall_data="$6"
  local btc="$7"

  local model
  model="$(find_model)" ||
    die "no valid GGUF model found"

  local count="$AI_VIEWS"

  (( count > 8 )) && count=8
  (( count < 1 )) && count=1

  # Explicit physical invariant.
  local physical_workers=1

  info "model: $model"
  info "logical lanes: $count"
  info "physical workers: $physical_workers"
  info "memory class: $(memory_class)"

  local lane prompt output hash
  local -a hashes=()

  for ((i=0; i<count; i++)); do
    lane="${LANE_NAMES[$i]}"

    info ""
    info "[$((i + 1))/$count] lane=$lane"

    prompt="$(
      build_prompt \
        "$lane" \
        "$task" \
        "$genesis" \
        "$round" \
        "$reference" \
        "$recall_data" \
        "$btc"
    )"

    # Refuse rather than adding another worker under RED pressure.
    if [[ "$(memory_class)" == "RED" ]]; then
      warn "memory pressure RED; refusing additional physical worker"
      return 1
    fi

    if output="$(llama_infer "$model" "$prompt")"; then
      hash="$(persist_pov \
        "$run_id" \
        "$task" \
        "$genesis" \
        "$round" \
        "$lane" \
        "$output"
      )"

      hashes+=("$hash")
      info "  sha256=$hash"
    else
      warn "lane failed: $lane"
      cat "$LAST_ERROR_FILE" >&2 2>/dev/null || true
      append_event inference_failure \
        "$(jq -cn \
          --arg run "$run_id" \
          --arg lane "$lane" \
          --arg round "$round" \
          '{run:$run,lane:$lane,round:($round|tonumber)}'
        )"
    fi
  done

  printf '%s\n' "${hashes[@]}"
}

# -----------------------------------------------------------------------------
# POV selection
# -----------------------------------------------------------------------------

select_povs() {
  local task="$1"
  local genesis="$2"
  local round="$3"
  local name

  for name in "${LANE_NAMES[@]}"; do
    jq -r \
      --arg task "$task" \
      --arg genesis "$genesis" \
      --arg round "$round" \
      --arg name "$name" '
        select(
          .type=="pov"
          and .task==$task
          and .genesis==$genesis
          and (.round|tostring)==$round
          and .name==$name
        )
        | .sha256
      ' "$LEDGER" 2>/dev/null |
      tail -n 1 || true
  done
}

load_pov_objects() {
  local task="$1"
  local genesis="$2"
  local round="$3"

  local name hash

  for name in "${LANE_NAMES[@]}"; do
    hash="$(
      jq -r \
        --arg task "$task" \
        --arg genesis "$genesis" \
        --arg round "$round" \
        --arg name "$name" '
          select(
            .type=="pov"
            and .task==$task
            and .genesis==$genesis
            and (.round|tostring)==$round
            and .name==$name
          )
          | .sha256
        ' "$LEDGER" 2>/dev/null |
        tail -n 1 || true
    )"

    [[ -n "$hash" ]] || continue

    if [[ -f "$OBJECTS/$hash.json" ]]; then
      cat "$OBJECTS/$hash.json"
      printf '\n'
    fi
  done
}

# -----------------------------------------------------------------------------
# Consensus
# -----------------------------------------------------------------------------

consensus() {
  local task="$1"
  local genesis="$2"
  local round="$3"

  local records

  records="$(load_pov_objects "$task" "$genesis" "$round")"

  [[ -n "$records" ]] || {
    warn "no valid POV records available"
    return 1
  }

  # Deterministic structural consensus.
  # We do not fabricate missing lanes and do not claim that frequency means truth.
  printf '%s\n' "$records" |
    jq -s '
      {
        schema:"GENESIS/HX/CONSENSUS/1",
        records:.
      }
    '
}

# -----------------------------------------------------------------------------
# Optional synthesis
# -----------------------------------------------------------------------------

synthesize() {
  local task="$1"
  local genesis="$2"
  local round="$3"
  local povs="$4"

  [[ "$AI_SYNTHESIS" == "1" ]] || return 0

  local prompt

  prompt="$(
    cat <<EOF
GENESIS/HX SYNTHESIS

GENESIS: $genesis
ROUND: $round

TASK:
$task

POV RECORDS:
$povs

SYNTHESIS CONTRACT:
- integrate compatible observations;
- preserve uncertainty;
- do not treat vote count as truth;
- do not invent missing evidence;
- return a compact implementation-oriented result.
EOF
  )"

  prompt="$(fit_prompt "$prompt" "$AI_PROMPT_BYTES")"

  local model
  model="$(find_model)" || return 1

  llama_infer "$model" "$prompt"
}

# -----------------------------------------------------------------------------
# Main engine
# -----------------------------------------------------------------------------

run_engine() {
  local task="${1-}"

  [[ -n "$task" ]] || die "empty task"

  validate_runtime
  require_cmd jq
  require_cmd sha256sum
  require_cmd timeout

  local normalized genesis task_hash run_id
  local reference recall_data btc round povs synthesis

  normalized="$(
    printf '%s' "$task" |
      tr '\r\n' ' ' |
      sed 's/[[:space:]][[:space:]]*/ /g'
  )"

  genesis="$(
    sha256_text \
      "$(printf '%s\0%s\0%s\0%s' \
        "$AI_GENESIS" \
        "$AI_VERSION" \
        "$normalized" \
        "$(timestamp)"
      )"
  )"

  task_hash="$(
    sha256_text "$(printf '%s\0%s' "$genesis" "$normalized")"
  )"

  run_id="${task_hash:0:16}-$(timestamp)"

  run_begin "$run_id"

  append_event genesis \
    "$(jq -cn \
      --arg task "$normalized" \
      --arg genesis "$genesis" \
      --arg task_hash "$task_hash" \
      --arg run "$run_id" \
      '{
        task:$task,
        genesis_hash:$genesis,
        task_hash:$task_hash,
        run:$run
      }'
    )"

  append_ledger run \
    "$(printf '%s\0%s\0%s' "$run_id" "$genesis" "$normalized")" \
    "$(jq -cn \
      --arg task "$normalized" \
      --arg task_hash "$task_hash" \
      --arg run "$run_id" \
      '{task:$task,task_hash:$task_hash,run:$run}'
    )" >/dev/null

  # Realtime is sampled ONCE per engine invocation.
  btc="$(btc_snapshot 2>/dev/null || printf '{"status":"unavailable"}')"

  if [[ -f "$REALTIME/latest.json" ]]; then
    btc="$(
      jq -c '.state // .' "$REALTIME/latest.json" 2>/dev/null |
        head -c "$AI_REALTIME_MAX_BYTES"
    )"
  fi

  reference="none"

  if [[ "$AI_AUTO_REINDEX" == "1" ]]; then
    index_tree "$AI_PROJECT_ROOT"
  fi

  if [[ -f "$FILE_INDEX" ]]; then
    recall_data="$(recall "$normalized" "$AI_RECALL_TOP")"
  else
    recall_data='[]'
  fi

  for ((round=1; round<=AI_DEPTH; round++)); do

    info ""
    info "============================================================"
    info "GENESIS/HX RUN $run_id"
    info "round=$round"
    info "genesis=$genesis"
    info "task=$normalized"
    info "============================================================"

    run_views \
      "$run_id" \
      "$normalized" \
      "$genesis" \
      "$round" \
      "$reference" \
      "$recall_data" \
      "$btc" || {
        run_end "$run_id" "failed"
        return 1
      }

    povs="$(consensus "$normalized" "$genesis" "$round" || true)"

    if [[ -n "$povs" ]]; then
      printf '%s\n' "$povs" > "$RUN/$run_id/consensus-$round.json"

      synthesis="$(
        synthesize \
          "$normalized" \
          "$genesis" \
          "$round" \
          "$povs" || true
      )"

      if [[ -n "$synthesis" ]]; then
        printf '%s\n' "$synthesis" > \
          "$RUN/$run_id/synthesis-$round.txt"

        append_ledger synthesis \
          "$(printf '%s\0%s\0%s' "$run_id" "$round" "$synthesis")" \
          "$(jq -cn \
            --arg run "$run_id" \
            --arg round "$round" \
            '{run:$run,round:($round|tonumber)}'
          )" >/dev/null
      fi
    fi
  done

  run_end "$run_id" "complete"

  jq -n \
    --arg run "$run_id" \
    --arg genesis "$genesis" \
    --arg task "$normalized" \
    --arg task_hash "$task_hash" \
    --arg state "$STATE" \
    '{
      schema:"GENESIS/HX",
      status:"complete",
      run:$run,
      genesis:$genesis,
      task:$task,
      task_hash:$task_hash,
      state:$state
    }'
}

# -----------------------------------------------------------------------------
# Memory
# -----------------------------------------------------------------------------

memory_cmd() {
  local mode="${1:-show}"
  local value="${2-}"

  case "$mode" in
    init)
      if [[ ! -f "$MEMORY_FILE" ]]; then
        jq -n \
          --arg genesis "$AI_GENESIS" \
          '{
            schema:"GENESIS/HX/MEMORY/1",
            genesis:$genesis,
            records:[]
          }' > "$MEMORY_FILE"
      fi
      cat "$MEMORY_FILE"
      ;;

    add)
      [[ -n "$value" ]] || die "usage: ai memory add TEXT"

      [[ -f "$MEMORY_FILE" ]] || memory_cmd init >/dev/null

      local sha
      sha="$(sha256_text "$value")"

      jq \
        --arg value "$value" \
        --arg sha "$sha" \
        --arg timestamp "$(iso_now)" \
        '.records += [{
          timestamp:$timestamp,
          sha256:$sha,
          value:$value
        }]' \
        "$MEMORY_FILE" > "$MEMORY_FILE.tmp.$$"

      mv -f "$MEMORY_FILE.tmp.$$" "$MEMORY_FILE"

      append_ledger memory \
        "$(printf '%s\0%s' "$sha" "$value")" \
        "$(jq -cn --arg sha "$sha" '{sha256:$sha}')" >/dev/null

      jq -c '.records[-1]' "$MEMORY_FILE"
      ;;

    show)
      [[ -f "$MEMORY_FILE" ]] &&
        jq . "$MEMORY_FILE" ||
        printf '{"records":[]}\n'
      ;;

    clear)
      jq -n \
        --arg genesis "$AI_GENESIS" \
        '{schema:"GENESIS/HX/MEMORY/1",genesis:$genesis,records:[]}' \
        > "$MEMORY_FILE"
      ;;

    *)
      die "usage: ai memory {init|add|show|clear}"
      ;;
  esac
}

# -----------------------------------------------------------------------------
# Reference
# -----------------------------------------------------------------------------

reference_cmd() {
  local mode="${1:-list}"
  local value="${2-}"

  case "$mode" in
    add)
      [[ -f "$value" ]] || die "reference file not found: $value"

      local sha target
      sha="$(hash_file "$value")"
      target="$REFERENCE/$sha"

      cp -f "$value" "$target"

      jq -n \
        --arg source "$value" \
        --arg sha "$sha" \
        --arg timestamp "$(iso_now)" \
        '{
          source:$source,
          sha256:$sha,
          timestamp:$timestamp
        }' > "$target.meta.json"

      info "reference=$target"
      ;;

    list)
      find "$REFERENCE" -maxdepth 1 -type f \
        ! -name '*.meta.json' \
        -printf '%f\n' 2>/dev/null |
        sort
      ;;

    show)
      [[ -n "$value" ]] || die "usage: ai reference show SHA"
      [[ -f "$REFERENCE/$value" ]] || die "reference not found"
      cat "$REFERENCE/$value"
      ;;

    *)
      die "usage: ai reference {add|list|show}"
      ;;
  esac
}

# -----------------------------------------------------------------------------
# Artifact
# -----------------------------------------------------------------------------

artifact_cmd() {
  local hash="${1-}"

  [[ -n "$hash" ]] || die "usage: ai artifact SHA256"
  [[ -f "$OBJECTS/$hash.json" ]] ||
    die "artifact not found: $hash"

  jq . "$OBJECTS/$hash.json"
}

# -----------------------------------------------------------------------------
# CRUD
# -----------------------------------------------------------------------------

crud_cmd() {
  local mode="${1:-list}"
  local path="${2-}"
  local value="${3-}"

  case "$mode" in
    get)
      [[ -f "$path" ]] || die "file not found: $path"
      cat "$path"
      ;;

    put)
      [[ -n "$path" ]] || die "usage: ai crud put FILE TEXT"
      printf '%s' "$value" > "$path"
      ;;

    append)
      [[ -n "$path" ]] || die "usage: ai crud append FILE TEXT"
      printf '%s\n' "$value" >> "$path"
      ;;

    rm)
      [[ -n "$path" ]] || die "usage: ai crud rm FILE"
      rm -f -- "$path"
      ;;

    list)
      find "$AI_FILE_ROOT" -maxdepth 2 -type f -print 2>/dev/null |
        sort
      ;;

    *)
      die "usage: ai crud {get|put|append|rm|list}"
      ;;
  esac
}

# -----------------------------------------------------------------------------
# Review / modernization
# -----------------------------------------------------------------------------

review_file() {
  local f="$1"

  [[ -f "$f" ]] || die "file not found: $f"

  local content
  content="$(head -c "$AI_MAX_FILE_BYTES" "$f")"

  local prompt
  prompt="$(
    cat <<EOF
GENESIS/HX CODE REVIEW

File:
$f

Classification:
$(classify_file "$f")

Content:
$content

Review for:
1. syntax/runtime hazards
2. resource hazards
3. state corruption
4. security/secrets
5. portability
6. maintainability
7. concrete fixes

Do not invent execution results.
EOF
  )"

  prompt="$(fit_prompt "$prompt" "$AI_PROMPT_BYTES")"

  local model
  model="$(find_model)" || die "no GGUF model"

  llama_infer "$model" "$prompt"
}

modernize_file() {
  local f="$1"

  [[ -f "$f" ]] || die "file not found: $f"

  review_file "$f"
}

review_cmd() {
  local mode="${1:-file}"
  local target="${2-}"

  case "$mode" in
    file)
      [[ -n "$target" ]] || die "usage: ai review file PATH"
      review_file "$target"
      ;;

    tree)
      [[ -n "$target" ]] || target="$AI_PROJECT_ROOT"

      find "$target" \
        -type f \
        ! -path '*/.git/*' \
        ! -path '*/.ai/*' \
        -print |
        while IFS= read -r f; do
          printf '\n===== %s =====\n' "$f"
          review_file "$f" || true
        done
      ;;

    *)
      die "usage: ai review {file|tree} PATH"
      ;;
  esac
}

# -----------------------------------------------------------------------------
# Validate
# -----------------------------------------------------------------------------

validate_cmd() {
  local failures=0

  printf 'GENESIS/HX validation\n'
  printf '%-28s %s\n' "version" "$AI_VERSION"
  printf '%-28s %s\n' "genesis" "$AI_GENESIS"
  printf '%-28s %s\n' "topology" "$AI_TOPOLOGY"
  printf '%-28s %s\n' "state" "$STATE"
  printf '%-28s %s\n' "llama" "$LLAMA_CLI"

  [[ "$AI_CONCURRENCY" == "1" ]] ||
    { printf 'FAIL physical concurrency\n'; failures=$((failures+1)); }

  (( AI_VIEWS >= 1 && AI_VIEWS <= 8 )) ||
    { printf 'FAIL logical views\n'; failures=$((failures+1)); }

  (( AI_CTX <= 2048 )) ||
    { printf 'FAIL context safety\n'; failures=$((failures+1)); }

  (( AI_PROMPT_BYTES <= 5500 )) ||
    { printf 'FAIL prompt ceiling\n'; failures=$((failures+1)); }

  [[ -d "$STATE" ]] ||
    { printf 'FAIL state directory\n'; failures=$((failures+1)); }

  if [[ -x "$LLAMA_CLI" ]]; then
    printf '%-28s OK\n' "llama executable"
  else
    printf '%-28s MISSING\n' "llama executable"
    failures=$((failures+1))
  fi

  if (( failures == 0 )); then
    printf 'RESULT: VALID\n'
  else
    printf 'RESULT: INVALID failures=%s\n' "$failures"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Status
# -----------------------------------------------------------------------------

status_cmd() {
  local model=""

  model="$(find_model 2>/dev/null || true)"

  cat <<EOF
GENESIS/HX
version              $AI_VERSION
genesis              $AI_GENESIS
topology             $AI_TOPOLOGY

SOURCE
project              $AI_PROJECT_ROOT
controller           $AI_PROJECT_ROOT/ai.sh

STATE
state                $STATE
memory               $MEMORY_FILE
file index           $FILE_INDEX
ledger               $LEDGER
objects              $OBJECTS
realtime             $REALTIME

LLAMA
binary               $LLAMA_CLI
model                ${model:-NONE}
model name           ${model:+$(model_name "$model")}

RUNTIME
context              $AI_CTX
batch                $AI_BATCH
ubatch               $AI_UBATCH
threads              $AI_THREADS
predict              $AI_PREDICT
gpu layers           $AI_GPU_LAYERS
logical views        $AI_VIEWS
physical workers     1
depth                $AI_DEPTH
synthesis            $AI_SYNTHESIS
prompt bytes         $AI_PROMPT_BYTES
realtime bytes       $AI_REALTIME_MAX_BYTES
auto reindex         $AI_AUTO_REINDEX

RESOURCE
memory available MB  $(mem_available_mb)
swap available MB    $(swap_available_mb)
disk available MB    $(disk_available_mb)
memory class         $(memory_class)
EOF
}

# -----------------------------------------------------------------------------
# Models
# -----------------------------------------------------------------------------

models_cmd() {
  local p size status

  printf '%-12s %-8s %s\n' "ROLE" "STATUS" "PATH"

  for p in "$AI_MODEL_PATH" "$AI_FALLBACK_PATH"; do
    if [[ -f "$p" ]] &&
       [[ "$(head -c 4 "$p" 2>/dev/null || true)" == "GGUF" ]]; then
      size="$(du -h "$p" 2>/dev/null | awk '{print $1}')"
      status="READY($size)"
    elif [[ -f "$p" ]]; then
      status="INVALID"
    else
      status="MISSING"
    fi

    if [[ "$p" == "$AI_MODEL_PATH" ]]; then
      printf '%-12s %-8s %s\n' "PRIMARY" "$status" "$p"
    else
      printf '%-12s %-8s %s\n' "FALLBACK" "$status" "$p"
    fi
  done
}

# -----------------------------------------------------------------------------
# Doctor
# -----------------------------------------------------------------------------

doctor_cmd() {
  local fail=0

  printf 'GENESIS/HX doctor\n\n'

  if command -v jq >/dev/null 2>&1; then
    printf '[OK] jq\n'
  else
    printf '[FAIL] jq\n'
    fail=$((fail+1))
  fi

  if command -v curl >/dev/null 2>&1; then
    printf '[OK] curl\n'
  else
    printf '[WARN] curl unavailable; realtime disabled\n'
  fi

  if [[ -x "$LLAMA_CLI" ]]; then
    printf '[OK] llama: %s\n' "$LLAMA_CLI"
  else
    printf '[FAIL] llama: %s\n' "$LLAMA_CLI"
    fail=$((fail+1))
  fi

  if find_model >/dev/null 2>&1; then
    printf '[OK] valid GGUF model\n'
  else
    printf '[FAIL] no valid GGUF model\n'
    fail=$((fail+1))
  fi

  printf '[INFO] memory=%s MiB\n' "$(mem_available_mb)"
  printf '[INFO] swap=%s MiB\n' "$(swap_available_mb)"
  printf '[INFO] disk=%s MiB\n' "$(disk_available_mb)"
  printf '[INFO] memory-class=%s\n' "$(memory_class)"

  if [[ "$(memory_class)" == "RED" ]]; then
    printf '[WARN] resource pressure critical\n'
  fi

  if [[ -f "$RUN/last_error.log" ]]; then
    printf '[INFO] previous inference error:\n'
    tail -n 10 "$RUN/last_error.log"
  fi

  if [[ -f "$RUN"/*/start.json ]]; then
    :
  fi

  if (( fail == 0 )); then
    printf '\nRESULT: HEALTHY\n'
  else
    printf '\nRESULT: %s FAILURE(S)\n' "$fail"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Config
# -----------------------------------------------------------------------------

config_cmd() {
  cat <<EOF
AI_VERSION=$AI_VERSION
AI_GENESIS=$AI_GENESIS
AI_HOME=$AI_HOME
AI_PROJECT_ROOT=$AI_PROJECT_ROOT
AI_STATE_DIR=$AI_STATE_DIR
AI_FILE_ROOT=$AI_FILE_ROOT
AI_MODEL_DIR=$AI_MODEL_DIR
LLAMA_CLI=$LLAMA_CLI

AI_CTX=$AI_CTX
AI_BATCH=$AI_BATCH
AI_UBATCH=$AI_UBATCH
AI_THREADS=$AI_THREADS
AI_THREADS_BATCH=$AI_THREADS_BATCH
AI_PREDICT=$AI_PREDICT
AI_GPU_LAYERS=$AI_GPU_LAYERS

AI_VIEWS=$AI_VIEWS
AI_CONCURRENCY=1
AI_DEPTH=$AI_DEPTH
AI_SYNTHESIS=$AI_SYNTHESIS

AI_PROMPT_BYTES=$AI_PROMPT_BYTES
AI_REALTIME_MAX_BYTES=$AI_REALTIME_MAX_BYTES
AI_RECALL_TOP=$AI_RECALL_TOP
AI_MAX_FILE_BYTES=$AI_MAX_FILE_BYTES
AI_CHUNK_BYTES=$AI_CHUNK_BYTES

AI_AUTO_REINDEX=$AI_AUTO_REINDEX
AI_AUTO_REVIEW=$AI_AUTO_REVIEW
AI_MEM_RESERVE_MB=$AI_MEM_RESERVE_MB

AI_REALTIME=$AI_REALTIME
AI_REALTIME_TIMEOUT=$AI_REALTIME_TIMEOUT
EOF
}

# -----------------------------------------------------------------------------
# Ledger
# -----------------------------------------------------------------------------

ledger_cmd() {
  local mode="${1:-tail}"

  case "$mode" in
    tail)
      tail -n 50 "$LEDGER" 2>/dev/null || true
      ;;
    verify)
      [[ -f "$LEDGER" ]] || {
        info "ledger empty"
        return 0
      }

      local prev=""
      local line sha stored material
      local ok=1

      while IFS= read -r line; do
        sha="$(jq -r '.sha256 // ""' <<<"$line" 2>/dev/null || true)"
        [[ -n "$sha" ]] || continue

        # Full cryptographic reconstruction is intentionally not claimed here:
        # payload serialization can evolve. Structural chain verification follows.
        stored="$(jq -r '.prev_sha256 // ""' <<<"$line")"

        if [[ "$stored" != "$prev" && -n "$prev" ]]; then
          printf 'CHAIN BREAK: expected=%s got=%s\n' "$prev" "$stored"
          ok=0
        fi

        prev="$sha"
      done < "$LEDGER"

      (( ok )) &&
        printf 'ledger structural chain: OK\n' ||
        return 1
      ;;

    *)
      die "usage: ai ledger {tail|verify}"
      ;;
  esac
}

# -----------------------------------------------------------------------------
# Rehash
# -----------------------------------------------------------------------------

rehash_cmd() {
  local root="${1:-$AI_PROJECT_ROOT}"

  [[ -d "$root" ]] || die "directory not found: $root"

  index_tree "$root"
}

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------

help_cmd() {
  cat <<'EOF'
GENESIS/HX ai.sh v252.0.0

USAGE
  ai "TASK"
  ai run "TASK"

CORE
  run TASK              Run GENESIS/HX inference
  views TASK            Alias for run
  repl                  Interactive prompt loop

WORKSPACE
  scan [PATH]           Scan/index workspace
  index [PATH]          Build file_index.json
  hydrate [PATH]        Build hash-addressed chunks
  rehash [PATH]         Rebuild hashes/index
  recall QUERY          Deterministic lexical recall

STATE
  remember TEXT         Add memory record
  memory init|show|clear
  ledger tail|verify
  artifact SHA256
  reference add FILE
  reference list
  reference show SHA256

RUNTIME
  models                Show primary/fallback GGUF
  status                Runtime/resource state
  doctor                Health diagnostics
  config                Effective configuration
  validate              Check HX invariants
  realtime refresh
  realtime show
  realtime ledger

CODE
  review file PATH
  review tree PATH
  modernize PATH
  validate

FILES
  crud list
  crud get FILE
  crud put FILE TEXT
  crud append FILE TEXT
  crud rm FILE

ENVIRONMENT
  llama.cpp only
  physical concurrency = 1
  logical views <= 8
  context <= 2048 by default
  prompt <= 5500 bytes
  realtime <= 1200 bytes
  automatic indexing disabled

SEMANTIC RULES
  SHA256  = integrity / lineage
  MD5     = legacy metadata
  mod7    = deterministic time bucket
  entropy = statistical measurement
  BTC     = public external observation
  AI      = inference, not ground truth
EOF
}

# -----------------------------------------------------------------------------
# REPL
# -----------------------------------------------------------------------------

repl_cmd() {
  local input

  while true; do
    printf 'GENESIS/HX> '

    IFS= read -r input || break

    case "$input" in
      exit|quit)
        break
        ;;
      "")
        continue
        ;;
      *)
        run_engine "$input" || true
        ;;
    esac
  done
}

# -----------------------------------------------------------------------------
# Main dispatch
# -----------------------------------------------------------------------------

main() {
  local cmd="${1:-}"

  case "$cmd" in

    "")
      help_cmd
      ;;

    run)
      shift
      run_engine "$*"
      ;;

    views)
      shift
      run_engine "$*"
      ;;

    scan|index)
      index_tree "${2:-$AI_PROJECT_ROOT}"
      ;;

    hydrate)
      hydrate_tree "${2:-$AI_PROJECT_ROOT}"
      ;;

    rehash)
      rehash_cmd "${2:-$AI_PROJECT_ROOT}"
      ;;

    recall)
      shift
      recall "$*"
      ;;

    remember)
      shift
      memory_cmd add "$*"
      ;;

    memory)
      memory_cmd "${2:-show}" "${3-}"
      ;;

    ledger)
      ledger_cmd "${2:-tail}"
      ;;

    artifact)
      artifact_cmd "${2-}"
      ;;

    reference)
      reference_cmd "${2:-list}" "${3-}"
      ;;

    reference-ingest)
      reference_cmd add "${2-}"
      ;;

    realtime)
      realtime_cmd "${2:-show}"
      ;;

    review)
      review_cmd "${2:-file}" "${3-}"
      ;;

    review-tree)
      review_cmd tree "${2:-$AI_PROJECT_ROOT}"
      ;;

    modernize)
      modernize_file "${2-}"
      ;;

    crud)
      crud_cmd "${2:-list}" "${3-}" "${4-}"
      ;;

    models)
      models_cmd
      ;;

    status)
      status_cmd
      ;;

    doctor)
      doctor_cmd
      ;;

    config)
      config_cmd
      ;;

    validate)
      validate_cmd
      ;;

    repl)
      repl_cmd
      ;;

    help|-h|--help)
      help_cmd
      ;;

    *)
      # Natural CLI:
      # ai "what should I inspect?"
      run_engine "$*"
      ;;

  esac
}

main "$@"
