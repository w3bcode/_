#!/usr/bin/env bash
# =============================================================================
# ai.sh — single-file llama CLI CRUD / genesis / SOAP-JSON / entropy indexer
# =============================================================================
# Local-first controller derived from the supplied Gemini Interactions skill
# semantics, adapted to llama CLI. It does NOT call Gemini or require an API key.
#
# Core state model:
#   timestamp -> mod7 epoch -> genesis SHA256
#   prompt/file -> MD5 origin -> SHA256 task/root
#   content -> token frequencies -> Shannon entropy / token weights
#   artifacts -> JSONL database -> score/rank -> parent-hash traceback
#
# Runtime model:
#   llama cli ...
#
# The installed llama command reference is captured at runtime with:
#   llama --help
#   llama cli -h
# and stored in the database. This avoids pretending unsupported flags exist.
# =============================================================================

set -o pipefail
shopt -s nullglob

VERSION="1.2.0"
AI_NAME="loopshape-ai"
BASE="${AI_HOME:-${HOME}/_}"
STATE="${AI_STATE_DIR:-$BASE/.ai-state}"
DB="$STATE/db"
OBJECTS="$DB/objects"
REFS="$DB/reference"
WORK="$BASE"
LLAMA_BIN="${LLAMA_BIN:-llama}"
MODEL="${AI_MODEL:-Qwen/Qwen2.5-Coder-3B-Instruct-GGUF}"
CTX="${AI_CTX:-4096}"
THREADS="${AI_THREADS:-8}"
GPU_LAYERS="${AI_GPU_LAYERS:-0}"
TEMP="${AI_TEMP:-0.65}"
TOP_P="${AI_TOP_P:-0.95}"
TOP_K="${AI_TOP_K:-40}"
REPEAT_PENALTY="${AI_REPEAT_PENALTY:-1.10}"
VIEWS="${AI_VIEWS:-1}"
SYNTHESIS="${AI_SYNTHESIS:-true}"
PARALLEL="${AI_PARALLEL:-0}"
TIMEOUT="${AI_TIMEOUT:-600}"
VERBOSE=0
NO_COLOR="${AI_NO_COLOR:-0}"
SESSION="${AI_SESSION:-default}"
MAX_BYTES="${AI_MAX_BYTES:-10485760}"
EXCLUDE_REGEX='(^|/)(\.git|node_modules|\.venv|__pycache__|dist|build|\.ai-state)(/|$)'

mkdir -p "$DB" "$OBJECTS" "$REFS" "$STATE" || exit 1

# ----------------------------------------------------------------------------
# Dependencies
# ----------------------------------------------------------------------------
need(){ command -v "$1" >/dev/null 2>&1 || { echo "ai.sh: missing dependency: $1" >&2; exit 127; }; }
for c in awk sed grep sort find stat wc tr date mktemp; do need "$c"; done
need jq
if command -v sha256sum >/dev/null 2>&1; then SHA_CMD=sha256sum
elif command -v shasum >/dev/null 2>&1; then SHA_CMD=shasum
else echo "ai.sh: sha256sum or shasum required" >&2; exit 127; fi
if command -v md5sum >/dev/null 2>&1; then MD5_CMD=md5sum
elif command -v md5 >/dev/null 2>&1; then MD5_CMD=md5
else MD5_CMD=""; fi

