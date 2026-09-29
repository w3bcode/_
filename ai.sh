#!/usr/bin/env bash
# =============================================================================
# GENESIS/HX unified local controller v251.0.0
#
# Goals:
#   - one CLI / one state tree / one local llama.cpp adapter
#   - scan + rehash + chunk + recall arbitrary workspace trees
#   - eight logical 2PI/8 channels with bounded physical concurrency
#   - SHA256 integrity lineage; MD5 only as legacy attribution metadata
#   - modulo-7 markers, entropy, lexical/LSA-surrogate signatures, channel geometry
#   - shebang / extension classification
#   - review + validated atomic AI modernization (no arbitrary AI command execution)
#   - JSON memory index + JSONL event ledger
#
# Default design is conservative for low-RAM ARM devices: 8 logical lanes,
# physical concurrency auto-capped from available memory and AI_CONCURRENCY.
# =============================================================================
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

AI_VERSION='251.0.0'
AI_HOME="${AI_HOME:-${HOME:-/home/loop}/.ai}"
STATE="${AI_STATE_DIR:-$AI_HOME/state}"
DB="${AI_DB:-$STATE/memory.json}"
INDEX="$STATE/file_index.json"
LEDGER="$STATE/ledger.jsonl"
OBJECTS="$STATE/objects"
RUN="$STATE/run"
SESS="$STATE/sessions"
LOG="$STATE/logs"
WORKSPACE="${AI_WORKSPACE:-${HOME:-/home/loop}/_}"
REFERENCE_FILE="${AI_REFERENCE_FILE:-${HOME:-/home/loop}/contagential.txt}"
MODEL_DIR="${AI_MODEL_DIR:-$AI_HOME/models}"
PRIMARY="${AI_MODEL_PATH:-$MODEL_DIR/qwen2.5-coder-3b-instruct-q4_k_m.gguf}"
FALLBACK="${AI_FALLBACK_PATH:-$MODEL_DIR/qwen2.5-1.5b-instruct-q4_k_m.gguf}"
LLAMA_CLI="${LLAMA_CLI:-${HOME:-/home/loop}/.local/bin/llama}"

CTX="${AI_CONTEXT:-2048}"
BATCH="${AI_BATCH:-128}"
UBATCH="${AI_UBATCH:-64}"
PREDICT="${AI_PREDICT:-384}"
THREADS="${AI_THREADS:-4}"
TIMEOUT="${AI_TIMEOUT:-600}"
TEMP="${AI_TEMPERATURE:-0.65}"
TOPK="${AI_TOP_K:-40}"
TOPP="${AI_TOP_P:-0.95}"
REPEAT="${AI_REPEAT_PENALTY:-1.10}"
SEED="${AI_SEED:-0}"
VIEWS="${AI_VIEWS:-8}"
DEPTH="${AI_DEPTH:-1}"
SYNTH="${AI_SYNTHESIS:-true}"
RECURSIVE="${AI_RECURSIVE:-1}"
MAX_TOKENS="${AI_MAX_TOKENS:-512}"
AI_CONCURRENCY="${AI_CONCURRENCY:-auto}"
AI_MEM_RESERVE_MB="${AI_MEM_RESERVE_MB:-1800}"
AI_WORKER_TIMEOUT="${AI_WORKER_TIMEOUT:-600}"
AI_CHUNK_BYTES="${AI_CHUNK_BYTES:-4096}"
AI_RECALL_TOP="${AI_RECALL_TOP:-8}"
AI_MAX_FILE_BYTES="${AI_MAX_FILE_BYTES:-262144}"
AI_MAX_PROMPT_BYTES="${AI_MAX_PROMPT_BYTES:-120000}"
AI_AUTO_REVIEW="${AI_AUTO_REVIEW:-1}"
AI_AUTO_REINDEX="${AI_AUTO_REINDEX:-1}"
AI_EXCLUDE="${AI_EXCLUDE:-.git .ai .cache node_modules target dist build __pycache__}" 
PI='3.141592653589793238462643383279502884'

NAMES=(analytical architectural critical creative implementation adversarial systems synthesis)
DESCS=(
  'strict/root alignment and assumptions'
  'architecture/dependency projection'
  'critical/failure and contradiction projection'
  'creative/alternative formulation projection'
  'implementation/code-operation projection'
  'adversarial/security/boundary projection'
  'systems/lifecycle/resource projection'
  'synthesis/reconciliation projection'
)

# =============================================================================
# OPTIONAL REALTIME EXTERNAL STATE
# =============================================================================

AI_REALTIME="${AI_REALTIME:-1}"
AI_REALTIME_HOST="${AI_REALTIME_HOST:-https://api.coingecko.com}"
AI_REALTIME_ASSET="${AI_REALTIME_ASSET:-bitcoin}"
AI_REALTIME_CURRENCY="${AI_REALTIME_CURRENCY:-usd}"
AI_REALTIME_TIMEOUT="${AI_REALTIME_TIMEOUT:-12}"

REALTIME_DIR="$STATE/realtime"
REALTIME_LAST="$REALTIME_DIR/latest.json"
REALTIME_LEDGER="$REALTIME_DIR/ledger.jsonl"

mkdir -p "$REALTIME_DIR"

# further back-to-topic...



mkdir -p "$STATE" "$OBJECTS" "$RUN" "$SESS" "$LOG" "$MODEL_DIR"
[[ -f "$DB" ]] || printf '{"version":"%s","genesis":"2244-1","last":{},"records":[],"files":{},"chunks":{},"reviews":{},"stats":{}}
' "$AI_VERSION" >"$DB"
[[ -f "$INDEX" ]] || printf '{"version":1,"root":"%s","generated":0,"files":[]}
' "$WORKSPACE" >"$INDEX"

