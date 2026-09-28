#!/usr/bin/env bash
# GENESIS/HX unified local controller v17.0.0
# One CLI + state tree + llama.cpp adapter; eight POVs run sequentially.
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

AI_VERSION=17.0.0
AI_HOME="${AI_HOME:-${HOME:-/home/loop}/.ai}"
STATE="${AI_STATE_DIR:-$AI_HOME/state}"
DB="$STATE/db"; OBJECTS="$DB/objects"; RUN="$STATE/run"; LOG="$STATE/logs"; SESS="$STATE/sessions"
WORKSPACE="${AI_WORKSPACE:-$AI_HOME/workspace}"
MODEL_DIR="${AI_MODEL_DIR:-$AI_HOME/models}"
LEDGER="${AI_LEDGER_FILE:-$DB/ledger.jsonl}"
INDEX="$DB/file_index.json"
LLAMA_CLI="${LLAMA_CLI:-${HOME:-/home/loop}/.local/bin/llama}"
PRIMARY="${AI_MODEL_PATH:-$MODEL_DIR/qwen2.5-coder-3b-instruct-q4_k_m.gguf}"
FALLBACK="${AI_FALLBACK_PATH:-$MODEL_DIR/qwen2.5-1.5b-instruct-q4_k_m.gguf}"
CTX="${AI_CONTEXT:-2048}"; BATCH="${AI_BATCH:-128}"; UBATCH="${AI_UBATCH:-64}"
PREDICT="${AI_PREDICT:-384}"; THREADS="${AI_THREADS:-4}"; TIMEOUT="${AI_TIMEOUT:-600}"
TEMP="${AI_TEMPERATURE:-0.65}"; TOPK="${AI_TOP_K:-40}"; TOPP="${AI_TOP_P:-0.95}"
REPEAT="${AI_REPEAT_PENALTY:-1.10}"; VIEWS="${AI_VIEWS:-8}"; DEPTH="${AI_DEPTH:-1}"
SYNTH="${AI_SYNTHESIS:-true}"; SESSION="${AI_SESSION:-default}"
mkdir -p "$OBJECTS" "$RUN" "$LOG" "$SESS" "$WORKSPACE" "$MODEL_DIR"
[[ -f "$INDEX" ]] || printf '{"version":1,"files":[]}\n' > "$INDEX"
if [[ -t 1 ]]; then C=$'\033[36m'; R=$'\033[0m'; Y=$'\033[33m'; else C='';R='';Y='';fi
say(){ printf '%s[GENESIS]%s %s\n' "$C" "$R" "$*"; }
warn(){ printf '%s[WARN]%s %s\n' "$Y" "$R" "$*" >&2; }
die(){ printf '[ERROR] %s\n' "$*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }
now(){ date -u '+%Y-%m-%dT%H:%M:%SZ'; }
esc(){ local x=$1; x=${x//\\/\\\\}; x=${x//\"/\\\"}; x=${x//$'\n'/\\n}; x=${x//$'\r'/\\r}; x=${x//$'\t'/\\t}; printf %s "$x"; }
hash_text(){ if have sha256sum; then printf %s "$1"|sha256sum|awk '{print $1}'; else printf %s "$1"|shasum -a 256|awk '{print $1}'; fi; }
hash_file(){ if have sha256sum; then sha256sum "$1"|awk '{print $1}'; else shasum -a 256 "$1"|awk '{print $1}'; fi; }
is_gguf(){ [[ -s "$1" && "$(head -c4 "$1" 2>/dev/null || true)" == GGUF ]]; }
json_valid(){ if have jq; then jq -e . "$1" >/dev/null; elif have python3; then python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$1"; else return 2; fi; }

event(){
  local type=$1 payload=${2:-} ts parent h line
  ts=$(now); line=$(tail -n1 "$LEDGER" 2>/dev/null || true); parent=GENESIS
  if [[ -n "$line" ]] && have jq; then parent=$(jq -r '.hash // "GENESIS"' <<<"$line"); fi
  h=$(hash_text "$ts|$type|$parent|$payload")
  printf '{"timestamp":"%s","type":"%s","parent":"%s","hash":"%s","payload":"%s"}\n' "$(esc "$ts")" "$(esc "$type")" "$(esc "$parent")" "$h" "$(esc "$payload")" >> "$LEDGER"
  printf %s "$h"
}
artifact(){
  local kind=$1 body=$2 parent=${3:-} h
  h=$(hash_text "$body")
  [[ -f "$OBJECTS/$h.txt" ]] || printf %s "$body" > "$OBJECTS/$h.txt"
  printf '{"hash":"%s","kind":"%s","parent":"%s","created":"%s"}\n' "$h" "$(esc "$kind")" "$(esc "$parent")" "$(now)" > "$OBJECTS/$h.json"
  printf %s "$h"
}
resolve_model(){
  MODEL_PATH=; MODEL_TIER=none
  if [[ -f "$PRIMARY" ]] && is_gguf "$PRIMARY"; then MODEL_PATH=$PRIMARY; MODEL_TIER=primary
  elif [[ -f "$FALLBACK" ]] && is_gguf "$FALLBACK"; then MODEL_PATH=$FALLBACK; MODEL_TIER=fallback
  else return 1; fi
}
validate_config(){
  local n v
  for n in CTX BATCH UBATCH PREDICT THREADS TIMEOUT VIEWS DEPTH; do v=${!n}; [[ "$v" =~ ^[0-9]+$ ]] || die "$n must be an integer"; done
  ((CTX>0&&BATCH>0&&UBATCH>0&&PREDICT>0&&THREADS>0&&VIEWS>=1&&VIEWS<=8&&DEPTH>=1&&DEPTH<=16)) || die "invalid numeric configuration"
}

# The sole inference adapter. Detects dispatcher (`llama cli`) vs classic binary.
declare -a BASE=() CMD=()
HELP_TEXT=""
detect_adapter(){
  [[ -x "$LLAMA_CLI" ]] || { warn "llama runtime missing: $LLAMA_CLI"; return 127; }
  local h; h=$("$LLAMA_CLI" --help 2>&1 || true)
  if grep -Eq '(^|[[:space:]])cli([[:space:]]|$)' <<<"$h"; then BASE=("$LLAMA_CLI" cli); else BASE=("$LLAMA_CLI"); fi
  HELP_TEXT=$("${BASE[@]}" --help 2>&1 || true)
}
supports(){ grep -Eq -- "(^|[[:space:]])$1([=[:space:]]|,|$)" <<<"$HELP_TEXT"; }
infer(){
  local prompt=$1 model=${2:-$MODEL_PATH} out='' rc=0 err="$RUN/llama.stderr"
  [[ -n "$model" && -f "$model" && -s "$model" ]] || { warn "unresolved model path"; return 2; }
  is_gguf "$model" || { warn "model is not valid GGUF"; return 2; }
  detect_adapter || return $?
  CMD=("${BASE[@]}" --model "$model")
  if supports '--ctx-size'; then CMD+=(--ctx-size "$CTX"); elif supports '-c'; then CMD+=(-c "$CTX"); fi
  if supports '--batch-size'; then CMD+=(--batch-size "$BATCH"); elif supports '-b'; then CMD+=(-b "$BATCH"); fi
  supports '--ubatch-size' && CMD+=(--ubatch-size "$UBATCH")
  if supports '--predict'; then CMD+=(--predict "$PREDICT"); elif supports '-n'; then CMD+=(-n "$PREDICT"); fi
  if supports '--threads'; then CMD+=(--threads "$THREADS"); elif supports '-t'; then CMD+=(-t "$THREADS"); fi
  supports '--temp' && CMD+=(--temp "$TEMP")
  supports '--top-k' && CMD+=(--top-k "$TOPK")
  supports '--top-p' && CMD+=(--top-p "$TOPP")
  supports '--repeat-penalty' && CMD+=(--repeat-penalty "$REPEAT")
  supports '--single-turn' && CMD+=(--single-turn)
  if supports '--prompt'; then CMD+=(--prompt "$prompt")
  elif supports '-p'; then CMD+=(-p "$prompt"); fi
  if [[ "${CMD[-1]:-}" == "$prompt" ]]; then
    if have timeout; then out=$(timeout "$TIMEOUT" "${CMD[@]}" 2>"$err") || rc=$?; else out=$("${CMD[@]}" 2>"$err") || rc=$?; fi
  else
    if have timeout; then out=$(printf %s "$prompt"|timeout "$TIMEOUT" "${CMD[@]}" 2>"$err") || rc=$?; else out=$(printf %s "$prompt"|"${CMD[@]}" 2>"$err") || rc=$?; fi
  fi
  if ((rc)); then warn "llama rc=$rc: $(tail -n6 "$err" 2>/dev/null|tr '\n' ' ')"; event inference_error "rc=$rc model=$model" >/dev/null; return "$rc"; fi
  printf %s "$out"
}
NAMES=(analytical architectural critical creative implementation adversarial systems synthesis)
ANGLES=(0 45 90 135 180 225 270 315)
declare -a FILES=() SCORES=() CNAMES=()
score_text(){
  local t=$1 w s=0 d=0
  w=$(awk '{n+=NF}END{print n+0}' <<<"$t")
  grep -Eq '(^|[[:space:]])([0-9]+\.|- |\* )' <<<"$t" && ((s+=1)) || true
  grep -Eiq 'because|therefore|however|implementation|solution|constraint' <<<"$t" && ((s+=1)) || true
  grep -q ':' <<<"$t" && ((s+=1)) || true
  grep -Eiq 'answer|solution|implement|use|change|run|configure|fix' <<<"$t" && ((d+=1)) || true
  ((${#t}>200)) && ((d+=1)) || true
  awk -v w="$w" -v s="$s" -v d="$d" 'BEGIN{l=(w>=100?100:w>=50?80:w>=20?60:w>=8?30:0);printf "%.3f",l*.2+(s/3*100)*.2+(d/2*100)*.2+(s>=2?100:s*50)*.3+5}'
}
run_engine(){
  local original=$1 task genesis depth i name pp out h score best bs result bundle
  validate_config; [[ -n "$original" ]] || die "empty prompt"
  resolve_model || die "no valid GGUF at $PRIMARY or $FALLBACK"
  genesis=$(hash_text "$(now)|$AI_VERSION|$original"); task=$(hash_text "$genesis|$original")
  event genesis "genesis=$genesis" >/dev/null; event task "task=$task" >/dev/null
  say "model=$MODEL_TIER views=$VIEWS depth=$DEPTH genesis=$genesis"
  for ((depth=1;depth<=DEPTH;depth++)); do
    FILES=(); SCORES=(); CNAMES=()
    for ((i=0;i<VIEWS;i++)); do
      name=${NAMES[$i]}; say "round $depth/$DEPTH · POV $((i+1))/$VIEWS $name @ ${ANGLES[$i]}°"
      pp=$(cat <<EOF
You are the $name perspective in a multi-view analysis.
TASK: $original
VIEW: $name at ${ANGLES[$i]} degrees
GENESIS: $genesis
TASK HASH: $task
Give a focused useful analysis. State assumptions, separate facts from inference, identify constraints and testable steps. Do not claim tool execution. Return only this perspective.
EOF
)
      out=$(infer "$pp" "$MODEL_PATH") || { warn "POV $name failed"; continue; }
      [[ -n "$out" ]] || continue
      h=$(artifact "pov:$name" "$out" "$task"); score=$(score_text "$out")
      FILES+=("$h"); SCORES+=("$score"); CNAMES+=("$name")
      event pov "task=$task pov=$name angle=${ANGLES[$i]} hash=$h score=$score" >/dev/null
    done
    ((${#FILES[@]}>0)) || die "all POV executions failed"
    best=0; bs=${SCORES[0]}
    for ((i=1;i<${#FILES[@]};i++)); do if awk -v a="${SCORES[$i]}" -v b="$bs" 'BEGIN{exit !(a>b)}'; then best=$i; bs=${SCORES[$i]}; fi; done
    result=$(cat "$OBJECTS/${FILES[$best]}.txt")
    if [[ "${SYNTH,,}" == true && ${#FILES[@]} -gt 1 ]]; then
      bundle="TASK: $original"$'\n\n'"CANDIDATES:"
      for ((i=0;i<${#FILES[@]};i++)); do bundle+=$'\n\n'"--- ${CNAMES[$i]} score=${SCORES[$i]} ---"$'\n'"$(cat "$OBJECTS/${FILES[$i]}.txt")"; done
      bundle+=$'\n\n'"Synthesize a coherent response, reconcile contradictions, retain constraints, avoid unsupported claims. Return only the final answer."
      result=$(infer "$bundle" "$MODEL_PATH") || { warn "synthesis failed; selecting top candidate"; result=$(cat "$OBJECTS/${FILES[$best]}.txt"); }
      h=$(artifact synthesis "$result" "$task"); event synthesis "task=$task hash=$h" >/dev/null
    fi
    h=$(artifact "round:$depth" "$result" "$task"); event round "depth=$depth task=$task result=$h" >/dev/null
    if ((depth<DEPTH)); then original="Original task: $1"$'\n\n'"Prior result: $result"$'\n\n'"Continue by resolving gaps and improving precision."; task=$(hash_text "$genesis|$original|depth=$((depth+1))"); fi
  done
  printf '%s\n' "$result"
}
status(){
  printf 'GENESIS/HX %s\nRuntime: %s\nModel: %s (%s)\nContext=%s Threads=%s Views=%s Depth=%s Synthesis=%s\nState: %s\nWorkspace: %s\n' "$AI_VERSION" "$LLAMA_CLI" "${MODEL_PATH:-unresolved}" "$MODEL_TIER" "$CTX" "$THREADS" "$VIEWS" "$DEPTH" "$SYNTH" "$STATE" "$WORKSPACE"
}
doctor(){
  printf 'Bash %s\n' "$BASH_VERSION"
  for x in sha256sum shasum jq python3 timeout node; do have "$x" && echo "$x OK" || echo "$x optional/missing"; done
  [[ -x "$LLAMA_CLI" ]] && "$LLAMA_CLI" --version 2>&1|head -n1 || warn "llama missing"
  resolve_model && printf 'GGUF %s (%s)\n' "$MODEL_PATH" "$MODEL_TIER" || warn "no verified GGUF"
}
index_workspace(){
  local tmp="$RUN/index.$$" f rel h first=true
  printf '{"version":1,"generated":"%s","files":[' "$(now)" > "$tmp"
  while IFS= read -r -d '' f; do
    rel=${f#"$WORKSPACE"/}; h=$(hash_file "$f")
    [[ $first == true ]] || printf ',' >> "$tmp"; first=false
    printf '{"path":"%s","sha256":"%s","bytes":%s}' "$(esc "$rel")" "$h" "$(wc -c <"$f"|tr -d ' ')" >> "$tmp"
  done < <(find "$WORKSPACE" -type f -print0)
  printf ']}\n' >> "$tmp"
  json_valid "$tmp" || { rm -f "$tmp"; die "index validation failed (jq or python3 required)"; }
  mv -f "$tmp" "$INDEX"; say "index updated: $INDEX"
}
file_cmd(){
  local op=${1:-} path=${2:-} data=${3:-} target
  [[ -n "$op" && -n "$path" ]] || die "usage: ai file create|read|write|append|delete PATH [DATA]"
  case "$path" in /*) target=$path;; *) target="$WORKSPACE/$path";; esac
  case "$op" in
    create) [[ ! -e "$target" ]] || die "already exists"; mkdir -p "$(dirname "$target")"; printf %s "$data" > "$target";;
    read) [[ -f "$target" ]] || die "not found"; cat "$target";;
    write) mkdir -p "$(dirname "$target")"; [[ ! -f "$target" ]] || cp -p "$target" "$target.bak.$(date +%s)"; printf %s "$data" > "$RUN/write.$$"; mv -f "$RUN/write.$$" "$target";;
    append) mkdir -p "$(dirname "$target")"; printf %s "$data" >> "$target";;
    delete) [[ -f "$target" ]] || die "not found"; cp -p "$target" "$target.bak.$(date +%s)"; rm -f "$target";;
    *) die "unknown file operation: $op";;
  esac
  event file "$op $target" >/dev/null
}
help(){
cat <<'EOF'
GENESIS/HX v17.0.0 — unified local llama.cpp controller
ai "prompt" | ai run "prompt" | ai chat
ai status | doctor | models | test | config | version
ai hash TEXT | ledger [N] | index
ai file create|read|write|append|delete PATH [DATA]
Settings: LLAMA_CLI AI_MODEL_PATH AI_FALLBACK_PATH AI_CONTEXT AI_BATCH
AI_UBATCH AI_PREDICT AI_THREADS AI_TIMEOUT AI_VIEWS(1..8) AI_DEPTH(1..16)
AI_SYNTHESIS=true|false AI_WORKSPACE AI_STATE_DIR
EOF
}
chat(){
  local p ans
  while printf 'hx> ' && IFS= read -r p; do
    case "$p" in /exit|/quit) break;; /help) help;; /status) status;; '') continue;; *) ans=$(run_engine "$p"); printf '%s\n' "$ans"; printf '[%s] USER\n%s\n[%s] ASSISTANT\n%s\n' "$(now)" "$p" "$(now)" "$ans" >> "$SESS/${SESSION//[^a-zA-Z0-9_.-]/_}.log";; esac
  done
}
main(){
  local cmd=${1:-help}
  case "$cmd" in
    help|-h|--help) help;; version|-V|--version) echo "$AI_VERSION";;
    status) resolve_model >/dev/null 2>&1 || true; status;;
    doctor) doctor;;
    models|model) resolve_model && printf '%s (%s)\n' "$MODEL_PATH" "$MODEL_TIER" || warn "no valid GGUF";;
    config) printf 'AI_HOME=%s\nSTATE=%s\nWORKSPACE=%s\nLLAMA_CLI=%s\nPRIMARY=%s\nFALLBACK=%s\n' "$AI_HOME" "$STATE" "$WORKSPACE" "$LLAMA_CLI" "$PRIMARY" "$FALLBACK";;
    hash) shift; hash_text "$*"; printf '\n';;
    ledger) tail -n "${2:-10}" "$LEDGER" 2>/dev/null || true;;
    index) index_workspace;;
    file) shift; file_cmd "$@";;
    chat|repl) chat;;
    test) resolve_model || die "no model"; infer 'Reply with exactly: OK' "$MODEL_PATH"; printf '\n';;
    run) shift; local p="${*:-}"; [[ -n "$p" ]] || p=$(cat); run_engine "$p";;
    *) run_engine "$*";;
  esac
}
main "$@"