log(){ (( VERBOSE )) && printf '[ai] %s\n' "$*" >&2 || true; }
die(){ printf 'ai.sh: %s\n' "$*" >&2; exit 1; }
now(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
compact_path(){ printf '%s' "$1" | sed "s#^$HOME#~#"; }

sha256_text(){
  if [[ "$SHA_CMD" == sha256sum ]]; then printf '%s' "$1" | sha256sum | awk '{print $1}'
  else printf '%s' "$1" | shasum -a 256 | awk '{print $1}'; fi
}
sha256_file(){
  if [[ "$SHA_CMD" == sha256sum ]]; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}
md5_text(){
  [[ -n "$MD5_CMD" ]] || { printf 'md5-unavailable'; return 0; }
  if [[ "$MD5_CMD" == md5sum ]]; then printf '%s' "$1" | md5sum | awk '{print $1}'
  else printf '%s' "$1" | md5 -q; fi
}
md5_file(){
  [[ -n "$MD5_CMD" ]] || { printf 'md5-unavailable'; return 0; }
  if [[ "$MD5_CMD" == md5sum ]]; then md5sum "$1" | awk '{print $1}'
  else md5 -q "$1"; fi
}

# ----------------------------------------------------------------------------
# File database — append-only JSONL + content-addressed objects
# ----------------------------------------------------------------------------
init_db(){
  for f in roots sessions tasks files traces scores events tokens reference; do
    [[ -f "$DB/$f.jsonl" ]] || : > "$DB/$f.jsonl"
  done
  [[ -f "$DB/index.json" ]] || printf '{"schema":1,"createdAt":"%s"}\n' "$(now)" > "$DB/index.json"
}
init_db

append_json(){
  local name="$1"; shift
  printf '%s\n' "$1" >> "$DB/$name.jsonl"
}

object_put(){
  local text="$1" hash
  hash="$(sha256_text "$text")"
  printf '%s' "$text" > "$OBJECTS/$hash" 2>/dev/null || true
  printf '%s' "$hash"
}

# ----------------------------------------------------------------------------
# Skill-inspired interaction event lifecycle
# created -> step.start -> step.delta* -> step.stop -> completed/failed
# The supplied skill defines this stream shape explicitly.                
# ----------------------------------------------------------------------------
event(){
  local type="$1"; shift
  local ts id json data="${1:-}"
  [[ -n "$data" ]] || data="{}"
  ts="$(now)"
  id="$(sha256_text "$SESSION|$ts|$type|$RANDOM")"
  json="$(jq -cn --arg id "$id" --arg type "$type" --arg at "$ts" --arg session "$SESSION" --argjson data "$data" \
    '{id:$id,event_type:$type,at:$at,session:$session,data:$data}')"
  append_json events "$json"
  (( VERBOSE )) && printf '[event] %s\n' "$type" >&2
}

# ----------------------------------------------------------------------------
# Genesis / lineage
# ----------------------------------------------------------------------------
genesis_new(){
  local ts epoch mod7 seed root
  ts="$(date +%s%3N 2>/dev/null || date +%s000)"
  epoch=$((ts % 1000000007))
  mod7=$((epoch % 7))
  seed="$ts|$mod7|$SESSION|$BASE|${USER:-unknown}"
  root="$(sha256_text "$seed")"
  GENESIS_HASH="$root"
  printf '%s\n' "$root" > "$STATE/genesis.hash"
  jq -cn \
    --arg id "$root" \
    --arg timestamp "$ts" \
    --arg mod7 "$mod7" \
    --arg session "$SESSION" \
    --arg workspace "$BASE" \
    '{genesisHash:$id,timestampMs:$timestamp,mod7:($mod7|tonumber),session:$session,workspace:$workspace}' \
    >> "$DB/roots.jsonl"
  event interaction.created "$(jq -cn --arg genesis "$root" --arg mod7 "$mod7" '{genesisHash:$genesis,mod7:($mod7|tonumber)}')"
}

genesis_current(){
  if [[ -s "$STATE/genesis.hash" ]]; then cat "$STATE/genesis.hash"; else genesis_new; cat "$STATE/genesis.hash"; fi
}

# ----------------------------------------------------------------------------
# SOAP-JSON envelope
# ----------------------------------------------------------------------------
soap_json(){
  local action="$1" body="${2:-{}}" root="${3:-$(genesis_current)}"
  jq -cn \
    --arg action "$action" \
    --arg version "$VERSION" \
    --arg at "$(now)" \
    --arg genesis "$root" \
    --argjson body "$body" \
    '{soap:{version:$version,action:$action,timestamp:$at,genesisHash:$genesis,body:$body}}'
}

# ----------------------------------------------------------------------------
# Tokenizer / entropy / token weights
# ----------------------------------------------------------------------------
normalize_token(){ printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^[:alnum:]_+.#/@:-]/ /g'; }

entropy_text(){
  local text="$1"
  awk -v s="$text" '
  BEGIN {
    n=split(s,a,/[^[:alnum:]_+.#\/@:-]+/); total=0
    for(i=1;i<=n;i++) if(a[i]!=""){ c[a[i]]++; total++ }
    if(total==0){print "0"; exit}
    H=0
    for(k in c){ p=c[k]/total; H-=p*log(p)/log(2) }
    printf "%.8f\n",H
  }'
}

# Returns token<TAB>count<TAB>p<TAB>surprisal<TAB>weight
rank_tokens(){
  local text="$1" tmp total
  tmp="$(mktemp)"
  printf '%s' "$text" | tr '\t\r\n' '   ' | sed 's/[^[:alnum:]_+.#\/@:-]/ /g' | tr '[:upper:]' '[:lower:]' | awk '{for(i=1;i<=NF;i++) print $i}' | sort | uniq -c | sort -k1,1nr -k2,2 > "$tmp"
  total="$(awk '{s+=$1} END{print s+0}' "$tmp")"
  awk -v total="$total" 'BEGIN{OFS="\t"} {p=$1/total; surprisal=-log(p)/log(2); weight=(1-p)*surprisal; print $2,$1,p,surprisal,weight}' "$tmp"
  rm -f "$tmp"
}

score_text(){
  local text="$1" entropy token_count unique_count avg_weight
  entropy="$(entropy_text "$text")"
  token_count="$(printf '%s' "$text" | tr '\t\r\n' '   ' | sed 's/[^[:alnum:]_+.#\/@:-]/ /g' | awk '{n+=NF} END{print n+0}')"
  unique_count="$(rank_tokens "$text" | wc -l | awk '{print $1}')"
  avg_weight="$(rank_tokens "$text" | awk '{s+=$5;n++} END{if(n)printf "%.8f",s/n;else print "0"}')"
  jq -cn --argjson entropy "$entropy" --argjson tokens "$token_count" --argjson unique "$unique_count" --argjson avg "$avg_weight" \
    '{entropy:$entropy,tokenWeightCount:$tokens,uniqueTokens:$unique,avgTokenWeight:$avg}'
}

# ----------------------------------------------------------------------------
# Index files
# ----------------------------------------------------------------------------
index_file(){
  local file="$1" rel sha md5 bytes mtime text entropy parent origin
  [[ -f "$file" ]] || return 0
  bytes="$(wc -c < "$file" | awk '{print $1}')"
  (( bytes > MAX_BYTES )) && { log "skip oversized file: $file"; return 0; }
  sha="$(sha256_file "$file")"
  md5="$(md5_file "$file")"
  rel="${file#$BASE/}"
  mtime="$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo 0)"
  text="$(cat "$file" 2>/dev/null || true)"
  entropy="$(entropy_text "$text")"
  origin="$(md5_text "${GENESIS_HASH:-$(genesis_current)}|$rel")"
  parent="${INDEX_PARENT:-}"
  jq -cn \
    --arg path "$rel" --arg abs "$file" --arg sha "$sha" --arg md5 "$md5" --arg origin "$origin" \
    --arg parent "$parent" --argjson bytes "$bytes" --argjson mtime "$mtime" --argjson entropy "$entropy" \
    --arg indexedAt "$(now)" \
    '{path:$path,absolutePath:$abs,sha256:$sha,md5:$md5,originHash:$origin,parentHash:(if $parent=="" then null else $parent end),bytes:$bytes,mtime:$mtime,entropy:$entropy,indexedAt:$indexedAt}' \
    >> "$DB/files.jsonl"
  printf '%s\n' "$text" > "$OBJECTS/$sha" 2>/dev/null || true
}

index_dir(){
  local root="${1:-$BASE}"
  [[ -d "$root" ]] || die "directory not found: $root"
  root="$(cd "$root" && pwd -P)"
  genesis_new >/dev/null
  local count=0
  while IFS= read -r -d '' f; do
    if [[ "$f" =~ $EXCLUDE_REGEX ]]; then continue; fi
    index_file "$f"; count=$((count+1))
  done < <(find "$root" -type f -print0)
  jq -cn --arg action "index" --arg root "$root" --arg genesis "$GENESIS_HASH" --argjson count "$count" '{action:$action,root:$root,genesisHash:$genesis,count:$count,at:now|todate}'
}

# ----------------------------------------------------------------------------
# CRUD
# ----------------------------------------------------------------------------
resolve_workspace_path(){
  local input="$1" abs
  [[ "$input" = /* ]] && abs="$input" || abs="$BASE/$input"
  abs="$(realpath -m "$abs" 2>/dev/null || readlink -m "$abs" 2>/dev/null || echo "$abs")"
  case "$abs" in "$BASE"|"$BASE"/*) printf '%s' "$abs";; *) die "path escapes workspace: $input";; esac
}

crud(){
  local op="$1" path="$2" text="${3:-}" abs sha md5 parent
  abs="$(resolve_workspace_path "$path")"
  case "$op" in
    create)
      [[ ! -e "$abs" ]] || die "already exists: $path"
      mkdir -p "$(dirname "$abs")"; : > "$abs"; index_file "$abs"; echo "created: $path" ;;
    read)
      [[ -f "$abs" ]] || die "not a file: $path"
      cat "$abs" ;;
    write|update)
      mkdir -p "$(dirname "$abs")"; printf '%s' "$text" > "$abs"; index_file "$abs"; echo "written: $path" >&2 ;;
    append)
      mkdir -p "$(dirname "$abs")"; printf '%s' "$text" >> "$abs"; index_file "$abs"; echo "appended: $path" >&2 ;;
    delete|remove)
      [[ -e "$abs" ]] || die "not found: $path"; rm -f -- "$abs"; echo "deleted: $path" ;;
    list)
      find "$abs" -maxdepth 1 -mindepth 1 -printf '%f\n' 2>/dev/null || ls -la "$abs" ;;
    *) die "crud: create|read|write|append|delete|list" ;;
  esac
}

# ----------------------------------------------------------------------------
# Runtime reference capture
# ----------------------------------------------------------------------------
capture_llama_reference(){
  command -v "$LLAMA_BIN" >/dev/null 2>&1 || { echo "llama binary not found: $LLAMA_BIN" >&2; return 2; }
  local ts raw1 raw2 sha bundle refid
  ts="$(now)"
  raw1="$($LLAMA_BIN --help 2>&1 || true)"
  raw2="$($LLAMA_BIN cli -h 2>&1 || true)"
  local raw3
  raw3="$($LLAMA_BIN help all 2>&1 || true)"
  bundle=$(cat <<EOF
=== llama --help ===
$raw1
=== llama cli -h ===
$raw2
=== llama help all ===
$raw3
EOF
)
  sha="$(sha256_text "$bundle")"
  refid="$(md5_text "reference|$sha|$ts")"
  printf '%s\n' "$bundle" > "$REFS/llama-cli-help-$sha.txt"
  jq -cn --arg id "$refid" --arg sha "$sha" --arg at "$ts" --arg bin "$LLAMA_BIN" --arg text "$bundle" \
    '{referenceId:$id,sha256:$sha,md5Root:$id,at:$at,binary:$bin,commandReference:$text}' \
    >> "$DB/reference.jsonl"
  # Extract likely top-level command names, preserving raw help as authority.
  printf '%s\n' "$raw1" | awk '\n    /^[[:space:]]{2,}[a-zA-Z0-9_-]+[[:space:]]/ {gsub(/^ +| +$/,"",$1); if($1!="") print $1}\n  ' | sort -u | while IFS= read -r cmd; do
      [[ -n "$cmd" ]] || continue
      jq -cn --arg cmd "$cmd" --arg sha "$sha" --arg at "$ts" '{kind:"llama-subcommand",command:$cmd,referenceSha256:$sha,at:$at}' >> "$DB/reference.jsonl"
    done
  printf '%s\n' "$REFS/llama-cli-help-$sha.txt"
}

# ----------------------------------------------------------------------------
# Exact llama passthrough
# ----------------------------------------------------------------------------
llama_passthrough(){
  command -v "$LLAMA_BIN" >/dev/null 2>&1 || die "llama binary not found: $LLAMA_BIN"
  "$LLAMA_BIN" "$@"
}

# ----------------------------------------------------------------------------
# Envelope parser
# ----------------------------------------------------------------------------
PROMPT=""
EXTRA=()
parse_envelope(){
  local input="$*" tok
  PROMPT=""
  EXTRA=()
  while [[ "$input" =~ ^[[:space:]]*([^[:space:]]+)([[:space:]]+(.*))?$ ]]; do
    tok="${BASH_REMATCH[1]}"
    input="${BASH_REMATCH[3]}"
    if [[ "$tok" == @model=* ]]; then MODEL="${tok#@model=}"
    elif [[ "$tok" == @views=* ]]; then VIEWS="${tok#@views=}"
    elif [[ "$tok" == @synthesis=* ]]; then SYNTHESIS="${tok#@synthesis=}"
    elif [[ "$tok" == @temp=* ]]; then TEMP="${tok#@temp=}"
    elif [[ "$tok" == @ctx=* ]]; then CTX="${tok#@ctx=}"
    elif [[ "$tok" == @threads=* ]]; then THREADS="${tok#@threads=}"
    elif [[ "$tok" == @gpu_layers=* ]]; then GPU_LAYERS="${tok#@gpu_layers=}"
    elif [[ "$tok" == @parallel=* ]]; then PARALLEL="${tok#@parallel=}"
    else
      PROMPT+="${PROMPT:+ }$tok"
    fi
    [[ -n "$input" ]] || break
  done
  [[ -n "$PROMPT" ]] || PROMPT="$*"
}

# ----------------------------------------------------------------------------
# Prompt execution / multiview
# ----------------------------------------------------------------------------
run_one(){
  local prompt="$1" view="$2" outFile="$3" parent="$4"
  local viewName="view-$view" seed score sha md5 origin cmdrc
  seed=$(( (10#$view + 1) * 7919 + 7 ))
  viewName="${VIEW_NAMES[$view]:-view-$view}"
  event step.start "$(jq -cn --arg view "$view" --arg name "$viewName" '{view:($view|tonumber),name:$name}')"
  local role
  role="${VIEW_ROLES[$view]:-Analyze the task from an independent technical perspective.}"
  local vp
  vp=$(cat <<EOF
SYSTEM ROLE:
$role

CONSTRAINTS:
- Return conclusions and actionable rationale; do not expose hidden chain-of-thought.
- Separate observations from assumptions.
- Preserve requested scope.
- Prefer verifiable local behavior.

TASK:
$prompt

MULTIVIEW:
This is perspective $view of $VIEWS using a deterministic 2pi/8 rotation concept.
EOF
)
  local -a args=(cli -hf "$MODEL" --ctx-size "$CTX" --threads "$THREADS" --gpu-layers "$GPU_LAYERS" --temp "$TEMP")
  if [[ -n "$TOP_P" ]]; then args+=(--top-p "$TOP_P"); fi
  if [[ -n "$TOP_K" ]]; then args+=(--top-k "$TOP_K"); fi
  if [[ -n "$REPEAT_PENALTY" ]]; then args+=(--repeat-penalty "$REPEAT_PENALTY"); fi
  args+=(--seed "$seed" --prompt "$vp")
  log "llama view=$view name=$viewName"
  if [[ "$TIMEOUT" =~ ^[0-9]+$ ]] && command -v timeout >/dev/null 2>&1; then
    timeout "${TIMEOUT}s" "$LLAMA_BIN" "${args[@]}" > "$outFile" 2> "$outFile.stderr"
    cmdrc=$?
  else
    "$LLAMA_BIN" "${args[@]}" > "$outFile" 2> "$outFile.stderr"
    cmdrc=$?
  fi
  if (( cmdrc != 0 )); then
    event step.stop "$(jq -cn --arg view "$view" --arg code "$cmdrc" '{view:($view|tonumber),status:"failed",exitCode:($code|tonumber)}')"
    printf 'view %s failed (%s): %s\n' "$view" "$cmdrc" "$(tail -n 3 "$outFile.stderr" 2>/dev/null)" >&2
    return "$cmdrc"
  fi
  local text
  text="$(cat "$outFile")"
  sha="$(sha256_text "$text")"
  md5="$(md5_text "$text")"
  origin="$(md5_text "${GENESIS_HASH}|$view|$parent")"
  local metrics
  metrics="$(score_text "$text")"
  local entropy
  entropy="$(jq -r '.entropy' <<<"$metrics")"
  local weight
  weight="$(jq -r '.avgTokenWeight' <<<"$metrics")"
  local rankScore
  rankScore="$(awk -v e="$entropy" -v w="$weight" 'BEGIN{printf "%.8f", (e+1)*(w+1)}')"
  jq -cn --arg id "$sha" --arg view "$view" --arg name "$viewName" --arg parent "$parent" --arg genesis "$GENESIS_HASH" \
    --arg md5 "$md5" --arg origin "$origin" --argjson metrics "$metrics" --argjson score "$rankScore" \
    '{type:"model-output",id:$id,view:($view|tonumber),viewName:$name,parentHash:$parent,genesisHash:$genesis,md5:$md5,originHash:$origin,metrics:$metrics,score:$score,at:now|todate}' >> "$DB/traces.jsonl"
  object_put "$text" >/dev/null
  cp "$outFile" "$STATE/last-view-$view.txt"
  event step.delta "$(jq -cn --arg view "$view" --arg sha "$sha" --argjson score "$rankScore" '{view:($view|tonumber),sha256:$sha,score:$score}')"
  event step.stop "$(jq -cn --arg view "$view" '{view:($view|tonumber),status:"completed"}')"
  return 0
}

VIEW_NAMES=(Nexus Cognito Relay Sentinel Echo Vector-8 XOR-Pool Origin-7)
VIEW_ROLES=(
  "Structural architect: decompose requirements into robust modules and interfaces."
  "Entropy analyst: identify ambiguity, diversity, information density, and priorities."
  "Context router: normalize inputs, files, parameters, and operational constraints."
  "Validation guard: search for failures, security issues, unsafe assumptions, and edge cases."
  "Synthesis planner: identify compatible conclusions and implementation paths."
  "Systems optimizer: minimize CPU, memory, latency, and redundant work."
  "Adversarial evaluator: challenge assumptions and propose counterexamples."
  "Origin tracer: preserve provenance, lineage, reproducibility, and rollback paths."
)

synthesize(){
  local prompt="$1" parent="$2" bundle="$STATE/view-bundle.txt"
  : > "$bundle"
  for f in "$STATE"/view-*.txt; do
    [[ -f "$f" ]] || continue
    printf '\n=== %s ===\n' "$(basename "$f")" >> "$bundle"
    cat "$f" >> "$bundle"
  done
  local synthesisPrompt
  synthesisPrompt=$(cat <<EOF
You are the synthesis stage of a local multi-view software agent.

Original task:
$prompt

Candidate perspectives are stored below.

$(cat "$bundle")

Produce the final answer by selecting compatible, evidence-backed conclusions.
Do not expose hidden chain-of-thought. Give conclusions, implementation details,
and verification steps. Preserve provenance by referring to the strongest view
when useful.
EOF
)
  event step.start "$(jq -cn '{stage:"synthesis"}')"
  local out="$STATE/final.txt"
  local -a args=(cli -hf "$MODEL" --ctx-size "$CTX" --threads "$THREADS" --gpu-layers "$GPU_LAYERS" --temp "$TEMP" --prompt "$synthesisPrompt")
  "$LLAMA_BIN" "${args[@]}" > "$out" 2> "$out.stderr"
  local rc=$?
  if (( rc != 0 )); then
    event step.stop "$(jq -cn --arg code "$rc" '{stage:"synthesis",status:"failed",exitCode:($code|tonumber)}')"
    return "$rc"
  fi
  local text sha md5 metrics score
  text="$(cat "$out")"
  sha="$(sha256_text "$text")"
  md5="$(md5_text "$text")"
  metrics="$(score_text "$text")"
  score="$(awk -v e="$(jq -r .entropy <<<"$metrics")" -v w="$(jq -r .avgTokenWeight <<<"$metrics")" 'BEGIN{printf "%.8f",(e+1)*(w+1)}')"
  jq -cn --arg id "$sha" --arg parent "$parent" --arg genesis "$GENESIS_HASH" --arg md5 "$md5" --argjson metrics "$metrics" --argjson score "$score" \
    '{type:"synthesis",id:$id,parentHash:$parent,genesisHash:$genesis,md5:$md5,metrics:$metrics,score:$score,at:now|todate}' >> "$DB/traces.jsonl"
  event step.stop "$(jq -cn --arg sha "$sha" '{stage:"synthesis",status:"completed",sha256:$sha}')"
  event interaction.completed "$(jq -cn --arg sha "$sha" '{finalSha256:$sha}')"
  cat "$out"
}

run_prompt(){
  local raw="$*"
  parse_envelope "$raw"
  [[ -n "$PROMPT" ]] || die 'run requires a prompt'
  genesis_new >/dev/null
  local inputHash originHash taskId sessionAt
  inputHash="$(sha256_text "$PROMPT")"
  originHash="$(md5_text "$GENESIS_HASH|$PROMPT")"
  taskId="$(sha256_text "$GENESIS_HASH|$originHash|$inputHash")"
  sessionAt="$(now)"
  jq -cn --arg task "$taskId" --arg input "$inputHash" --arg origin "$originHash" --arg genesis "$GENESIS_HASH" --arg session "$SESSION" --arg prompt "$PROMPT" \
    '{taskId:$task,sha256:$input,originHash:$origin,genesisHash:$genesis,session:$session,prompt:$prompt,createdAt:$session|now|todate}' >> "$DB/tasks.jsonl"
  event step.start "$(jq -cn --arg task "$taskId" '{stage:"task-index",taskId:$task}')"

  (( VIEWS < 1 )) && VIEWS=1
  (( VIEWS > 8 )) && VIEWS=8
  local i rc=0 out
  : > "$STATE/view-bundle.txt"
  for ((i=0;i<VIEWS;i++)); do
    out="$STATE/view-$i.txt"
    if ! run_one "$PROMPT" "$i" "$out" "$taskId"; then rc=1; break; fi
  done
  (( rc == 0 )) || die 'one or more llama views failed'

  local ranked="$STATE/ranking.json"
  jq -s 'map(select(.type=="model-output")) | sort_by(-.score)' "$DB/traces.jsonl" > "$ranked"
  cp "$ranked" "$STATE/last-ranking.json"
  event step.stop "$(jq -cn --arg task "$taskId" --arg views "$VIEWS" '{stage:"ranking",taskId:$task,views:($views|tonumber)}')"

  local top="$(jq -r '.[0].id // empty' "$ranked")"
  if [[ "$SYNTHESIS" == true || "$SYNTHESIS" == 1 ]]; then
    synthesize "$PROMPT" "$top"
  else
    [[ -f "$STATE/view-0.txt" ]] && cat "$STATE/view-0.txt"
  fi
}

# ----------------------------------------------------------------------------
# Token rank command: every token gets MD5-root / SHA-256 source / score
# ----------------------------------------------------------------------------
rank_command(){
  local input="$*"
  [[ -n "$input" ]] || { [[ ! -t 0 ]] && input="$(cat)"; }
  [[ -n "$input" ]] || die 'rank requires data'
  local genesis root
  genesis="$(genesis_current)"
  root="$(md5_text "$genesis|$input")"
  local line token count p surprisal weight sha
  while IFS=$'\t' read -r token count p surprisal weight; do
    [[ -n "$token" ]] || continue
    sha="$(sha256_text "$genesis|$root|$token")"
    jq -cn --arg token "$token" --arg root "$root" --arg sha "$sha" --argjson count "$count" --argjson p "$p" --argjson surprisal "$surprisal" --argjson weight "$weight" \
      '{md5Root:$root,sha256:$sha,token:$token,count:$count,probability:$p,surprisal:$surprisal,weight:$weight,at:now|todate}' >> "$DB/tokens.jsonl"
  done < <(rank_tokens "$input")
  rank_tokens "$input" | sort -t$'\t' -k5,5nr | sed 's/^/RANK\t/'
}

trace_command(){
  local id="$1"
  [[ -n "$id" ]] || die 'trace requires a hash/prefix'
  jq -c --arg id "$id" 'select((.id//"")|startswith($id) or (.parentHash//"")|startswith($id) or (.originHash//"")|startswith($id) or (.genesisHash//"")|startswith($id))' "$DB/traces.jsonl" 2>/dev/null || true
}

status_command(){
  local g="$(genesis_current)"
  jq -cn --arg version "$VERSION" --arg name "$AI_NAME" --arg workspace "$BASE" --arg state "$STATE" --arg model "$MODEL" --arg llama "$LLAMA_BIN" --arg genesis "$g" --argjson views "$VIEWS" \
    '{name:$name,version:$version,workspace:$workspace,state:$state,llama:$llama,model:$model,views:$views,genesisHash:$genesis}'
}

usage(){
cat <<'EOF'
ai.sh — local llama CLI / CRUD / genesis / SHA256 entropy indexer

COMMANDS
  init [DIR]                       initialize state/workspace
  status                           runtime state
  doctor                           verify dependencies + llama binary
  reference                        capture `llama --help` + `llama cli -h`
  run PROMPT                       execute llama workflow
  prompt PROMPT                    alias for run
  parse DATA                       parse @key=value envelope
  rank DATA                        rank every token by weighted entropy
  index DIR                        file-index directory
  trace HASH                       traceback indexed reasoning/output nodes
  crud OP PATH [TEXT]              create/read/write/append/delete/list
  soap ACTION JSON                 emit SOAP-JSON envelope
  export FILE                      export database manifest
  llama ARGS...                    exact `llama ARGS...` passthrough
  cli ARGS...                      exact `llama cli ARGS...` passthrough
  serve ARGS...                    exact `llama serve ARGS...` passthrough
  download ARGS...                 exact `llama download ARGS...` passthrough
  update ARGS...                   exact `llama update ARGS...` passthrough
  completion ARGS...               exact `llama completion ARGS...` passthrough

RUN PARAMETERS
  --model MODEL
  --ctx N
  --threads N
  --gpu-layers N
  --temp N
  --top-p N
  --top-k N
  --repeat-penalty N
  --views N                       1..8 bounded passes
  --parallel 0|1                  reserved/bounded; default sequential
  --synthesis true|false
  --session NAME
  --verbose

ENVELOPE
  @model=MODEL @views=8 @synthesis=true @temp=.65 @ctx=4096 @threads=8

DATABASE
  $DB/*.jsonl                      append-only JSONL state
  $OBJECTS/<sha256>                content-addressed objects
  $REFS/                            captured llama command reference

NOTES
  - SHA-256 is used for content identity/integrity.
  - MD5 is used only as a compact legacy/origin root identifier.
  - Shannon entropy and token weights are computed independently from hashes.
  - The stored llama command reference is authoritative for the installed build.
  - No Gemini SDK/API is invoked by this script.
EOF
}

# ----------------------------------------------------------------------------
# Argument parsing / main
# ----------------------------------------------------------------------------
cmd="${1:-}"
[[ -n "$cmd" ]] && shift || { usage; exit 0; }

case "$cmd" in
  init)
    target="${1:-$BASE}"; mkdir -p "$target/.ai-state/db/objects" "$target/.ai-state/db/reference"; echo "initialized: $target" ;;
  status)
    status_command ;;
  doctor)
    printf 'bash=%s\n' "$BASH_VERSION"
    printf 'jq=%s\n' "$(jq --version 2>/dev/null || echo missing)"
    printf 'sha256=%s\n' "$SHA_CMD"
    printf 'md5=%s\n' "${MD5_CMD:-missing}"
    if command -v "$LLAMA_BIN" >/dev/null 2>&1; then printf 'llama=%s\n' "$(command -v "$LLAMA_BIN")"; "$LLAMA_BIN" --version 2>&1 || true
    else printf 'llama=missing\n'; fi ;;
  reference)
    capture_llama_reference ;;
  parse)
    parse_envelope "$*"
    jq -cn --arg model "$MODEL" --arg views "$VIEWS" --arg synthesis "$SYNTHESIS" --arg temp "$TEMP" --arg ctx "$CTX" --arg threads "$THREADS" --arg gpu "$GPU_LAYERS" --arg prompt "$PROMPT" \
      '{model:$model,views:($views|tonumber),synthesis:$synthesis,temp:($temp|tonumber),ctx:($ctx|tonumber),threads:($threads|tonumber),gpuLayers:($gpu|tonumber),prompt:$prompt}' ;;
  rank)
    rank_command "$*" ;;
  index)
    index_dir "${1:-$BASE}" ;;
  trace)
    trace_command "${1:-}" ;;
  crud)
    op="${1:-}"; path="${2:-}"; shift 2 || true; crud "$op" "$path" "$*" ;;
  soap)
    soap_json "${1:-unknown}" "${2:-{}}" ;;
  export)
    out="${1:-$BASE/ai-export.json}"
    jq -s 'sort_by(.at // .createdAt // "")' "$DB"/*.jsonl > "$out"
    echo "$out" ;;
  llama)
    llama_passthrough "$@" ;;
  cli)
    llama_passthrough cli "$@" ;;
  serve|download|update|completion)
    llama_passthrough "$cmd" "$@" ;;
  prompt|run)
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --model) MODEL="${2:?missing model}"; shift 2;;
        --ctx) CTX="${2:?missing ctx}"; shift 2;;
        --threads) THREADS="${2:?missing threads}"; shift 2;;
        --gpu-layers) GPU_LAYERS="${2:?missing gpu layers}"; shift 2;;
        --temp) TEMP="${2:?missing temp}"; shift 2;;
        --top-p) TOP_P="${2:?missing top-p}"; shift 2;;
        --top-k) TOP_K="${2:?missing top-k}"; shift 2;;
        --repeat-penalty) REPEAT_PENALTY="${2:?missing repeat penalty}"; shift 2;;
        --views) VIEWS="${2:?missing views}"; shift 2;;
        --parallel) PARALLEL="${2:?missing parallel}"; shift 2;;
        --synthesis) SYNTHESIS="${2:?missing synthesis}"; shift 2;;
        --session) SESSION="${2:?missing session}"; shift 2;;
        --verbose|-v) VERBOSE=1; shift;;
        --) shift; break;;
        @*) break;;
        -*) die "unknown run option: $1";;
        *) break;;
      esac
    done
    run_prompt "$*" ;;
  help|-h|--help)
    usage ;;
  version|--version|-V)
    echo "$VERSION" ;;
  *)
    # Bare invocation is a prompt for compatibility with the earlier ai.sh UX.
    run_prompt "$cmd ${*:-}" ;;
esac