if [[ -t 1 ]]; then C=$'\033[36m'; Y=$'\033[33m'; G=$'\033[32m'; R=$'\033[0m'; else C='';Y='';G='';R='';fi
say(){ printf '%s[HX]%s %s\n' "$C" "$R" "$*"; }
ok(){ printf '%s[OK]%s %s\n' "$G" "$R" "$*"; }
warn(){ printf '%s[WARN]%s %s\n' "$Y" "$R" "$*" >&2; }
die(){ printf '[ERROR] %s\n' "$*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }
now(){ date +%s; }
iso(){ date -u '+%Y-%m-%dT%H:%M:%SZ'; }
json_quote(){ jq -Rn --arg x "${1-}" '$x'; }
sha256_text(){ printf '%s' "${1-}" | sha256sum | awk '{print $1}'; }
sha256_file(){ sha256sum -- "$1" | awk '{print $1}'; }
sha512_text(){ printf '%s' "${1-}" | sha512sum | awk '{print $1}'; }
md5_text(){ printf '%s' "${1-}" | md5sum | awk '{print $1}'; }
bytes_file(){ wc -c <"$1" | tr -d ' '; }

require(){ for x in "$@"; do have "$x" || die "missing dependency: $x"; done; }

is_gguf(){ [[ -s "$1" && "$(head -c4 "$1" 2>/dev/null || true)" == GGUF ]]; }
resolve_model(){
  MODEL_PATH=''; MODEL_TIER='none'
  if [[ -f "$PRIMARY" ]] && is_gguf "$PRIMARY"; then
    MODEL_PATH="$PRIMARY"; MODEL_TIER='primary'
  elif [[ -f "$FALLBACK" ]] && is_gguf "$FALLBACK"; then
    MODEL_PATH="$FALLBACK"; MODEL_TIER='fallback'
  else
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Deterministic derived metrics. These are indexing features, not claims about
# physical entropy, intelligence, causality, or truth.
# -----------------------------------------------------------------------------
shannon_entropy(){
  local s="${1-}"
  [[ -n "$s" ]] || { printf '0.000000000000\n'; return; }
  LC_ALL=C printf '%s' "$s" | fold -w1 | sort | uniq -c |
    awk -v n="$(LC_ALL=C printf '%s' "$s" | wc -c)" 'BEGIN{h=0}{p=$1/n;if(p>0)h-=p*log(p)/log(2)}END{printf "%.12f\n",h+0}'
}
hex01(){
  local h="${1:0:8}"
  printf '%s\n' "$h" | awk 'BEGIN{v=0}{for(i=1;i<=length($0);i++){c=tolower(substr($0,i,1));p=index("0123456789abcdef",c)-1;v=v*16+p}}END{printf "%.12f\n",v/4294967295}'
}
channel_for(){
  local h
  h="$(sha256_text "${1-}")"
  printf '%d\n' "$((16#${h:0:8} % 8))"
}
channel_desc(){ printf '%s\n' "${DESCS[${1:-0}]}"; }
channel_geom(){
  local e="${1:-0}" c="${2:-0}" theta x y
  theta="$(awk -v p="$PI" -v c="$c" 'BEGIN{printf "%.12f",(2*p/8)*c}')"
  x="$(awk -v e="$e" -v t="$theta" 'BEGIN{printf "%.12f",e*cos(t)}')"
  y="$(awk -v e="$e" -v t="$theta" 'BEGIN{printf "%.12f",e*sin(t)}')"
  printf '%s\t%s\t%s\n' "$theta" "$x" "$y"
}
octal_tag(){ printf '%s\n' "$(( ${1:-0} & 7 ))" | awk '{printf "%02o",$1}'; }
rgba_from_hash(){
  local h="${1:-00000000}"
  printf '#%s\n' "${h:0:8}"
}
lex_signature(){
  local t="${1-}"
  printf '%s' "$t" | tr '\r\n\t' '   ' | tr '[:upper:]' '[:lower:]' |
    sed 's/[^[:alnum:]_+.-]/ /g' | awk '{for(i=1;i<=NF;i++) c[$i]++}END{for(k in c) print k,c[k]}' |
    sort -k2,2nr -k1,1 | head -n 24 | sha256sum | awk '{print $1}'
}
signal_from_score(){
  local score="${1:-0}"
  awk -v s="$score" 'BEGIN{if(s>=0.67)print 1;else if(s<=0.33)print -1;else print 0}'
}

# -----------------------------------------------------------------------------
# Locking + JSON mutation.
# -----------------------------------------------------------------------------
with_lock(){
  local rc=0
  if have flock; then
    exec 9>"$DB.lock"
    flock -x 9
    "$@" || rc=$?
    flock -u 9 || true
    exec 9>&-
  else
    local n=0
    while ! mkdir "$DB.lock.d" 2>/dev/null; do
      n=$((n+1)); ((n<200)) || return 75; sleep .02
    done
    "$@" || rc=$?
    rmdir "$DB.lock.d" 2>/dev/null || true
  fi
  return "$rc"
}

persist_event(){
  local type="${1-}" payload="${2-}" ts root parent event origin integrity rec
  ts="$(now)"
  parent="$(jq -r '.last.origin // "GENESIS"' "$DB" 2>/dev/null || echo GENESIS)"
  root="$(sha256_text "$((ts%7)):$type:$payload")"
  event="$(sha256_text "$ts:$root:$parent:$payload")"
  origin="$(md5_text "$parent:$event:$root")"
  integrity="$(sha512_text "$ts:$root:$event:$origin:$payload")"
  rec="$(jq -cn --argjson ts "$ts" --arg iso "$(iso)" --arg type "$type" --arg root "$root" --arg event "$event" --arg origin "$origin" --arg parent "$parent" --arg integrity "$integrity" --arg payload "$payload" '{timestamp:$ts,iso:$iso,type:$type,genesis:$root,event:$event,origin:$origin,parent:$parent,sha512:$integrity,payload:$payload}')"
  with_lock jq --argjson rec "$rec" --argjson ts "$ts" --arg root "$root" --arg event "$event" --arg origin "$origin" --arg integrity "$integrity" '.records += [$rec] | .last={timestamp:$ts,genesis:$root,event:$event,origin:$origin,sha512:$integrity}' "$DB" >"$RUN/db.$$" && mv -f "$RUN/db.$$" "$DB"
  printf '%s\n' "$rec" >> "$LEDGER"
  printf '%s\n' "$root"
}

# -----------------------------------------------------------------------------
# Path policy. Default scan root is /home/loop/_; recursive operations stay under
# that root unless explicitly overridden by AI_ALLOW_ABSOLUTE=1.
# -----------------------------------------------------------------------------
canon_path(){
  local p="$1" root="$2" out
  if [[ "$p" != /* ]]; then p="$root/$p"; fi
  out="$(realpath -m -- "$p")"
  printf '%s\n' "$out"
}
assert_under_root(){
  local path root
  path="$(canon_path "$1" "$WORKSPACE")"
  root="$(canon_path "$WORKSPACE" "$WORKSPACE")"
  if [[ "${AI_ALLOW_ABSOLUTE:-0}" == 1 ]]; then printf '%s\n' "$path"; return 0; fi
  case "$path" in
    "$root"|"$root"/*) printf '%s\n' "$path";;
    *) die "path outside workspace: $path (set AI_ALLOW_ABSOLUTE=1 only deliberately)";;
  esac
}
excluded_path(){
  local f="$1" base item
  for item in $AI_EXCLUDE; do
    while [[ "$f" == *"/$item/"* || "$f" == */"$item" ]]; do return 0; done
  done
  return 1
}
file_ext(){ local b="${1##*/}"; [[ "$b" == *.* && "$b" != .* ]] && printf '%s\n' "${b##*.}" || printf '%s\n' ''; }
shebang_of(){
  local f="$1" line=''
  IFS= read -r line <"$f" 2>/dev/null || true
  [[ "$line" == '#!'* ]] && printf '%s\n' "$line" || printf '%s\n' ''
}
language_of(){
  local ext="$1" sb="$2"
  case "$ext" in
    sh|bash|zsh|ksh) echo bash-like;; js|mjs|cjs) echo javascript;; ts|tsx) echo typescript;; py) echo python;; rb) echo ruby;; rs) echo rust;; go) echo go;; c|h) echo c;; cc|cpp|cxx|hpp) echo cpp;; java|kt|kts) echo jvm;; html|htm) echo html;; css) echo css;; json|jsonl) echo json;; md|markdown) echo markdown;; xml) echo xml;; yaml|yml) echo yaml;; sql) echo sql;; *) [[ -n "$sb" ]] && printf 'shebang:%s\n' "$sb" || echo text;; esac
}

# -----------------------------------------------------------------------------
# Scan + rehash + file index.
# -----------------------------------------------------------------------------
scan_workspace(){
  local root="${1:-$WORKSPACE}" tmp f rel bytes sha md5 ts ext sb lang ent lex changed=0 total=0 first=true
  root="$(canon_path "$root" "$WORKSPACE")"
  [[ -d "$root" ]] || die "scan root not found: $root"
  ts="$(now)"; tmp="$RUN/index.$$.json"
  printf '{"version":2,"root":%s,"generated":%s,"files":[' "$(json_quote "$root")" "$ts" >"$tmp"
  while IFS= read -r -d '' f; do
    excluded_path "$f" && continue
    ((total+=1))
    rel="${f#"$root"/}"
    bytes="$(bytes_file "$f")"
    if ((bytes>AI_MAX_FILE_BYTES)); then
      sha="$(sha256_file "$f")"; md5="$(md5sum -- "$f" | awk '{print $1}')"; ext="$(file_ext "$f")"; sb=''; lang="$(language_of "$ext" "$sb")"; ent='-1'; lex='-1'
    else
      sha="$(sha256_file "$f")"; md5="$(md5sum -- "$f" | awk '{print $1}')"; ext="$(file_ext "$f")"; sb="$(shebang_of "$f")"; lang="$(language_of "$ext" "$sb")"; ent="$(shannon_entropy "$(cat "$f")")"; lex="$(lex_signature "$(cat "$f")")"
    fi
    changed="$(jq -r --arg p "$rel" --arg s "$sha" '((.files[$p].sha256 // "") != $s)' "$INDEX" 2>/dev/null || echo true)"
    [[ "$first" == true ]] || printf ',' >>"$tmp"; first=false
    printf '%s' "$(jq -cn --arg path "$rel" --argjson bytes "$bytes" --arg sha256 "$sha" --arg md5 "$md5" --arg ext "$ext" --arg shebang "$sb" --arg language "$lang" --arg entropy "$ent" --arg lex "$lex" --argjson ts "$ts" '{path:$path,bytes:$bytes,sha256:$sha256,md5:$md5,extension:$ext,shebang:$shebang,language:$language,entropy:(if $entropy=="-1" then null else ($entropy|tonumber) end),lsa_surrogate:(if $lex=="-1" then null else $lex end),updated:$ts}')" >>"$tmp"
    if [[ "$changed" == true ]]; then
      persist_event file_seen "path=$rel sha256=$sha ext=$ext language=$lang" >/dev/null
    fi
  done < <(find "$root" -type f -print0 2>/dev/null)
  printf ']}\n' >>"$tmp"
  jq empty "$tmp" || { rm -f "$tmp"; die 'file index JSON validation failed'; }

  # Convert array -> path keyed object for stable lookup, and store compact index.
  jq '{version,root,generated,files:(reduce .files[] as $f ({}; .[$f.path]=$f))}' "$tmp" >"$INDEX.tmp"
  mv -f "$INDEX.tmp" "$INDEX"; rm -f "$tmp"
  # Merge scan metadata into memory database without retaining entire file contents.
  jq --argjson ts "$ts" --slurpfile idx "$INDEX" '.files=$idx[0].files | .stats.files_scanned=([.files|to_entries[]]|length) | .stats.last_scan=$ts' "$DB" >"$RUN/db.$$" && mv -f "$RUN/db.$$" "$DB"
  say "indexed $root: $total files -> $INDEX"
}

rehash_diff(){
  local oldsha newsha p changes=0 missing=0
  [[ -s "$INDEX" ]] || { scan_workspace "$WORKSPACE"; return; }
  while IFS=$'\t' read -r p oldsha; do
    [[ -n "$p" ]] || continue
    if [[ ! -f "$WORKSPACE/$p" ]]; then
      printf 'DELETED\t%s\t%s\n' "$p" "$oldsha"; ((missing+=1)); continue
    fi
    newsha="$(sha256_file "$WORKSPACE/$p")"
    if [[ "$oldsha" != "$newsha" ]]; then
      printf 'CHANGED\t%s\t%s\t%s\n' "$p" "$oldsha" "$newsha"; ((changes+=1))
    fi
  done < <(jq -r '(.files // {}) | to_entries[] | [.key,.value.sha256] | @tsv' "$INDEX")
  printf 'SUMMARY\tchanged=%s\tdeleted=%s\n' "$changes" "$missing"
}

# -----------------------------------------------------------------------------
# Chunked memory records + recall.
# -----------------------------------------------------------------------------
normalize_text(){ printf '%s' "${1-}" | tr '\r\n\t' '   ' | awk '{$1=$1;print}'; }
chunk_file(){
  local f="$1" outdir h i cpath bytes root c start=0 end ext sb lang ent lsa payload
  f="$(canon_path "$f" "$WORKSPACE")"
  [[ -f "$f" ]] || die "not found: $f"
  bytes="$(bytes_file "$f")"; h="$(sha256_file "$f")"; outdir="$OBJECTS/chunks/$h"; mkdir -p "$outdir"
  if find "$outdir" -type f -name '*.txt' -print -quit 2>/dev/null | grep -q .; then return 0; fi
  root="$(sha256_text "$(( $(now) % 7 )):$h:$bytes")"
  rm -f -- "$outdir"/*.txt 2>/dev/null || true
  awk -v max="$AI_CHUNK_BYTES" -v dir="$outdir" '
    BEGIN{buf="";i=0}
    {
      line=$0"\n";
      if(buf!="" && length(buf)+length(line)>max){
        path=dir"/"i".txt"; printf "%s",buf > path; close(path); i++; buf=""
      }
      buf=buf line
    }
    END{if(buf!=""){path=dir"/"i".txt";printf "%s",buf > path;close(path)}}
  ' "$f"
  ext="$(file_ext "$f")"; sb="$(shebang_of "$f")"; lang="$(language_of "$ext" "$sb")"
  for cpath in "$outdir"/*.txt; do
    [[ -f "$cpath" ]] || continue
    i="${cpath##*/}"; i="${i%.txt}"
    c="$(sha256_file "$cpath")"; end="$((start+$(bytes_file "$cpath")))"
    payload="$(cat "$cpath")"; ent="$(shannon_entropy "$payload")"; lsa="$(lex_signature "$payload")"
    persist_event chunk "file=$f chunk=$i sha256=$c channel=$((16#${c:0:8}%8))" >/dev/null
    jq --arg h "$c" --arg file "$f" --argjson chunk "$i" --argjson channel "$((16#${c:0:8}%8))" --arg root "$root" --arg start "$start" --arg end "$end" --arg lang "$lang" --arg ext "$ext" --argjson ts "$(now)" --arg payload "$payload" --arg entropy "$ent" --arg lsa "$lsa" --arg octal "$(octal_tag "$((16#${c:0:8}%8))")" --arg rgba "$(rgba_from_hash "$c")" '.chunks[$h]={file:$file,chunk:$chunk,channel:$channel,genesis:$root,start:($start|tonumber),end:($end|tonumber),extension:$ext,language:$lang,entropy:($entropy|tonumber),lsa_surrogate:$lsa,octal:$octal,rgba:$rgba,timestamp:$ts,payload:$payload}' "$DB" >"$RUN/db.$$" && mv -f "$RUN/db.$$" "$DB"
    start="$end"
  done
  ok "chunked $f -> $outdir"
}

remember_text(){
  local text="${1-}" source="${2:-prompt}" ts root h ent ch desc sha512
  [[ -n "$text" ]] || die 'empty memory text'
  ts="$(now)"; h="$(sha256_text "$text")"; root="$(sha256_text "$((ts%7)):$source:$h")"; ent="$(shannon_entropy "$text")"; ch="$(channel_for "$root:$text")"; desc="$(channel_desc "$ch")"; sha512="$(sha512_text "$ts:$root:$h:$text")"
  if jq -e --arg h "$h" 'any((.records // [])[]?; .hash == $h)' "$DB" >/dev/null 2>&1; then printf '%s\n' "$h"; return 0; fi
  printf '%s\n' "$text" >"$OBJECTS/$h.txt"
  jq --arg h "$h" --arg source "$source" --arg root "$root" --argjson ts "$ts" --arg iso "$(iso)" --argjson channel "$ch" --arg desc "$desc" --arg entropy "$ent" --arg sha512 "$sha512" --arg payload "$text" '.records += [{hash:$h,source:$source,genesis:$root,timestamp:$ts,iso:$iso,channel:$channel,descriptor:$desc,entropy:($entropy|tonumber),sha512:$sha512,payload:$payload}] | .last={timestamp:$ts,genesis:$root,origin:$h,sha512:$sha512}' "$DB" >"$RUN/db.$$" && mv -f "$RUN/db.$$" "$DB"
  printf '%s\n' "$(jq -cn --arg hash "$h" --arg source "$source" --arg root "$root" --argjson channel "$ch" --arg entropy "$ent" '{hash:$hash,source:$source,genesis:$root,channel:$channel,entropy:($entropy|tonumber)}')" >>"$LEDGER"
  printf '%s\n' "$h"
}
recall(){
  local query="${1-}" top="${2:-$AI_RECALL_TOP}"
  [[ -n "$query" ]] || die 'usage: ai recall QUERY [N]'
  jq -r --arg q "$query" --argjson top "$top" '
    def words: (ascii_downcase|gsub("[^a-z0-9_+.-]";" ")|split(" ")|map(select(length>2))|unique);
    ($q|words) as $qw |
    [ ((.records // []) + ((.chunks // {}) | to_entries | map(.value)))[]
      | . as $r
      | ($r.payload // "") as $p
      | ($p|words) as $rw
      | ([ $qw[] | select(. as $w | ($rw|index($w))) ]|length) as $hits
      | {score:(if ($qw|length)>0 then ($hits/($qw|length)) else 0 end),hash:($r.hash // $r.genesis),source:($r.source // $r.file // $r.type // "record"),timestamp:($r.timestamp // 0),payload:$p}
    ]
    | sort_by(-.score,-.timestamp)
    | .[0:$top][]
    | @json
  ' "$DB"
}

# -----------------------------------------------------------------------------
# Reference corpus: the user-provided contagential.txt is context, not evidence.
# -----------------------------------------------------------------------------
reference_context(){
  local f="$REFERENCE_FILE" h bytes
  [[ -f "$f" ]] || { printf 'REFERENCE_STATUS=missing path=%s\n' "$f"; return 0; }
  h="$(sha256_file "$f")"; bytes="$(bytes_file "$f")"
  printf 'REFERENCE_STATUS=loaded\nREFERENCE_PATH=%s\nREFERENCE_SHA256=%s\nREFERENCE_BYTES=%s\nREFERENCE_ROLE=context-not-fact\n' "$f" "$h" "$bytes"
}
reference_ingest(){
  [[ -f "$REFERENCE_FILE" ]] || die "reference not found: $REFERENCE_FILE"
  local saved="$WORKSPACE/.hx-reference/contagential.txt"
  mkdir -p "$(dirname "$saved")"
  cp -p "$REFERENCE_FILE" "$saved"
  chunk_file "$saved"
  remember_text "$(cat "$REFERENCE_FILE")" "reference:contagential.txt" >/dev/null
  ok "reference indexed: $REFERENCE_FILE (copied into workspace metadata boundary)"
}

# -----------------------------------------------------------------------------
# Local llama.cpp adapter. Prefers physical GGUF path; detects `llama cli`.
# -----------------------------------------------------------------------------
declare -a BASE=() CMD=()
HELP_TEXT=''
detect_adapter(){
  [[ -x "$LLAMA_CLI" ]] || { warn "llama runtime missing: $LLAMA_CLI"; return 127; }
  local h
  h="$($LLAMA_CLI --help 2>&1 || true)"
  if grep -Eq '(^|[[:space:]])cli([[:space:]]|$)' <<<"$h"; then BASE=("$LLAMA_CLI" cli); else BASE=("$LLAMA_CLI"); fi
  HELP_TEXT="$(${BASE[@]} --help 2>&1 || true)"
}
supports(){ grep -Eq -- "(^|[[:space:]])$1([=[:space:]]|,|$)" <<<"$HELP_TEXT"; }
llama_infer(){
  local prompt="${1-}" model="${2:-$MODEL_PATH}" out='' rc=0 err="$RUN/llama.stderr"
  [[ -n "$model" && -f "$model" && -s "$model" ]] || return 2
  is_gguf "$model" || return 2
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
  supports '--seed' && CMD+=(--seed "$SEED")
  supports '--single-turn' && CMD+=(--single-turn)
  if supports '--prompt'; then CMD+=(--prompt "$prompt")
  elif supports '-p'; then CMD+=(-p "$prompt")
  else
    if have timeout; then out="$(printf '%s' "$prompt" | timeout "$TIMEOUT" "${CMD[@]}" 2>"$err")" || rc=$?; else out="$(printf '%s' "$prompt" | "${CMD[@]}" 2>"$err")" || rc=$?; fi
    ((rc==0)) || { warn "llama rc=$rc: $(tail -n6 "$err" 2>/dev/null | tr '\n' ' ')"; persist_event inference_error "rc=$rc model=$model" >/dev/null; return "$rc"; }
    printf '%s' "$out"; return 0
  fi
  if have timeout; then out="$(timeout "$TIMEOUT" "${CMD[@]}" 2>"$err")" || rc=$?; else out="$("${CMD[@]}" 2>"$err")" || rc=$?; fi
  ((rc==0)) || { warn "llama rc=$rc: $(tail -n6 "$err" 2>/dev/null | tr '\n' ' ')"; persist_event inference_error "rc=$rc model=$model" >/dev/null; return "$rc"; }
  printf '%s' "$out"
}

# -----------------------------------------------------------------------------
# Bounded physical concurrency. Eight logical lanes are always represented;
# actual processes are constrained to protect RAM/CPU on mobile systems.
# -----------------------------------------------------------------------------
mem_available_mb(){ awk '/MemAvailable:/{printf "%.0f\n",$2/1024}' /proc/meminfo 2>/dev/null || echo 0; }
calc_concurrency(){
  local mem="$(mem_available_mb)" bymem=1 requested
  requested="$VIEWS"
  [[ "$AI_CONCURRENCY" =~ ^[0-9]+$ ]] && requested="$AI_CONCURRENCY"
  if ((mem>AI_MEM_RESERVE_MB)); then
    bymem=$(( (mem-AI_MEM_RESERVE_MB) / 1400 ))
    ((bymem<1)) && bymem=1
    ((bymem>VIEWS)) && bymem="$VIEWS"
  fi
  ((requested>bymem)) && requested="$bymem"
  ((requested<1)) && requested=1
  printf '%s\n' "$requested"
}

review_file(){
  local f="$1" instruction="${2:-review for correctness, maintainability, security, compatibility, and concrete improvements}" model prompt out h
  f="$(assert_under_root "$f")"; [[ -f "$f" ]] || die "not found: $f"
  (( $(bytes_file "$f") <= AI_MAX_FILE_BYTES )) || die "file exceeds AI_MAX_FILE_BYTES: $f"
  resolve_model || die 'no verified GGUF model'
  prompt=$(cat <<EOF
ROLE: local source-code reviewer.
REFERENCE: contagential.txt is user-provided conceptual context only; do not treat it as factual evidence.
FILE: $f
EXTENSION: $(file_ext "$f")
SHEBANG: $(shebang_of "$f")
LANGUAGE: $(language_of "$(file_ext "$f")" "$(shebang_of "$f")")
GENESIS-FILE-SHA256: $(sha256_file "$f")
TASK: $instruction
RULES: separate observed facts from inference; identify exact risks; propose testable changes; do not claim to have executed tools.
SOURCE:
$(cat "$f")
EOF
)
  out="$(llama_infer "$prompt" "$MODEL_PATH")" || die 'review inference failed'
  h="$(sha256_text "$out")"; printf '%s\n' "$out" >"$OBJECTS/review.$h.txt"
  jq --arg f "$f" --arg hash "$h" --arg sha256 "$(sha256_file "$f")" --arg review "$out" --argjson ts "$(now)" '.reviews[$f]={timestamp:$ts,file_sha256:$sha256,review_hash:$hash,review:$review}' "$DB" >"$RUN/db.$$" && mv -f "$RUN/db.$$" "$DB"
  persist_event review "file=$f source_sha256=$(sha256_file "$f") review_sha256=$h" >/dev/null
  printf '%s\n' "$out"
}
validate_file(){
  local f="$1" ext="${1##*.}" js css op cl
  [[ -f "$f" ]] || { echo "missing: $f"; return 1; }
  case "$ext" in
    sh|bash|zsh|ksh) bash -n "$f";;
    js|mjs|cjs) have node || return 2; node --check "$f";;
    json) jq empty "$f";;
    html|htm) grep -qi '<!doctype html' "$f" || return 1; grep -qi '<html\b' "$f" || return 1; grep -qi '</html>' "$f" || return 1;;
    css) op="$(tr -cd '{' <"$f" | wc -c)"; cl="$(tr -cd '}' <"$f" | wc -c)"; [[ "$op" == "$cl" ]];;
    *) test -s "$f";;
  esac
}
clean_model_output(){
  # Remove a single markdown fence wrapper if the model ignored the source-only rule.
  sed -e '1{/^[[:space:]]*```[[:alnum:]_-]*[[:space:]]*$/d;}' -e '${/^[[:space:]]*```[[:space:]]*$/d;}'
}
modernize_file(){
  local f="$1" instruction="${2:-modernize conservatively while preserving externally observable behavior}" tmp candidate backup h before after
  f="$(assert_under_root "$f")"; [[ -f "$f" ]] || die "not found: $f"
  resolve_model || die 'no verified GGUF model'
  before="$(sha256_file "$f")"
  prompt=$(cat <<EOF
ROLE: conservative source modernization agent.
REFERENCE: contagential.txt is conceptual user context, not factual evidence.
FILE: $f
LANGUAGE: $(language_of "$(file_ext "$f")" "$(shebang_of "$f")")
INSTRUCTION: $instruction
REQUIRED: preserve behavior unless the instruction explicitly asks otherwise; preserve shebang; output ONLY complete source; no markdown fences; no commentary; do not add network calls, telemetry, destructive commands, or arbitrary shell execution.
VALIDATION TARGET: $(file_ext "$f")
SOURCE:
$(cat "$f")
EOF
)
  tmp="$RUN/repair.$$.tmp"
  llama_infer "$prompt" "$MODEL_PATH" | clean_model_output >"$tmp" || { rm -f "$tmp"; die 'modernize inference failed'; }
  validate_file "$tmp" || { rm -f "$tmp"; die 'AI output failed local syntax/static validation; original left untouched'; }
  backup="$f.bak.$(now)"; cp -p "$f" "$backup"; mv -f "$tmp" "$f"
  after="$(sha256_file "$f")"; h="$(sha256_text "$before:$after:$instruction")"
  jq --arg f "$f" --arg before "$before" --arg after "$after" --arg backup "$backup" --arg change "$h" --arg instruction "$instruction" --argjson ts "$(now)" '.reviews[$f].modernization={timestamp:$ts,before_sha256:$before,after_sha256:$after,backup:$backup,change_hash:$change,instruction:$instruction}' "$DB" >"$RUN/db.$$" && mv -f "$RUN/db.$$" "$DB"
  persist_event modernize "file=$f before=$before after=$after change=$h backup=$backup" >/dev/null
  ok "modernized $f; backup=$backup"
}

# -----------------------------------------------------------------------------
# Eight logical POVs with bounded concurrency and persisted per-lane artifacts.
# -----------------------------------------------------------------------------
run_views(){
  local prompt="$1" model="$2" dir count lane j pid running name angle pp refmeta
  dir="$RUN/views.$$.${RANDOM}"; mkdir -p "$dir"
  count="$(calc_concurrency)"
  refmeta="$(reference_context | tr '\n' ';')"
  say "logical_views=$VIEWS physical_concurrency=$count threads=$THREADS memory=$(mem_available_mb)MB"
  for ((lane=0; lane<VIEWS && lane<8; lane++)); do
    name="${NAMES[$lane]}"; angle="$(awk -v p="$PI" -v i="$lane" 'BEGIN{printf "%.12f",(2*p/8)*i}')"
    pp=$(cat <<EOF
You are lane $lane/8: $name.
CHANNEL: $name
ANGLE: $angle radians-equivalent 2PI/8 placement
ROLE: ${DESCS[$lane]}
TASK:
$prompt
REFERENCE METADATA:
$refmeta
INDEX RULES: hash lineage is evidence of data identity only; entropy/geometry/LSA-surrogate are deterministic indexing features, not measures of truth or intelligence.
RETURN FORMAT:
STATE_SIGNAL=<1|0|-1>
OBSERVED=<concise observed facts>
INFERENCE=<clearly labeled inference>
ACTIONS=<testable next actions>
RISKS=<key risks/unknowns>
Do not claim to have executed tools.
EOF
)
    (
      out="$(llama_infer "$pp" "$model")" || exit 1
      printf '%s' "$out" >"$dir/$lane.txt"
      printf '%s\n' "$lane" >"$dir/$lane.ok"
    ) &
    while (( $(jobs -pr | wc -l) >= count )); do wait -n || true; done
  done
  wait || true
  for ((lane=0; lane<VIEWS && lane<8; lane++)); do
    name="${NAMES[$lane]}"; angle="$(awk -v p="$PI" -v i="$lane" 'BEGIN{printf "%.12f",(2*p/8)*i}')"
    if [[ -s "$dir/$lane.txt" ]]; then
      local_out="$(cat "$dir/$lane.txt")"
      h="$(sha256_text "$local_out")"
      printf '%s\n' "$local_out" >"$OBJECTS/pov.$h.txt"
      jq --arg hash "$h" --arg name "$name" --argjson lane "$lane" --arg angle "$angle" --arg desc "${DESCS[$lane]}" --arg payload "$local_out" --argjson ts "$(now)" '.records += [{type:"pov",lane:$lane,name:$name,angle:$angle,descriptor:$desc,hash:$hash,timestamp:$ts,payload:$payload}]' "$DB" >"$RUN/db.$$" && mv -f "$RUN/db.$$" "$DB"
      persist_event pov "lane=$lane name=$name angle=$angle sha256=$h" >/dev/null
      printf '%s\t%s\t%s\n' "$lane" "$name" "$h"
    else
      warn "lane $lane $name failed"
      persist_event pov_error "lane=$lane name=$name" >/dev/null
    fi
  done
  rm -rf "$dir"
}

synthesize_views(){
  local prompt="$1" bundle='' line lane name hash text_out h
  resolve_model || die 'no verified GGUF model'
  for lane in 0 1 2 3 4 5 6 7; do
    name="${NAMES[$lane]}"
    hash="$(jq -r --arg n "$name" '(.records // []) | map(select(.type=="pov" and .name==$n)) | last.hash // empty' "$DB")"
    [[ -n "$hash" && -f "$OBJECTS/pov.$hash.txt" ]] || continue
    text_out="$(cat "$OBJECTS/pov.$hash.txt")"
    bundle+=$'\n\n'
    bundle+="LANE=$lane NAME=$name HASH=$hash\n$text_out"
  done
  [[ -n "$bundle" ]] || die 'no POV artifacts available for synthesis'
  if ((${#bundle}>AI_MAX_PROMPT_BYTES)); then bundle="${bundle:0:AI_MAX_PROMPT_BYTES}"$'\n[TRUNCATED_FOR_CONTEXT]'; fi
  local final_prompt
  final_prompt=$(cat <<EOF
ROLE: synthesis/reconciliation engine.
TASK:
$prompt

CANDIDATE POV ARTIFACTS:
$bundle

REQUIRED OUTPUT:
1. FACTS: only observations supported by supplied material.
2. INFERENCES: explicitly marked interpretations.
3. CHANGES: concrete implementation changes.
4. VALIDATION: commands/tests that can be run locally.
5. RISKS: unresolved or uncertain items.
6. MEMORY: compact reusable rules for future recall.
Do not claim any tool was executed unless the shell actually executed it.
Do not treat contagential.txt as verified factual evidence.
EOF
)
  local result
  result="$(llama_infer "$final_prompt" "$MODEL_PATH")" || die 'synthesis inference failed'
  h="$(sha256_text "$result")"
  printf '%s\n' "$result" >"$OBJECTS/final.$h.txt"
  persist_event synthesis "sha256=$h" >/dev/null
  printf '%s\n' "$result"
}

review_tree(){
  local root="${1:-$WORKSPACE}" limit="${2:-${AI_REVIEW_LIMIT:-24}}" f count=0
  root="$(canon_path "$root" "$WORKSPACE")"; [[ -d "$root" ]] || die "not found: $root"
  while IFS= read -r -d '' f; do
    excluded_path "$f" && continue
    [[ "$(bytes_file "$f")" -le "$AI_MAX_FILE_BYTES" ]] || continue
    case "$(file_ext "$f")" in
      sh|bash|zsh|ksh|js|mjs|cjs|ts|tsx|py|rb|rs|go|c|h|cc|cpp|cxx|hpp|java|kt|kts|html|htm|css|json|jsonl|xml|yaml|yml|sql|md|markdown) ;;
      *) continue;;
    esac
    review_file "$f" || warn "review failed: $f"
    ((count+=1))
    if [[ "$limit" =~ ^[0-9]+$ ]] && ((limit>0 && count>=limit)); then break; fi
  done < <(find "$root" -type f -print0 2>/dev/null)
  ok "reviewed=$count"
}

hydrate_tree(){
  local root="${1:-$WORKSPACE}" f n=0
  root="$(canon_path "$root" "$WORKSPACE")"
  while IFS= read -r -d '' f; do
    excluded_path "$f" && continue
    [[ "$(bytes_file "$f")" -le "$AI_MAX_FILE_BYTES" ]] || continue
    chunk_file "$f" >/dev/null || warn "chunk failed: $f"
    ((n+=1))
  done < <(find "$root" -type f -print0 2>/dev/null)
  ok "content-hydrated=$n"
}

run_engine(){
  local input="${1-}" round=1 normalized genesis task ref recall_context views_output result final_hash
  [[ -n "$input" ]] || die 'empty prompt'
  require jq sha256sum md5sum awk find sed sort fold wc timeout
  resolve_model || die "no verified GGUF: $PRIMARY / $FALLBACK"
  normalized="$(normalize_text "$input")"
  genesis="$(sha256_text "$(now)|2244-1|$AI_VERSION|$normalized")"
  task="$(sha256_text "$genesis|$normalized")"

realtime_state() {
  local url raw ts sha1 sha256 bytes mod7

  [[ "$AI_REALTIME" == 1 ]] || {
    printf '{"enabled":false}\n'
    return 0
  }

  have curl || {
    warn "curl unavailable; realtime state skipped"
    return 0
  }

  ts="$(now)"

  url="${AI_REALTIME_HOST}/api/v3/simple/price?ids=${AI_REALTIME_ASSET}&vs_currencies=${AI_REALTIME_CURRENCY}&include_last_updated_at=true"

  raw="$(
    curl \
      --fail \
      --silent \
      --show-error \
      --location \
      --connect-timeout 5 \
      --max-time "$AI_REALTIME_TIMEOUT" \
      -H 'Accept: application/json' \
      "$url"
  )" || {
    warn "realtime provider unavailable"
    persist_event realtime_error "provider=coingecko asset=$AI_REALTIME_ASSET" >/dev/null || true
    return 0
  }

  [[ -n "$raw" ]] || {
    warn "realtime provider returned empty response"
    return 0
  }

  # Validate JSON before using it.
  jq empty <<<"$raw" >/dev/null 2>&1 || {
    warn "realtime response was not valid JSON"
    return 0
  }

  bytes="$(printf '%s' "$raw" | wc -c | tr -d ' ')"
  sha256="$(printf '%s' "$raw" | sha256sum | awk '{print $1}')"
  sha1="$(printf '%s' "$raw" | sha1sum | awk '{print $1}')"
  mod7="$((ts % 7))"

  jq -cn \
    --arg provider "coingecko" \
    --arg endpoint "$url" \
    --arg asset "$AI_REALTIME_ASSET" \
    --arg currency "$AI_REALTIME_CURRENCY" \
    --arg raw "$raw" \
    --arg sha256 "$sha256" \
    --arg sha1 "$sha1" \
    --argjson timestamp "$ts" \
    --argjson bytes "$bytes" \
    --argjson mod7 "$mod7" \
    '{
      type:"realtime_state",
      provider:$provider,
      endpoint:$endpoint,
      asset:$asset,
      currency:$currency,
      timestamp:$timestamp,
      bytes:$bytes,
      sha256:$sha256,
      sha1:$sha1,
      mod7:$mod7,
      raw:$raw
    }' >"$RUN/realtime.$$.json"

  mv -f "$RUN/realtime.$$.json" "$REALTIME_LAST"

  cp "$REALTIME_LAST" "$RUN/realtime.current.json"

  printf '%s\n' \
    "$(jq -c 'del(.raw)' "$REALTIME_LAST")" \
    >>"$REALTIME_LEDGER"

  persist_event \
    realtime \
    "provider=coingecko asset=$AI_REALTIME_ASSET sha256=$sha256 sha1=$sha1 mod7=$mod7" \
    >/dev/null || true

  cat "$REALTIME_LAST"
}

  persist_event genesis "genesis=$genesis task=$task" >/dev/null
  say "genesis=2244-1 hash=$genesis model=$MODEL_TIER views=$VIEWS depth=$DEPTH"

  if [[ "$AI_AUTO_REINDEX" == 1 ]]; then
    scan_workspace "$WORKSPACE"
    hydrate_tree "$WORKSPACE"
  fi
  if [[ -f "$REFERENCE_FILE" ]]; then
    # Register the reference once by content hash; repeated runs remain idempotent.
    reference_ingest >/dev/null || warn 'reference ingest failed'
  fi

  for ((round=1; round<=DEPTH; round++)); do
    say "round $round/$DEPTH task=$task"
    recall_context="$(recall "$normalized" "$AI_RECALL_TOP" || true)"
    if ((${#recall_context}>AI_MAX_PROMPT_BYTES)); then recall_context="${recall_context:0:AI_MAX_PROMPT_BYTES}"$'\n[RECALL_TRUNCATED]'; fi
    local round_prompt
    round_prompt=$(cat <<EOF
GENESIS: 2244-1
GENESIS_HASH: $genesis
TASK_HASH: $task
ROUND: $round/$DEPTH
REFERENCE: $(reference_context | tr '\n' ';')
RECALLED MEMORY:
$recall_context

ORIGINAL USER TASK:
$normalized

WORKFLOW CONTRACT:
- scan/index first;
- use hashes only for provenance/integrity;
- distinguish facts, inference, and hypotheses;
- never claim local file edits/tool execution unless performed by this controller;
- use bounded 2PI/8 logical lanes;
- persist reusable memory and validation results;
- prefer deterministic, testable transformations.
EOF
)
    run_views "$round_prompt" "$MODEL_PATH" >/dev/null || die 'view pipeline failed'
    if [[ "${SYNTH,,}" == true ]]; then
      result="$(synthesize_views "$round_prompt")"
    else
      result="$(jq -r '.records[]|select(.type=="pov")|.payload' "$DB" | tail -n1)"
    fi
    final_hash="$(sha256_text "$result")"
    remember_text "$result" "run:$task:round:$round" >/dev/null
    persist_event round "round=$round task=$task result=$final_hash" >/dev/null
    if ((round<DEPTH)); then
      task="$(sha256_text "$genesis|$task|$final_hash|round=$round")"
      normalized="Prior synthesis:\n$result\n\nContinue by resolving gaps and validating the implementation."
    fi
  done
  printf '%s\n' "$result"
}

# -----------------------------------------------------------------------------
# Diagnostics / state views / CLI.
# -----------------------------------------------------------------------------
status(){
  resolve_model >/dev/null 2>&1 || true
  jq -n \
    --arg version "$AI_VERSION" --arg root "$WORKSPACE" --arg state "$STATE" \
    --arg db "$DB" --arg index "$INDEX" --arg ledger "$LEDGER" \
    --arg llama "$LLAMA_CLI" --arg model "${MODEL_PATH:-unresolved}" --arg tier "${MODEL_TIER:-none}" \
    --argjson views "$VIEWS" --argjson depth "$DEPTH" --argjson threads "$THREADS" \
    --argjson concurrency "$(calc_concurrency)" --argjson mem "$(mem_available_mb)" \
    --arg reference "$REFERENCE_FILE" \
    '{version:$version,workspace:$root,state:$state,db:$db,index:$index,ledger:$ledger,llama:$llama,model:$model,tier:$tier,views:$views,depth:$depth,threads:$threads,physical_concurrency:$concurrency,mem_available_mb:$mem,reference:$reference}'
}
doctor(){
  local a=''; resolve_model && a="$MODEL_PATH" || a='none'
  printf 'GENESIS/HX %s\n' "$AI_VERSION"
  printf 'Bash: %s\n' "$BASH_VERSION"
  printf 'Workspace: %s\nState: %s\n' "$WORKSPACE" "$STATE"
  printf 'llama: %s\n' "$LLAMA_CLI"
  printf 'model: %s\n' "$a"
  printf 'memory: %s MB available\n' "$(mem_available_mb)"
  printf 'physical concurrency: %s\n' "$(calc_concurrency)"
  for x in jq sha256sum md5sum awk sed find fold timeout flock node; do have "$x" && printf '%s=OK\n' "$x" || printf '%s=missing/optional\n' "$x"; done
  if [[ -x "$LLAMA_CLI" ]]; then "$LLAMA_CLI" --version 2>&1 | head -n1 || true; fi
  [[ -s "$DB" ]] && jq empty "$DB" && echo 'memory.json=VALID' || echo 'memory.json=INVALID'
  [[ -s "$INDEX" ]] && jq empty "$INDEX" && echo 'file_index.json=VALID' || echo 'file_index.json=INVALID'
}
models(){
  resolve_model && printf '%s\t%s\n' "$MODEL_PATH" "$MODEL_TIER" || warn 'no valid local GGUF';
}
memory(){ jq -c '.last // {}' "$DB"; }
ledger(){ tail -n "${1:-20}" "$LEDGER" 2>/dev/null || true; }
index_cmd(){ scan_workspace "${1:-$WORKSPACE}"; }
rehash_cmd(){ rehash_diff; }
hash_cmd(){ local t="${*:-}"; [[ -n "$t" ]] || die 'usage: ai hash TEXT'; printf '%s\n' "$(sha256_text "$t")"; }
artifact_cmd(){ local f="$1"; f="$(assert_under_root "$f")"; [[ -f "$f" ]] || die "not found"; jq -cn --arg file "$f" --arg sha256 "$(sha256_file "$f")" --arg md5 "$(md5sum -- "$f"|awk '{print $1}')" --arg ext "$(file_ext "$f")" --arg shebang "$(shebang_of "$f")" --arg language "$(language_of "$(file_ext "$f")" "$(shebang_of "$f")")" --argjson bytes "$(bytes_file "$f")" --argjson timestamp "$(now)" '{file:$file,bytes:$bytes,sha256:$sha256,md5:$md5,extension:$ext,shebang:$shebang,language:$language,timestamp:$timestamp}' ; }

crud(){
  local op="${1:-}" p="${2:-}" data="${3:-}" target backup
  [[ -n "$op" && -n "$p" ]] || die 'usage: ai crud create|read|write|append|delete PATH [DATA]'
  target="$(assert_under_root "$p")"
  case "$op" in
    create) [[ ! -e "$target" ]] || die "already exists: $target"; mkdir -p "$(dirname "$target")"; printf '%s' "$data" >"$target";;
    read) [[ -f "$target" ]] || die "not found: $target"; cat "$target";;
    write) mkdir -p "$(dirname "$target")"; backup="$target.bak.$(now)"; [[ ! -f "$target" ]] || cp -p "$target" "$backup"; printf '%s' "$data" >"$RUN/write.$$"; mv -f "$RUN/write.$$" "$target";;
    append) mkdir -p "$(dirname "$target")"; printf '%s' "$data" >>"$target";;
    delete) [[ -f "$target" ]] || die "not found: $target"; backup="$target.bak.$(now)"; cp -p "$target" "$backup"; rm -f -- "$target";;
    *) die 'unknown CRUD operation';;
  esac
  persist_event crud "op=$op file=$target sha256=$(sha256_file "$target" 2>/dev/null || echo deleted)" >/dev/null
}

repl(){
  local p
  while printf 'hx> ' >&2 && IFS= read -r p; do
    case "$p" in
      /exit|/quit) break;;
      /help) usage;;
      /status) status;;
      /index) index_cmd;;
      /memory) memory;;
      '') continue;;
      *) run_engine "$p" || true;;
    esac
  done
}

usage(){ cat <<EOF
GENESIS/HX v$AI_VERSION — local llama.cpp file-indexed memory controller

Core:
  ai "PROMPT" | ai run "PROMPT"     scan -> chunk -> recall -> 2PI/8 -> synth -> memory
  ai views "PROMPT"                  bounded 8-lane analysis
  ai scan [ROOT]                     recursive file index + hashes + shebang/extension metadata
  ai hydrate [ROOT]                  chunk files into hash-addressed memory objects
  ai rehash                          detect changed/deleted files against file_index.json
  ai recall "QUERY" [N]              lexical recall from memory + chunks
  ai remember "TEXT" [SOURCE]       persist a memory record

Source review / changes:
  ai review FILE [INSTRUCTION]       AI review; no file modification
  ai review-tree [ROOT] [LIMIT]      bounded tree review
  ai modernize FILE [INSTRUCTION]    AI rewrite + validate + backup + atomic replace
  ai validate FILE                   static syntax/shape validation
  ai crud create|read|write|append|delete PATH [DATA]

Provenance / diagnostics:
  ai hash TEXT | artifact FILE | memory | ledger [N]
  ai reference | ai reference-ingest
  ai status | doctor | models | config | version | repl

Environment:
  AI_WORKSPACE=/home/loop/_
  AI_REFERENCE_FILE=/home/loop/contagential.txt
  AI_MODEL_PATH=~/.ai/models/qwen2.5-coder-3b-instruct-q4_k_m.gguf
  AI_FALLBACK_PATH=~/.ai/models/qwen2.5-1.5b-instruct-q4_k_m.gguf
  LLAMA_CLI=~/.local/bin/llama
  AI_VIEWS=8 AI_DEPTH=1 AI_SYNTHESIS=true AI_RECURSIVE=1
  AI_CONCURRENCY=auto AI_MEM_RESERVE_MB=1800 AI_THREADS=4
  AI_CHUNK_BYTES=4096 AI_RECALL_TOP=8 AI_MAX_FILE_BYTES=262144
  AI_REVIEW_LIMIT=24 AI_AUTO_REINDEX=1 AI_ALLOW_ABSOLUTE=0

Notes:
  SHA256 = primary identity/integrity key.
  MD5    = legacy attribution/compatibility field only, never sole integrity proof.
  entropy, 2PI/8 geometry, octal tags, RGBA tags and LSA-surrogate signatures
  are deterministic indexing features; they are not measurements of truth,
  intelligence, causality, or physical entropy.
EOF
}

main(){
  local cmd="${1:-run}"; shift || true
  case "$cmd" in
    help|-h|--help) usage;;
    version|-V|--version) echo "$AI_VERSION";;
    status) status;;
    doctor) doctor;;
    models|model) models;;
    config) printf 'AI_VERSION=%s\nAI_HOME=%s\nSTATE=%s\nDB=%s\nINDEX=%s\nLEDGER=%s\nWORKSPACE=%s\nREFERENCE_FILE=%s\nLLAMA_CLI=%s\nPRIMARY=%s\nFALLBACK=%s\nVIEWS=%s\nDEPTH=%s\nTHREADS=%s\nAI_CONCURRENCY=%s\n' "$AI_VERSION" "$AI_HOME" "$STATE" "$DB" "$INDEX" "$LEDGER" "$WORKSPACE" "$REFERENCE_FILE" "$LLAMA_CLI" "$PRIMARY" "$FALLBACK" "$VIEWS" "$DEPTH" "$THREADS" "$AI_CONCURRENCY";;
    hash) hash_cmd "$@";;
    scan|index) index_cmd "${1:-$WORKSPACE}";;
    hydrate) hydrate_tree "${1:-$WORKSPACE}";;
    rehash|diff) rehash_cmd;;
    recall) recall "${1:-}" "${2:-$AI_RECALL_TOP}";;
    remember) remember_text "${1:-}" "${2:-manual}";;
    reference) reference_context;;
    reference-ingest) reference_ingest;;
    memory) memory;;
    ledger) ledger "${1:-20}";;
    artifact) artifact_cmd "${1:-}";;
    views) resolve_model || die 'no model'; run_views "${*:-$(cat)}" "$MODEL_PATH";;
    run) [[ $# -gt 0 ]] && run_engine "$*" || run_engine "$(cat)";;
    review) review_file "${1:-}" "${*:2}";;
    review-tree) review_tree "${1:-$WORKSPACE}" "${2:-${AI_REVIEW_LIMIT:-24}}";;
    modernize|fix) modernize_file "${1:-}" "${*:2}";;
    validate) validate_file "${1:-}";;
    crud) crud "$@";;
    repl|chat) repl;;
    *) run_engine "$cmd ${*:-}";;
  esac
}

main "$@"

