#!/usr/bin/env bash
# =============================================================================
# ai-fusion.sh 3.0.0 — high-performance local AI fusion controller
# =============================================================================
# Unified llama.cpp CLI + Ollama + Gemini Interactions backend.
#
# Design:
#   prompt -> parser -> genesis root -> task hash -> 2PI/8 views -> scoring
#   -> consensus/synthesis -> validation -> content-addressed artifact ledger
#
# Backends:
#   auto    prefer llama CLI when available; otherwise Ollama
#   llama   local `llama cli` / GGUF runtime
#   ollama  local HTTP API at 127.0.0.1:11434
#   gemini  Google Gemini Interactions API / managed agents
#
# Safety:
#   - generated source is validated, never executed automatically
#   - model tool calls are inspected only; shell execution is explicit
#   - MD5 is a compact lineage/origin identifier, NOT a security primitive
#   - SHA-256 is used for content identity
#
# Dependencies: bash>=4, curl, jq, awk, sed, grep, find, sort, stat, wc,
#               sha256sum/shasum, optionally md5sum/md5, node, timeout, base64
# =============================================================================
set -o pipefail
shopt -s nullglob

VERSION="3.0.0"
AI_NAME="loopshape-ai-fusion"
BASE="${AI_HOME:-${HOME}/_}"
STATE="${AI_STATE_DIR:-$BASE/.ai-state}"
DB="$STATE/db"
OBJECTS="$DB/objects"
REFS="$DB/reference"
LLAMA_BIN="${LLAMA_BIN:-llama}"
BACKEND="${AI_BACKEND:-auto}"
GEMINI_API_KEY="${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}"
GEMINI_BASE_URL="${GEMINI_BASE_URL:-https://generativelanguage.googleapis.com/v1beta}"
GEMINI_UPLOAD_BASE_URL="${GEMINI_UPLOAD_BASE_URL:-https://generativelanguage.googleapis.com/upload/v1beta}"
GEMINI_MODEL="${AI_GEMINI_MODEL:-gemini-3.7-flash}"
GEMINI_IMAGE_MODEL="${AI_GEMINI_IMAGE_MODEL:-gemini-3.1-flash-image}"
GEMINI_AUDIO_MODEL="${AI_GEMINI_AUDIO_MODEL:-gemini-3.1-flash-tts-preview}"
GEMINI_VIDEO_MODEL="${AI_GEMINI_VIDEO_MODEL:-gemini-omni-flash-preview}"
GEMINI_MUSIC_MODEL="${AI_GEMINI_MUSIC_MODEL:-lyria-3-clip-preview}"
GEMINI_FAST_MODEL="${AI_GEMINI_FAST_MODEL:-gemini-3.5-flash-lite}"
GEMINI_PRO_MODEL="${AI_GEMINI_PRO_MODEL:-gemini-3.1-pro-preview}"
GEMINI_AGENT="${AI_GEMINI_AGENT:-antigravity-preview-05-2026}"
GEMINI_RESEARCH_AGENT="${AI_GEMINI_RESEARCH_AGENT:-deep-research-preview-04-2026}"
GEMINI_RESEARCH_MAX_AGENT="${AI_GEMINI_RESEARCH_MAX_AGENT:-deep-research-max-preview-04-2026}"
GEMINI_STORE="${AI_GEMINI_STORE:-true}"
GEMINI_STATEFUL="${AI_GEMINI_STATEFUL:-true}"
GEMINI_BACKGROUND="${AI_GEMINI_BACKGROUND:-false}"
GEMINI_ENVIRONMENT="${AI_GEMINI_ENVIRONMENT:-remote}"
GEMINI_TOOLS_FILE="${AI_GEMINI_TOOLS_FILE:-}"
GEMINI_AGENT_CONFIG_FILE="${AI_GEMINI_AGENT_CONFIG_FILE:-}"
GEMINI_MAX_OUTPUT="${AI_GEMINI_MAX_OUTPUT:-0}"
GEMINI_THINKING_SUMMARIES="${AI_GEMINI_THINKING_SUMMARIES:-auto}"
GEMINI_THINKING_LEVEL="${AI_GEMINI_THINKING_LEVEL:-}"
GEMINI_SERVICE_TIER="${AI_GEMINI_SERVICE_TIER:-standard}"
GEMINI_LAST_ID_FILE=""
OLLAMA_HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"

# llama defaults
LLAMA_MODEL="${AI_MODEL:-Qwen/Qwen2.5-Coder-3B-Instruct-GGUF}"
CTX="${AI_CTX:-4096}"
THREADS="${AI_THREADS:-8}"
GPU_LAYERS="${AI_GPU_LAYERS:-0}"
TEMP="${AI_TEMP:-0.65}"
TOP_P="${AI_TOP_P:-0.95}"
TOP_K="${AI_TOP_K:-40}"
REPEAT_PENALTY="${AI_REPEAT_PENALTY:-1.10}"
SEED="${AI_SEED:--1}"

# Ollama defaults / router ladder
OLLAMA_MODEL="${AI_OLLAMA_MODEL:-qwen3.5:4b}"
AI_CODER="${AI_CODER:-qwen2.5-coder:3b}"
AI_FALLBACK="${AI_FALLBACK:-qwen3:1.7b}"
AI_EMERGENCY="${AI_EMERGENCY:-qwen3:0.6b}"
KEEP_ALIVE="${AI_KEEP_ALIVE:-5m}"
THINK="${AI_THINK:-auto}"
AI_MAX_RAM_GB="${AI_MAX_RAM_GB:-0}"
AI_ENTROPY_UPGRADE="${AI_ENTROPY_UPGRADE:-1.55}"
AI_ENTROPY_DOWNGRADE="${AI_ENTROPY_DOWNGRADE:-0.55}"
AI_TOP_LOGPROBS="${AI_TOP_LOGPROBS:-5}"

VIEWS="${AI_VIEWS:-8}"
PARALLEL="${AI_PARALLEL:-0}"
SYNTHESIS="${AI_SYNTHESIS:-true}"
TIMEOUT="${AI_TIMEOUT:-600}"
SESSION="${AI_SESSION:-default}"
MAX_BYTES="${AI_MAX_BYTES:-10485760}"
VERBOSE="${AI_VERBOSE:-0}"
NO_STATS="${AI_NO_STATS:-0}"
SHOW_THINKING="${SHOW_THINKING:-0}"
STREAM="${AI_STREAM:-0}"
FORMAT="none"
MUSIC_OUTPUT=0
BACKGROUND="${AI_GEMINI_BACKGROUND:-0}"
AGENT=""
AGENT_SYSTEM=""
AGENT_CONFIG_FILE="${GEMINI_AGENT_CONFIG_FILE}"
ENVIRONMENT=""
ENVIRONMENT_JSON_FILE=""
TOOLS_FILE="${GEMINI_TOOLS_FILE}"
GENERATION_CONFIG_FILE=""
RESPONSE_FORMAT_FILE=""
IMAGE_ASPECT_RATIO="${AI_IMAGE_ASPECT_RATIO:-16:9}"
IMAGE_SIZE="${AI_IMAGE_SIZE:-1K}"
VIDEO_ASPECT_RATIO="${AI_VIDEO_ASPECT_RATIO:-16:9}"
VIDEO_RESOLUTION="${AI_VIDEO_RESOLUTION:-720p}"
UPLOAD_FILE=""
MIME_TYPE=""
SHOW_STEPS=0
SCHEMA_FILE=""
IMAGE_B64="[]"
UNLOAD=0
MODEL=""
EXPLICIT=0

EXCLUDE_REGEX='(^|/)(\.git|node_modules|\.venv|__pycache__|dist|build|\.ai-state)(/|$)'
SYSTEM_PROMPT="${AI_SYSTEM_PROMPT:-You are a precise local software agent. Produce technically correct, testable results. Separate observations from assumptions. Do not expose hidden chain-of-thought; provide concise conclusions and verification steps. Never claim to have executed commands you did not execute.}
"

mkdir -p "$DB" "$OBJECTS" "$REFS" "$STATE" || exit 1

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ai-fusion: missing dependency: $1" >&2; exit 127; }; }
for c in awk sed grep find sort stat wc tr date mktemp; do need "$c"; done
need jq
need curl
if command -v sha256sum >/dev/null 2>&1; then SHA_CMD=sha256sum; elif command -v shasum >/dev/null 2>&1; then SHA_CMD=shasum; else die="sha256sum or shasum required"; echo "ai-fusion: $die" >&2; exit 127; fi
if command -v md5sum >/dev/null 2>&1; then MD5_CMD=md5sum; elif command -v md5 >/dev/null 2>&1; then MD5_CMD=md5; else MD5_CMD=""; fi

log(){ (( VERBOSE )) && printf '[ai] %s\n' "$*" >&2 || true; }
warn(){ printf 'ai-fusion: warning: %s\n' "$*" >&2; }
die(){ printf 'ai-fusion: %s\n' "$*" >&2; exit 1; }
now(){ date -u +%Y-%m-%dT%H:%M:%SZ; }

sha256_text(){ if [[ "$SHA_CMD" == sha256sum ]]; then printf '%s' "$1"|sha256sum|awk '{print $1}'; else printf '%s' "$1"|shasum -a 256|awk '{print $1}'; fi; }
sha256_file(){ if [[ "$SHA_CMD" == sha256sum ]]; then sha256sum "$1"|awk '{print $1}'; else shasum -a 256 "$1"|awk '{print $1}'; fi; }
md5_text(){ [[ -n "$MD5_CMD" ]] || { printf 'md5-unavailable'; return; }; if [[ "$MD5_CMD" == md5sum ]]; then printf '%s' "$1"|md5sum|awk '{print $1}'; else printf '%s' "$1"|md5 -q; fi; }

init_db(){ for f in roots sessions tasks files traces scores events tokens artifacts runs reference interactions tool-calls; do [[ -f "$DB/$f.jsonl" ]] || : > "$DB/$f.jsonl"; done; [[ -f "$DB/index.json" ]] || jq -nc --arg v "$VERSION" --arg at "$(now)" '{schema:2,version:$v,createdAt:$at}' > "$DB/index.json"; }
init_db
append_json(){ printf '%s\n' "$2" >> "$DB/$1.jsonl"; }
object_put(){ local text="$1" h; h="$(sha256_text "$text")"; printf '%s' "$text" > "$OBJECTS/$h"; printf '%s' "$h"; }

event(){ local type="$1" data="${2:-}" ts id json; [[ -n "$data" ]] || data="{}"; ts="$(now)"; id="$(sha256_text "$SESSION|$ts|$type|$RANDOM")"; json="$(jq -cn --arg id "$id" --arg type "$type" --arg at "$ts" --arg session "$SESSION" --argjson data "$data" '{id:$id,event_type:$type,at:$at,session:$session,data:$data}')" || return; append_json events "$json"; (( VERBOSE )) && printf '[event] %s\n' "$type" >&2 || true; }

genesis_new(){ local ts mod7 seed root; ts="$(date +%s%3N 2>/dev/null || date +%s000)"; mod7=$((ts%7)); seed="$ts|$mod7|$SESSION|$BASE|${USER:-unknown}"; root="$(sha256_text "$seed")"; GENESIS_HASH="$root"; printf '%s\n' "$root" > "$STATE/genesis.hash"; append_json roots "$(jq -cn --arg id "$root" --arg ts "$ts" --argjson m "$mod7" --arg s "$SESSION" --arg w "$BASE" '{genesisHash:$id,timestampMs:$ts,mod7:$m,session:$s,workspace:$w}')"; event interaction.created "$(jq -cn --arg g "$root" --argjson m "$mod7" '{genesisHash:$g,mod7:$m}')"; }
genesis_current(){ [[ -s "$STATE/genesis.hash" ]] && cat "$STATE/genesis.hash" || { genesis_new; cat "$STATE/genesis.hash"; }; }

# -----------------------------------------------------------------------------
# RAM / model inventory / Ollama cache
# -----------------------------------------------------------------------------
ram_total_kb(){ awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0; }
ram_avail_kb(){ awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0; }
ram_total_gb(){ awk "BEGIN{printf \"%.2f\", $(ram_total_kb)/1048576}"; }
ram_avail_gb(){ awk "BEGIN{printf \"%.2f\", $(ram_avail_kb)/1048576}"; }

# name|class|GB|context|vision|tools|rank
MODELS=(
 "qwen3.5:4b|agent|3.40|262144|1|1|100"
 "qwen3:4b-instruct-2507-q4_K_M|agent|2.50|262144|0|1|94"
 "phi4-mini|agent|2.50|131072|0|1|92"
 "qwen2.5-coder:3b|coder|1.90|32768|0|1|90"
 "gemma3:4b|vision|3.30|131072|1|0|89"
 "qwen3.5:2b|agent|1.90|262144|1|1|86"
 "granite3.2:2b|agent|1.50|131072|0|1|82"
 "llama3.2:3b|agent|2.00|131072|0|1|81"
 "deepseek-r1:1.5b|reason|1.10|131072|0|1|79"
 "qwen3:1.7b|fallback|1.40|40960|0|1|77"
 "qwen3:0.6b|emergency|0.52|40960|0|1|60"
 "qwen2.5-coder:1.5b|coder|0.99|32768|0|1|69"
 "qwen2.5-coder:0.5b|coder|0.40|32768|0|1|55"
)

api(){ local path="$1"; shift; curl -fsS --connect-timeout 2 --max-time "$TIMEOUT" "$OLLAMA_HOST$path" "$@"; }
ollama_up(){ api /api/version >/dev/null 2>&1; }
installed_cache="$STATE/ollama-tags.json"
refresh_tags(){ api /api/tags > "$installed_cache.tmp" 2>/dev/null && mv "$installed_cache.tmp" "$installed_cache"; }
ensure_tags(){ [[ -s "$installed_cache" ]] || refresh_tags; jq -e '.models' "$installed_cache" >/dev/null 2>&1 || refresh_tags; }
model_installed(){ local m="$1"; ensure_tags || return 1; jq -e --arg m "$m" 'any(.models[]?; .name==$m or .model==$m)' "$installed_cache" >/dev/null 2>&1; }
model_size_gb(){ local m="$1" k; k="$(printf '%s\n' "${MODELS[@]}"|awk -F'|' -v m="$m" '$1==m{print $3;exit}')"; [[ -n "$k" ]] && { printf '%s\n' "$k"; return; }; api /api/show -d "$(jq -nc --arg name "$m" '{name:$name}')" 2>/dev/null|jq -r 'if (.size//0)>0 then .size/1073741824 elif (.details.parameter_size//"")|test("^[0-9.]+B$") then (.details.parameter_size|sub("B$";"")|tonumber) else 0 end'|awk 'NR==1{printf "%.2f\n",$1}'; }
model_context(){ printf '%s\n' "${MODELS[@]}"|awk -F'|' -v m="$1" '$1==m{print $4;exit}'; }
required_ram_gb(){ local m="$1" w c cache; w="$(model_size_gb "$m")"; c="$(model_context "$m")"; [[ -z "$c" ]]&&c=32768; cache="$(awk -v c="$c" 'BEGIN{if(c<=32768)print .5;else if(c<=65536)print 1;else if(c<=131072)print 2;else print 4}')"; awk -v w="$w" -v c="$cache" 'BEGIN{printf "%.2f",w+c+0.75}'; }

classify_task(){ local s="${1,,}"; if [[ "$s" =~ (image|photo|picture|screenshot|diagram|visual|ocr) ]]; then echo vision; elif [[ "$s" =~ (code|coding|script|bash|shell|python|javascript|typescript|rust|golang|debug|compile|refactor|regex|sql|docker|kubernetes|html|css|node) ]]; then echo coder; elif [[ "$s" =~ (prove|derive|reason|calculate|solve|why|analy[sz]e|architecture|trade.?off|research|deeply|step.?by.?step) ]]; then echo reason; else echo agent; fi; }

select_ollama_model(){
  local task="$1" avail="$(ram_avail_gb)"; [[ "$AI_MAX_RAM_GB" != 0 ]]&&avail="$AI_MAX_RAM_GB"
  local -a cs
  case "$task" in
    vision) cs=("qwen3.5:4b" "gemma3:4b" "qwen3.5:2b");;
    coder) cs=("$AI_CODER" "qwen3.5:4b" "qwen3:4b-instruct-2507-q4_K_M" "qwen2.5-coder:1.5b" "qwen3:1.7b" "qwen2.5-coder:0.5b");;
    reason) cs=("qwen3.5:4b" "qwen3:4b-instruct-2507-q4_K_M" "phi4-mini" "deepseek-r1:1.5b" "qwen3:1.7b" "qwen3:0.6b");;
    *) cs=("$OLLAMA_MODEL" "qwen3.5:4b" "qwen3:4b-instruct-2507-q4_K_M" "phi4-mini" "qwen3.5:2b" "granite3.2:2b" "llama3.2:3b" "$AI_FALLBACK" "$AI_EMERGENCY");;
  esac
  local c n; for c in "${cs[@]}"; do [[ -z "$c" ]]&&continue; if model_installed "$c"; then n="$(required_ram_gb "$c")"; if awk -v a="$avail" -v n="$n" 'BEGIN{exit !(a>=n)}'; then echo "$c"; return; fi; fi; done
  for c in "$AI_EMERGENCY" "$AI_FALLBACK"; do model_installed "$c"&&{ echo "$c"; return; }; done
  die "no eligible Ollama model installed";
}

# -----------------------------------------------------------------------------
# Prompt parser / scoring
# -----------------------------------------------------------------------------
PROMPT=""
parse_envelope(){
  local input="$*" tok; PROMPT=""; while read -r tok; do case "$tok" in
    @model=*) MODEL="${tok#@model=}"; EXPLICIT=1;;
    @backend=*) BACKEND="${tok#@backend=}";;
    @ctx=*) CTX="${tok#@ctx=}";; @threads=*) THREADS="${tok#@threads=}";;
    @gpu_layers=*) GPU_LAYERS="${tok#@gpu_layers=}";; @temp=*) TEMP="${tok#@temp=}";;
    @top_p=*) TOP_P="${tok#@top_p=}";; @top_k=*) TOP_K="${tok#@top_k=}";;
    @views=*) VIEWS="${tok#@views=}";; @parallel=*) PARALLEL="${tok#@parallel=}";;
    @synthesis=*) SYNTHESIS="${tok#@synthesis=}";; @think=*) THINK="${tok#@think=}";;
    @session=*) SESSION="${tok#@session=}";; @stream=*) STREAM="${tok#@stream=}";;
    @background=*) BACKGROUND="${tok#@background=}";; @agent=*) AGENT="${tok#@agent=}"; BACKEND=gemini;;
    @system=*) AGENT_SYSTEM="${tok#@system=}";; @environment=*) ENVIRONMENT="${tok#@environment=}";;
    @tools=*) TOOLS_FILE="${tok#@tools=}";; @generation_config=*) GENERATION_CONFIG_FILE="${tok#@generation_config=}";;
    @format=*) FORMAT="${tok#@format=}";; @image_output=*) FORMAT=image; BACKEND=gemini;;
    @audio_output=*) FORMAT=audio; BACKEND=gemini;; @video_output=*) FORMAT=video; BACKEND=gemini;; @music_output=*) FORMAT=audio; MUSIC_OUTPUT=1; BACKEND=gemini;;
    @google_search=true) enable_gemini_tool google_search;; @google_maps=true) enable_gemini_tool google_maps;; @code_execution=true) enable_gemini_tool code_execution;; @url_context=true) enable_gemini_tool url_context;;
    *) PROMPT+="${PROMPT:+ }$tok";; esac; done < <(printf '%s\n' "$input"|sed 's/\\ /__AI_ESC_SPACE__/g'|tr '[:space:]' '\n'|sed 's/__AI_ESC_SPACE__/ /g'); [[ -z "$PROMPT" ]]&&PROMPT="$input";
}

rank_tokens(){ local text="$1" tmp total; tmp="$(mktemp)"; printf '%s' "$text"|tr '\t\r\n' '   '|sed 's/[^[:alnum:]_+.#\/@:-]/ /g'|tr '[:upper:]' '[:lower:]'|awk '{for(i=1;i<=NF;i++)print $i}'|sort|uniq -c|sort -k1,1nr -k2,2 > "$tmp"; total="$(awk '{s+=$1}END{print s+0}' "$tmp")"; awk -v t="$total" 'BEGIN{OFS="\t"}{p=$1/t; s=-log(p)/log(2); w=(1-p)*s; print $2,$1,p,s,w}' "$tmp"; rm -f "$tmp"; }
entropy_text(){ local text="$1"; awk -v s="$text" 'BEGIN{n=split(s,a,/[^[:alnum:]_+.#\/@:-]+/);t=0;for(i=1;i<=n;i++)if(a[i]!=""){c[a[i]]++;t++}if(!t){print 0;exit}h=0;for(k in c){p=c[k]/t;h-=p*log(p)/log(2)}printf "%.8f\n",h}'; }
score_text(){ local t="$1" e n u w; e="$(entropy_text "$t")"; n="$(rank_tokens "$t"|awk '{s+=$2} END{print s+0}')"; u="$(rank_tokens "$t"|wc -l|awk '{print $1+0}')"; w="$(rank_tokens "$t"|awk '{s+=$5;n++}END{if(n)printf "%.8f",s/n;else print 0}')"; jq -cn --argjson entropy "$e" --argjson tokens "$n" --argjson unique "$u" --argjson weight "$w" '{entropy:$entropy,tokens:$tokens,unique:$unique,avgTokenWeight:$weight}'; }

# -----------------------------------------------------------------------------
# Gemini Interactions API backend
# -----------------------------------------------------------------------------
# Skill-derived contract:
# - Interactions are the stateful turn primitive.
# - tools/system_instruction/generation_config are interaction-scoped.
# - streaming uses SSE event_type + delta.
# - background agents are polled.
# - function calls are recorded/inspected; shell execution is never implicit.

gemini_available(){ [[ -n "$GEMINI_API_KEY" ]]; }
gemini_url(){ printf '%s%s' "$GEMINI_BASE_URL" "$1"; }
gemini_headers(){ printf '%s\n' '-H' "x-goog-api-key: $GEMINI_API_KEY" '-H' 'Content-Type: application/json'; }
gemini_api(){ local path="$1"; shift; gemini_available||return 127; curl -fsS --connect-timeout 5 --max-time "$TIMEOUT" "$(gemini_url "$path")" -H "x-goog-api-key: $GEMINI_API_KEY" -H 'Content-Type: application/json' "$@"; }
gemini_stream_api(){ local path="$1"; shift; gemini_available||return 127; curl -fsS --connect-timeout 5 --max-time "$TIMEOUT" --no-buffer -N "$(gemini_url "$path")" -H "x-goog-api-key: $GEMINI_API_KEY" -H 'Content-Type: application/json' -H 'Accept: text/event-stream' "$@"; }
gemini_model_for_task(){ if ((MUSIC_OUTPUT)); then printf '%s' "$GEMINI_MUSIC_MODEL"; return; fi; case "$FORMAT:$1" in image:*) printf '%s' "$GEMINI_IMAGE_MODEL";; audio:*) printf '%s' "$GEMINI_AUDIO_MODEL";; video:*) printf '%s' "$GEMINI_VIDEO_MODEL";; reason:*) printf '%s' "$GEMINI_PRO_MODEL";; *) printf '%s' "$GEMINI_MODEL";; esac; }
gemini_mime(){ local f="$1"; if command -v file >/dev/null 2>&1; then file -b --mime-type "$f" 2>/dev/null && return; fi; case "${f##*.}" in jpg|jpeg) echo image/jpeg;; png) echo image/png;; webp) echo image/webp;; gif) echo image/gif;; pdf) echo application/pdf;; txt|md|log) echo text/plain;; json) echo application/json;; html|htm) echo text/html;; mp3) echo audio/mpeg;; wav) echo audio/wav;; mp4) echo video/mp4;; mov) echo video/quicktime;; *) echo application/octet-stream;; esac; }

gemini_upload(){
  local f="$1" mime="${2:-}" hdr upurl bytes name resp;
  [[ -f "$f" ]]||return 2; mime="${mime:-$(gemini_mime "$f")}"; bytes="$(wc -c <"$f"|awk '{print $1}')"; name="$(basename "$f")";
  hdr="$(mktemp)";
  curl -fsS --connect-timeout 5 --max-time "$TIMEOUT" -D "$hdr" "$GEMINI_UPLOAD_BASE_URL/files" \
    -H "x-goog-api-key: $GEMINI_API_KEY" \
    -H 'X-Goog-Upload-Protocol: resumable' \
    -H 'X-Goog-Upload-Command: start' \
    -H "X-Goog-Upload-Header-Content-Length: $bytes" \
    -H "X-Goog-Upload-Header-Content-Type: $mime" \
    -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg n "$name" '{file:{display_name:$n}}')" >/dev/null || { rm -f "$hdr"; return 3; }
  upurl="$(awk 'BEGIN{IGNORECASE=1}/x-goog-upload-url:/{sub(/^[^:]*:[[:space:]]*/,"");gsub(/[\r\n]/,"");print;exit}' "$hdr")"; rm -f "$hdr";
  [[ -n "$upurl" ]]||return 4;
  resp="$(curl -fsS --connect-timeout 5 --max-time "$TIMEOUT" "$upurl" -H "Content-Length: $bytes" -H 'X-Goog-Upload-Offset: 0' -H 'X-Goog-Upload-Command: upload, finalize' --data-binary "@$f")" || return 5;
  jq -r '.file.uri // empty'<<<"$resp";
}

gemini_input_json(){
  local prompt="$1" f="${2:-}" mime uri typ size;
  if [[ -n "$f" && -f "$f" ]]; then
    mime="${MIME_TYPE:-$(gemini_mime "$f")}"; size="$(wc -c <"$f"|awk '{print $1}')";
    if [[ "$mime" == text/* && "$size" -le 10485760 ]]; then
      jq -nc --arg p "$prompt" --arg t "$(cat "$f")" '[{type:"text",text:$p},{type:"text",text:("\n--- FILE: " + $t)}]'; return;
    fi
    uri="$(gemini_upload "$f" "$mime")" || return 6;
    case "$mime" in image/*) typ=image;; audio/*) typ=audio;; video/*) typ=video;; *) typ=document;; esac
    jq -nc --arg p "$prompt" --arg u "$uri" --arg m "$mime" --arg t "$typ" '[{type:"text",text:$p},{type:$t,uri:$u,mime_type:$m}]';
  else
    jq -nc --arg p "$prompt" '[{type:"text",text:$p}]';
  fi
}

gemini_generation_config(){
  local cfg='{}';
  if [[ -n "$GENERATION_CONFIG_FILE" && -f "$GENERATION_CONFIG_FILE" ]]; then cfg="$(cat "$GENERATION_CONFIG_FILE")"; jq -e type >/dev/null 2>&1<<<"$cfg" || die "invalid generation config JSON"; fi
  [[ "$GEMINI_MAX_OUTPUT" =~ ^[0-9]+$ && "$GEMINI_MAX_OUTPUT" -gt 0 ]] && cfg="$(jq -c --argjson n "$GEMINI_MAX_OUTPUT" '.max_output_tokens=$n'<<<"$cfg")";
  [[ "$GEMINI_THINKING_SUMMARIES" != off ]] && cfg="$(jq -c --arg t "$GEMINI_THINKING_SUMMARIES" '.thinking_summaries=$t'<<<"$cfg")";
  [[ "$GEMINI_THINKING_LEVEL" =~ ^(minimal|low|medium|high)$ ]] && cfg="$(jq -c --arg t "$GEMINI_THINKING_LEVEL" '.thinking_level=$t'<<<"$cfg")";
  printf '%s' "$cfg";
}

gemini_response_format(){
  case "$FORMAT" in
    json) jq -nc '{type:"text",mime_type:"application/json"}';;
    schema) [[ -f "$SCHEMA_FILE" ]]||die "schema file not found: $SCHEMA_FILE"; jq -nc --argjson sch "$(cat "$SCHEMA_FILE")" '{type:"text",mime_type:"application/json",schema:$sch}';;
    image) jq -nc --arg ar "$IMAGE_ASPECT_RATIO" --arg sz "$IMAGE_SIZE" '{type:"image",aspect_ratio:$ar,image_size:$sz}';;
    audio) jq -nc '{type:"audio"}';;
    video) jq -nc --arg ar "$VIDEO_ASPECT_RATIO" --arg r "$VIDEO_RESOLUTION" '{type:"video",aspect_ratio:$ar,resolution:$r}';;
    *) printf 'null';;
  esac;
}

gemini_tools_json(){
  local t='[]';
  if [[ -n "$TOOLS_FILE" && -f "$TOOLS_FILE" ]]; then t="$(cat "$TOOLS_FILE")"; fi
  jq -e 'type=="array"' >/dev/null 2>&1 <<<"$t" || die "Gemini tools must be a JSON array"
  printf '%s' "$t"
}

enable_gemini_tool(){
  local typ="$1" f="$STATE/tools-cli.json" existing;
  case "$typ" in google_search|google_maps|code_execution|url_context|computer_use) ;; *) die "unsupported Gemini built-in tool: $typ";; esac
  existing="$(gemini_tools_json)";
  jq -cn --arg t "$typ" --argjson a "$existing" '($a + [{type:$t}]) | unique_by(tojson)' >"$f" || die "failed to build tools JSON";
  TOOLS_FILE="$f";
}

gemini_build_payload(){
  local model="$1" prompt="$2" prev="${3:-}" stream="${4:-0}" bg="${5:-0}" agent="${6:-}" env="${7:-}" input_json tools cfg rf='null' store="$GEMINI_STORE";
  [[ "$store" == true ]] || { [[ -z "$prev" && "$bg" != 1 && "$bg" != true ]] || die 'Gemini store=false cannot be combined with previous_interaction_id or background=true'; };
  input_json="$(gemini_input_json "$prompt" "${UPLOAD_FILE:-}")" || return;
  tools="$(gemini_tools_json)"; cfg="$(gemini_generation_config)"; [[ "$FORMAT" != none ]] && rf="$(gemini_response_format)";
  if [[ -n "$agent" ]]; then
    local envj='null' acfg='null';
    if [[ -n "$AGENT_CONFIG_FILE" && -f "$AGENT_CONFIG_FILE" ]]; then
      acfg="$(cat "$AGENT_CONFIG_FILE")"; jq -e 'type=="object"' >/dev/null 2>&1 <<<"$acfg" || die "invalid Gemini agent_config JSON";
    fi
    if [[ -n "$ENVIRONMENT_JSON_FILE" && -f "$ENVIRONMENT_JSON_FILE" ]]; then
      envj="$(cat "$ENVIRONMENT_JSON_FILE")"; jq -e 'type=="object" or type=="string"' >/dev/null 2>&1 <<<"$envj" || die "invalid Gemini environment JSON";
    else
      envj="$(jq -nc --arg e "${env:-remote}" '$e')";
    fi
    jq -nc --arg a "$agent" --argjson inp "$input_json" --argjson tl "$tools" --arg sys "$AGENT_SYSTEM" --argjson envj "$envj" --argjson acfg "$acfg" --argjson st "$store" --argjson rf "$rf" --arg tier "$GEMINI_SERVICE_TIER" --arg p "$prev" --argjson bg "$bg" --argjson str "$stream" '{agent:$a,input:$inp,stream:$str,background:$bg,store:$st}|if $tier!="standard" then .+{service_tier:$tier} else . end|if ($p|length)>0 then .+{previous_interaction_id:$p} else . end|if ($tl|length)>0 then .+{tools:$tl} else . end|if $sys!="" then .+{system_instruction:$sys} else . end|if ($acfg!=null) then .+{agent_config:$acfg} else . end|if ($envj!=null) then .+{environment:$envj} else . end|if $rf != null then .+{response_format:$rf} else . end';
  else
    jq -nc --arg m "$model" --argjson inp "$input_json" --arg sys "$SYSTEM_PROMPT" --argjson tl "$tools" --argjson gc "$cfg" --argjson st "$store" --argjson rf "$rf" --arg p "$prev" --argjson bg "$bg" --argjson str "$stream" --arg tier "$GEMINI_SERVICE_TIER" '{model:$m,input:$inp,system_instruction:$sys,stream:$str,background:$bg,store:$st}|if $tier!="standard" then .+{service_tier:$tier} else . end|if ($p|length)>0 then .+{previous_interaction_id:$p} else . end|if ($tl|length)>0 then .+{tools:$tl} else . end|if ($gc|length)>0 then .+{generation_config:$gc} else . end|if $rf != null then .+{response_format:$rf} else . end';
  fi
}

gemini_extract_text(){ jq -r '[.steps[]?.content[]? | select(.type=="text") | .text] | join("") // empty'; }
gemini_extract_output_text(){ jq -r '[.steps[]? | select(.type=="model_output") | .content[]? | select(.type=="text") | .text] | join("")'; }
gemini_record_steps(){ local response="$1" id="${2:-}"; [[ -n "$response" ]]||return; while IFS= read -r step; do [[ -z "$step" ]]&&continue; append_json interactions "$(jq -c --arg id "$id" --argjson st "$step" '{interactionId:$id,step:$st,at:now|todate}')"; case "$(jq -r '.type//empty'<<<"$step")" in function_call) append_json "tool-calls" "$(jq -c --arg id "$id" '{interactionId:$id,type:.type,id:(.id//""),name:(.name//""),arguments:(.arguments//{})}'<<<"$step")";; esac; done < <(jq -c '.steps[]?'<<<"$response"); }

gemini_print_steps(){ local response="$1"; if ((SHOW_STEPS)); then jq -c '.steps[]? | {type,index,id,name,call_id,status}'<<<"$response" >&2; fi; }

gemini_save_response_assets(){
  local response="$1" iid="${2:-response}" typ mime data f idx=0;
  while IFS=$'\t' read -r typ mime data; do
    [[ -n "$data" ]]||continue; idx=$((idx+1)); f="$(gemini_save_asset "$data" "$mime" "${iid}-${idx}")";
    [[ -n "$f" ]]&&append_json artifacts "$(jq -nc --arg p "$f" --arg m "$mime" --arg g "$(genesis_current)" '{type:"gemini-output",path:$p,mime_type:$m,genesisHash:$g,at:now|todate}')";
  done < <(jq -r '.steps[]? | select(.type=="model_output") | .content[]? | select(.type=="image" or .type=="audio" or .type=="video") | [.type,(.mime_type//"application/octet-stream"),(.data//"")] | @tsv'<<<"$response" 2>/dev/null)
}

gemini_generate(){
  local prompt="$1" out="$2" model="${3:-$GEMINI_MODEL}" seed="${4:--1}" prev="${5:-}" stream="${6:-$STREAM}" bg="${7:-$BACKGROUND}" agent="${8:-}" env="${9:-}" payload response id rc status errmsg;
  gemini_available||return 127;
  payload="$(gemini_build_payload "$model" "$prompt" "$prev" "$stream" "$bg" "$agent" "$env")" || return 2;
  printf '%s\n' "$payload" > "$STATE/last-gemini-request.json"; : >"$out"; rm -f "$out.stderr";
  if ((stream)); then
    : >"$STATE/last-gemini-stream.sse";
    while IFS= read -r line; do
      [[ "$line" == data:\ * ]]||continue; line="${line#data: }"; [[ "$line" == '[DONE]' ]]&&break; jq -e type >/dev/null 2>&1<<<"$line"||continue; printf '%s\n' "$line" >>"$STATE/last-gemini-stream.sse";
      et="$(jq -r '.event_type//empty'<<<"$line")";
      case "$et" in
        interaction.created) id="$(jq -r '.interaction.id//empty'<<<"$line")";;
        step.start) ((SHOW_STEPS))&&jq -c '{event_type,index,step}'<<<"$line" >&2;;
        step.delta) dt="$(jq -r '.delta.type//empty'<<<"$line")"; case "$dt" in text) jq -r '.delta.text//empty'<<<"$line" | tee -a "$out";; thought_summary) ((SHOW_THINKING||SHOW_STEPS))&&jq -r '.delta.content.text//empty'<<<"$line" >&2;; image|audio|video) data="$(jq -r '.delta.data//empty'<<<"$line")"; mime="$(jq -r '.delta.mime_type//application/octet-stream'<<<"$line")"; [[ -n "$data" ]]&&gemini_save_asset "$data" "$mime" "${id:-asset}" >/dev/null;; arguments_delta) ((SHOW_STEPS))&&jq -r '.delta.arguments//empty'<<<"$line" >&2;; esac;;
        interaction.completed) id="$(jq -r '.interaction.id//empty'<<<"$line")"; printf '%s\n' "$line">"$STATE/last-gemini-response.json";;
        interaction.status_update) ((SHOW_STEPS))&&jq -c .<<<"$line" >&2;;
      esac
    done < <(gemini_stream_api /interactions -d "$(cat "$STATE/last-gemini-request.json")")
    response="$(cat "$STATE/last-gemini-response.json" 2>/dev/null)";
  else
    response="$(gemini_api /interactions -d "$payload")"; rc=$?; ((rc!=0))&&{ printf '%s\n' 'Gemini request failed' >"$out.stderr"; return "$rc"; }
    printf '%s\n' "$response">"$STATE/last-gemini-response.json"; id="$(jq -r '.id//empty'<<<"$response")"; status="$(jq -r '.status//empty'<<<"$response")";
    if ((bg)) && [[ "$status" == in_progress || "$status" == requires_action ]]; then
      printf '%s\n' "$id">"$STATE/gemini-background.id";
      [[ "${AI_GEMINI_DETACH:-false}" == true ]] || { response="$(gemini_poll "$id" 5)" || return 1; printf '%s\n' "$response">"$STATE/last-gemini-response.json"; }
    fi
  fi
  [[ -n "$response" ]]||return 3; gemini_record_steps "$response" "$id"; gemini_print_steps "$response"; gemini_save_response_assets "$response" "$id"; gemini_print_stats "$response";
  [[ -n "$id" ]]&&printf '%s\n' "$id">"$STATE/gemini-interaction-${SESSION//[^A-Za-z0-9_.-]/_}.id";
  errmsg="$(jq -r '.error.message//empty'<<<"$response")"; [[ -z "$errmsg" ]]||{ printf '%s\n' "$errmsg">"$out.stderr"; return 21; };
  gemini_extract_output_text<<<"$response">"$out"; [[ -s "$out" ]]||gemini_extract_text<<<"$response">"$out"; return 0;
}

gemini_save_asset(){ local b64="$1" mime="$2" iid="${3:-asset}" ext; mkdir -p "$STATE/assets"; case "$mime" in image/png) ext=png;; image/webp) ext=webp;; image/jpeg) ext=jpg;; audio/wav) ext=wav;; audio/mpeg|audio/mp3) ext=mp3;; audio/ogg*) ext=ogg;; video/mp4) ext=mp4;; video/webm) ext=webm;; *) ext=bin;; esac; local f="$STATE/assets/${iid:-asset}-$(date +%Y%m%d-%H%M%S).$ext"; if command -v base64 >/dev/null 2>&1;then printf '%s' "$b64"|base64 -d >"$f" 2>/dev/null || printf '%s' "$b64"|base64 --decode >"$f" 2>/dev/null || true; fi; [[ -s "$f" ]]&&printf '%s\n' "$f" || true; }
gemini_print_stats(){ local r="$1"; ((NO_STATS))&&return 0; jq -r 'if (.usage//null) then "[gemini input=\(.usage.total_input_tokens//0) output=\(.usage.total_output_tokens//0) thought=\(.usage.total_thought_tokens//0) cached=\(.usage.total_cached_tokens//0) total=\(.usage.total_tokens//0)]" else empty end' <<<"$r" >&2; }

gemini_get(){ local id="$1"; [[ -n "$id" ]]||id="$(cat "$STATE/gemini-interaction-${SESSION//[^A-Za-z0-9_.-]/_}.id" 2>/dev/null)"; [[ -n "$id" ]]||die 'no Gemini interaction id'; gemini_api "/interactions/$id"; }
gemini_delete(){ local id="$1"; [[ -n "$id" ]]||die 'interaction id required'; curl -fsS -X DELETE --connect-timeout 5 --max-time "$TIMEOUT" "$(gemini_url "/interactions/$id")" -H "x-goog-api-key: $GEMINI_API_KEY"; }
gemini_poll(){ local id="$1" interval="${2:-5}" response status; while :; do response="$(gemini_get "$id")"||return; status="$(jq -r '.status//.interaction.status//empty'<<<"$response")"; printf '%s\n' "$response">"$STATE/last-gemini-response.json"; case "$status" in completed|failed|cancelled|incomplete) printf '%s\n' "$response"; return 0;; *) sleep "$interval";; esac; done; }

gemini_research(){ local prompt="$1" agent="${2:-$GEMINI_RESEARCH_AGENT}" out="$STATE/research.txt" response id; response="$(gemini_build_payload "$GEMINI_MODEL" "$prompt" '' 0 1 "$agent" remote)"||return; response="$(gemini_api /interactions -d "$response")"||return; id="$(jq -r '.id//empty'<<<"$response")"; printf '%s\n' "$id">"$STATE/gemini-research.id"; append_json interactions "$(jq -c --arg id "$id" --arg a "$agent" '{interactionId:$id,agent:$a,mode:"background"}')"; while :; do response="$(gemini_get "$id")"||return 1; status="$(jq -r '.status//empty'<<<"$response")"; ((VERBOSE))&&printf '[research] status=%s\n' "$status" >&2; case "$status" in completed|failed|cancelled|incomplete) break;; *) sleep 5;; esac; done; gemini_extract_output_text<<<"$response">"$out"; printf '%s\n' "$response">"$STATE/last-gemini-response.json"; cat "$out"; }

gemini_function_resume(){
  local interaction_id="$1" call_id="$2" name="$3" result="$4" model="${5:-$GEMINI_MODEL}" payload response tools cfg rf='null';
  [[ -n "$interaction_id" && -n "$call_id" && -n "$name" ]]||die 'resume-function requires INTERACTION_ID CALL_ID FUNCTION_NAME [RESULT_JSON]'; [[ -n "$result" ]]||result='{}';
  jq -e type >/dev/null 2>&1<<<"$result"||result="$(jq -nc --arg r "$result" '{result:$r}')"; tools="$(gemini_tools_json)"; cfg="$(gemini_generation_config)"; [[ "$FORMAT" != none ]]&&rf="$(gemini_response_format)";
  payload="$(jq -nc --arg m "$model" --arg iid "$interaction_id" --arg cid "$call_id" --arg n "$name" --argjson r "$result" --argjson tl "$tools" --argjson gc "$cfg" --argjson rf "$rf" '{model:$m,previous_interaction_id:$iid,input:[{type:"function_result",name:$n,call_id:$cid,result:[{type:"text",text:($r|tojson)}]}],store:true}|if ($tl|length)>0 then .+{tools:$tl} else . end|if ($gc|length)>0 then .+{generation_config:$gc} else . end|if $rf != null then .+{response_format:$rf} else . end')";
  response="$(gemini_api /interactions -d "$payload")"||return; printf '%s\n' "$payload">"$STATE/last-gemini-request.json"; printf '%s\n' "$response">"$STATE/last-gemini-response.json"; gemini_record_steps "$response" "$(jq -r '.id//empty'<<<"$response")"; gemini_save_response_assets "$response" "$(jq -r '.id//empty'<<<"$response")"; gemini_extract_output_text<<<"$response";
}

# File Search store helpers. Persistent File Search data is separate from transient Files uploads.
gemini_file_search_stores(){ gemini_api /fileSearchStores; }
gemini_file_search_create(){ local name="$1" emb="${2:-models/gemini-embedding-2}"; [[ -n "$name" ]]||die 'file-search store display name required'; gemini_api /fileSearchStores -d "$(jq -nc --arg d "$name" --arg e "$emb" '{displayName:$d,embeddingModel:$e}')"; }
gemini_file_search_upload(){ local store="$1" f="$2" hdr upurl bytes mime; [[ -n "$store" && -f "$f" ]]||die 'file-search upload requires STORE FILE'; mime="$(gemini_mime "$f")"; bytes="$(wc -c <"$f"|awk '{print $1}')"; hdr="$(mktemp)"; curl -fsS --connect-timeout 5 --max-time "$TIMEOUT" -D "$hdr" "$GEMINI_UPLOAD_BASE_URL/$store:uploadToFileSearchStore" -H "x-goog-api-key: $GEMINI_API_KEY" -H 'X-Goog-Upload-Protocol: resumable' -H 'X-Goog-Upload-Command: start' -H "X-Goog-Upload-Header-Content-Length: $bytes" -H "X-Goog-Upload-Header-Content-Type: $mime" -H 'Content-Type: application/json' -d "$(jq -nc --arg n "$(basename "$f")" '{displayName:$n}')" >/dev/null || { rm -f "$hdr"; return 1; }; upurl="$(awk 'BEGIN{IGNORECASE=1}/x-goog-upload-url:/{sub(/^[^:]*:[[:space:]]*/,"");gsub(/[\r\n]/,"");print;exit}' "$hdr")"; rm -f "$hdr"; [[ -n "$upurl" ]]||return 2; curl -fsS --connect-timeout 5 --max-time "$TIMEOUT" "$upurl" -H "Content-Length: $bytes" -H 'X-Goog-Upload-Offset: 0' -H 'X-Goog-Upload-Command: upload, finalize' --data-binary "@$f"; }
gemini_file_search_delete(){ local name="$1"; [[ -n "$name" ]]||die 'file-search store name required'; gemini_api "/$name" -X DELETE; }
gemini_file_search_query(){ local store="$1" prompt="$2" old="$TOOLS_FILE" f="$STATE/file-search-tools.json"; [[ -n "$store" && -n "$prompt" ]]||die 'file-search requires STORE PROMPT'; jq -nc --arg n "$store" '[{type:"file_search",file_search_store_names:[$n]}]' >"$f"; TOOLS_FILE="$f"; BACKEND=gemini; VIEWS=1; SYNTHESIS=false; run_prompt "$prompt"; TOOLS_FILE="$old"; }

# Managed-agent registry API
gemini_agents(){ gemini_api /agents; }
gemini_agent_get(){ local id="$1"; [[ -n "$id" ]]||die 'agent id required'; gemini_api "/agents/$id"; }
gemini_agent_delete(){ local id="$1"; [[ -n "$id" ]]||die 'agent id required'; curl -fsS -X DELETE --connect-timeout 5 --max-time "$TIMEOUT" "$(gemini_url "/agents/$id")" -H "x-goog-api-key: $GEMINI_API_KEY"; }
gemini_agent_create(){ local f="$1" body; [[ -f "$f" ]]||die "agent definition not found: $f"; body="$(cat "$f")"; jq -e 'type=="object" and (.id|type=="string") and (.base_agent|type=="string")' >/dev/null 2>&1 <<<"$body" || die 'agent definition must contain string id and base_agent'; gemini_api /agents -d "$body"; }

gemini_list_models(){ [[ -n "$GEMINI_API_KEY" ]]||die 'GEMINI_API_KEY not set'; gemini_api /models; }

gemini_upload_cmd(){ local f="$1"; [[ -f "$f" ]]||die 'file not found'; local uri="$(gemini_upload "$f" "$(gemini_mime "$f")")"; [[ -n "$uri" ]]||die 'upload failed'; jq -n --arg file "$f" --arg uri "$uri" --arg mime "$(gemini_mime "$f")" '{path:$file,uri:$uri,mime_type:$mime}'; }

# -----------------------------------------------------------------------------
# Backend generation
# -----------------------------------------------------------------------------
llama_available(){ command -v "$LLAMA_BIN" >/dev/null 2>&1; }
resolve_backend(){ case "$BACKEND" in llama|ollama|gemini) echo "$BACKEND";; auto) if llama_available; then echo llama; elif ollama_up; then echo ollama; elif gemini_available; then echo gemini; else die "no AI backend available (llama, Ollama, Gemini)"; fi;; *) die "backend must be auto|llama|ollama|gemini"; esac; }

llama_generate(){
  local prompt="$1" out="$2" seed="${3:--1}"; llama_available||return 127
  local -a a=(cli -hf "$LLAMA_MODEL" --ctx-size "$CTX" --threads "$THREADS" --gpu-layers "$GPU_LAYERS" --temp "$TEMP" --top-p "$TOP_P" --top-k "$TOP_K" --repeat-penalty "$REPEAT_PENALTY" --seed "$seed" --prompt "$prompt")
  log "llama: ${a[*]}"; if [[ "$TIMEOUT" =~ ^[0-9]+$ ]]&&command -v timeout >/dev/null 2>&1; then timeout "${TIMEOUT}s" "$LLAMA_BIN" "${a[@]}" >"$out" 2>"$out.stderr"; else "$LLAMA_BIN" "${a[@]}" >"$out" 2>"$out.stderr"; fi
}

ollama_payload(){
  local model="$1" prompt="$2" stream="$3" think="$4" format="${5:-none}" schema="${6:-}" images="${7:-[]}";
  jq -nc --arg m "$model" --arg s "$SYSTEM_PROMPT" --arg p "$prompt" --arg ka "$KEEP_ALIVE" --argjson st "$stream" --arg th "$think" --arg fmt "$format" --argjson imgs "$images" --argjson sch "$(if [[ -n "$schema"&&-f "$schema" ]];then cat "$schema";else echo '{}';fi)" '{model:$m,messages:[{role:"system",content:$s},{role:"user",content:$p}],stream:$st,keep_alive:$ka}|if $th=="auto" then . else .+{think:$th} end|if $fmt=="json" then .+{format:"json"} elif $fmt=="schema" then .+{format:$sch} else . end|if ($imgs|length)>0 then .messages[1].images=$imgs else . end'; }

ollama_generate(){
  local prompt="$1" out="$2" model="$3" format="${4:-none}" schema="${5:-}" images="${6:-[]}";
  local payload rc response tmp; payload="$(ollama_payload "$model" "$prompt" 0 "$THINK" "$format" "$schema" "$images")" || return 2; printf '%s\n' "$payload" > "$STATE/last-request.json";
  response="$(printf '%s' "$payload"|curl -fsS --connect-timeout 2 --max-time "$TIMEOUT" "$OLLAMA_HOST/api/chat" -H 'Content-Type: application/json' -d @-)"; rc=$?; ((rc!=0))&&return "$rc"; jq -e '.error' >/dev/null 2>&1<<<"$response"&&{ jq -r '.error'<<<"$response">"$out.stderr"; return 21; }; jq -r '.message.content // empty'<<<"$response">"$out"; printf '%s\n' "$response">"$STATE/last-response.json"; printf '%s\n' "$(entropy_ollama "$response")">"$STATE/last-entropy"; if [[ "$NO_STATS" != 1 ]];then print_ollama_stats "$model" "$response";fi; return 0;
}
entropy_ollama(){
  jq -r '
    [.logprobs[]? |
      ([.top_logprobs[]?.logprob] + [.logprob]) |
      map(select(type=="number")) |
      if length == 0 then empty
      else
        (map(exp)|add) as $z |
        if $z <= 0 then empty
        else (map(exp/$z)|map(select(.>0)|-(.*(log(.)/log(2))))|add) end
      end
    ] |
    if length==0 then "NA" else (add/length|tostring) end
  ' 2>/dev/null <<<"$1"
}
print_ollama_stats(){ local m="$1" r="$2" p e d l t; p="$(jq -r '.prompt_eval_count//0'<<<"$r")"; e="$(jq -r '.eval_count//0'<<<"$r")"; d="$(jq -r '.eval_duration//0'<<<"$r")"; l="$(jq -r '.load_duration//0'<<<"$r")"; t="$(awk -v e="$e" -v d="$d" 'BEGIN{if(d>0)printf "%.2f",e/(d/1e9);else print 0}')"; printf '\n[backend=ollama model=%s prompt=%s output=%s tok/s=%s load_ms=%s entropy=%s]\n' "$m" "$p" "$e" "$t" "$(awk -v x="$l" 'BEGIN{printf "%.1f",x/1e6}')" "$(entropy_ollama "$r")" >&2; }

backend_generate(){
  local backend="$1" prompt="$2" out="$3" seed="${4:--1}" model="${5:-}" format="${6:-none}" schema="${7:-}" images="${8:-[]}";
  case "$backend" in
    llama) llama_generate "$prompt" "$out" "$seed";;
    ollama) [[ -n "$model" ]]||model="$(select_ollama_model "$(classify_task "$prompt")")"; ollama_generate "$prompt" "$out" "$model" "$format" "$schema" "$images";;
    gemini) [[ -n "$model" ]]||model="$(gemini_model_for_task "$(classify_task "$prompt")")"; local prev=""; if [[ "$GEMINI_STATEFUL" == true && "$GEMINI_STORE" == true && "$VIEWS" -le 1 ]]; then prev="$(cat "$STATE/gemini-interaction-${SESSION//[^A-Za-z0-9_.-]/_}.id" 2>/dev/null)"; fi; gemini_generate "$prompt" "$out" "$model" "$seed" "$prev" "$STREAM" "$BACKGROUND" "${AGENT:-}" "${ENVIRONMENT:-}";;
    *) return 2;;
  esac
}

# -----------------------------------------------------------------------------
# Session / CRUD / indexing
# -----------------------------------------------------------------------------
session_file(){ printf '%s/sessions/%s.json' "$STATE" "${SESSION//[^A-Za-z0-9_.-]/_}"; }
ensure_session(){ mkdir -p "$STATE/sessions"; local f; f="$(session_file)"; [[ -s "$f" ]]||printf '[]\n'>"$f"; jq empty "$f" >/dev/null 2>&1||printf '[]\n'>"$f"; }
append_session(){ ensure_session; local f; f="$(session_file)"; jq --arg r "$1" --arg c "$2" '.+[{role:$r,content:$c}]' "$f">"$f.tmp"&&mv "$f.tmp" "$f"; }
atomic_write(){ local dst="$1" src="$2"; mkdir -p "$(dirname "$dst")"; [[ -e "$dst" ]]&&cp -a "$dst" "$dst.ai-before-$(date +%s)" 2>/dev/null||true; mv "$src" "$dst"; }
crud(){ local op="$1" path="$2"; shift 2||true; case "$op" in create) [[ -e "$path" ]]&&die "already exists: $path"; mkdir -p "$(dirname "$path")"; :>"$path";; read) [[ -f "$path" ]]||die "not a file: $path"; cat "$path";; write|update) local tmp; tmp="$(mktemp)"; if (($#));then printf '%s' "$*">"$tmp";else cat>"$tmp";fi; atomic_write "$path" "$tmp"; index_file "$path";; append) mkdir -p "$(dirname "$path")"; (($#))&&printf '%s\n' "$*">>"$path"||cat>>"$path"; index_file "$path";; delete|remove) [[ -e "$path" ]]||die "not found: $path"; local h="$(sha256_file "$path")"; rm -f -- "$path"; append_json artifacts "$(jq -cn --arg p "$path" --arg parent "$h" --arg g "$(genesis_current)" '{type:"tombstone",path:$p,parentHash:$parent,genesisHash:$g,at:now|todate}')";; *) die "crud: create|read|write|append|delete";; esac; }
index_file(){ local f="$1"; [[ -f "$f" ]]||return; local b; b="$(wc -c<"$f"|awk '{print $1}')"; ((b>MAX_BYTES))&&return; local h="$(sha256_file "$f")" m="$(md5_text "$(genesis_current)|$f")"; cp "$f" "$OBJECTS/$h" 2>/dev/null||true; append_json files "$(jq -cn --arg p "$f" --arg sha "$h" --arg md5 "$m" --argjson b "$b" '{path:$p,sha256:$sha,originHash:$md5,bytes:$b,at:now|todate}')"; }
index_dir(){ local root="${1:-$BASE}"; [[ -d "$root" ]]||die "directory not found: $root"; genesis_new>/dev/null; local n=0 f; while IFS= read -r -d '' f;do [[ "$f" =~ $EXCLUDE_REGEX ]]&&continue; index_file "$f"; n=$((n+1));done< <(find "$root" -type f -print0); jq -nc --arg root "$root" --arg g "$GENESIS_HASH" --argjson n "$n" '{action:"index",root:$root,genesisHash:$g,count:$n,at:now|todate}'; }

# -----------------------------------------------------------------------------
# 2PI/8 multiview engine
# -----------------------------------------------------------------------------
VIEW_NAMES=(Nexus Cognito Relay Sentinel Echo Vector XOR-Pool Origin-7)
VIEW_ROLES=(
 'Structural architect: decompose requirements into modules, interfaces, invariants and dependencies.'
 'Entropy analyst: identify ambiguity, information density, priorities and uncertainty.'
 'Context router: normalize inputs, files, runtime constraints and operational assumptions.'
 'Validation guard: find bugs, unsafe assumptions, portability problems and edge cases.'
 'Synthesis planner: compare alternatives and select compatible implementation paths.'
 'Systems optimizer: minimize CPU, memory, latency, I/O and redundant inference.'
 'Adversarial evaluator: challenge the proposed solution with counterexamples and failure modes.'
 'Origin tracer: preserve provenance, hashes, reproducibility, rollback and artifact lineage.'
)
parallel_limit(){ if [[ "$PARALLEL" =~ ^[0-9]+$ ]]&&((PARALLEL>0));then echo "$PARALLEL";else local c="$(getconf _NPROCESSORS_ONLN 2>/dev/null||echo 2)"; ((c>4))&&c=4; ((c<1))&&c=1; echo "$c";fi; }

run_view(){ local prompt="$1" idx="$2" out="$3" parent="$4" backend="$5" model="$6"; local seed=$((7919*(idx+1)+7)); local name="${VIEW_NAMES[$idx]}" role="${VIEW_ROLES[$idx]}"; event step.start "$(jq -cn --argjson v "$idx" --arg n "$name" '{view:$v,name:$n}')"; local vp; vp=$(cat<<EOF
SYSTEM ROLE:
$role

TASK:
$prompt

RUNTIME:
backend=$backend model=$model context=$CTX threads=$THREADS

MULTIVIEW CONTRACT:
You are view $((idx+1))/8 at rotation $((idx*45)) degrees. Return conclusions, rationale summaries, risks and concrete actions. Do not reveal hidden chain-of-thought.
EOF
); if ! backend_generate "$backend" "$vp" "$out" "$seed" "$model" "$FORMAT" "$SCHEMA_FILE" "$IMAGE_B64";then event step.stop "$(jq -cn --argjson v "$idx" '{view:$v,status:"failed"}')"; return 1;fi; local text="$(cat "$out")" h="$(sha256_text "$text")" m="$(md5_text "$text")" metrics="$(score_text "$text")" score="$(awk -v e="$(jq -r .entropy<<<"$metrics")" -v w="$(jq -r .avgTokenWeight<<<"$metrics")" 'BEGIN{printf "%.8f",(e+1)*(w+1)}')"; if [[ "$out" != "$STATE/view-$idx.txt" ]]; then cp "$out" "$STATE/view-$idx.txt"; fi; object_put "$text">/dev/null; append_json traces "$(jq -cn --arg id "$h" --arg m "$m" --arg g "$GENESIS_HASH" --arg p "$parent" --argjson v "$idx" --arg n "$name" --argjson metrics "$metrics" --argjson score "$score" '{type:"model-output",id:$id,md5:$m,genesisHash:$g,parentHash:$p,view:$v,viewName:$n,metrics:$metrics,score:$score,at:now|todate}')"; event step.delta "$(jq -cn --argjson v "$idx" --arg sha "$h" --argjson score "$score" '{view:$v,sha256:$sha,score:$score}')"; event step.stop "$(jq -cn --argjson v "$idx" '{view:$v,status:"completed"}')"; }

synthesize(){ local prompt="$1" parent="$2" backend="$3" model="$4"; local bundle="$STATE/view-bundle.txt" out="$STATE/final.txt"; :>"$bundle"; local f; for f in "$STATE"/view-{0,1,2,3,4,5,6,7}.txt;do [[ -f "$f" ]]||continue; printf '\n=== %s ===\n' "$(basename "$f")">>"$bundle"; cat "$f">>"$bundle";done; local sp; sp=$(cat<<EOF
You are the deterministic synthesis stage of a local multi-view software agent.
Original task:
$prompt

Candidate conclusions:
$(cat "$bundle")

Select the strongest evidence-backed conclusions. Resolve contradictions explicitly. Produce the final implementation/result, not hidden chain-of-thought. Include verification steps and preserve important constraints.
EOF
); event step.start '{"stage":"synthesis"}'; backend_generate "$backend" "$sp" "$out" 991948 "$model" || return 1; local text="$(cat "$out")" h="$(sha256_text "$text")" m="$(md5_text "$text")" metrics="$(score_text "$text")"; append_json traces "$(jq -cn --arg id "$h" --arg m "$m" --arg g "$GENESIS_HASH" --arg p "$parent" --argjson metrics "$metrics" '{type:"synthesis",id:$id,md5:$m,genesisHash:$g,parentHash:$p,metrics:$metrics,at:now|todate}')"; event interaction.completed "$(jq -cn --arg sha "$h" '{finalSha256:$sha}')"; cat "$out"; }

run_prompt(){ local raw="$*"; parse_envelope "$raw"; [[ -n "$PROMPT" ]]||die 'empty prompt'; ensure_session; genesis_new>/dev/null; local backend="$(resolve_backend)" task="$(classify_task "$PROMPT")" model="$MODEL"; if [[ "$backend" == ollama && -z "$model" ]];then model="$(select_ollama_model "$task")";fi; [[ "$backend" == llama ]]&&model="$LLAMA_MODEL"; local inputHash="$(sha256_text "$PROMPT")" originHash="$(md5_text "$GENESIS_HASH|$PROMPT")" taskId="$(sha256_text "$GENESIS_HASH|$originHash|$inputHash")"; append_json tasks "$(jq -cn --arg id "$taskId" --arg input "$inputHash" --arg origin "$originHash" --arg g "$GENESIS_HASH" --arg b "$backend" --arg model "$model" --arg task "$task" --arg p "$PROMPT" '{taskId:$id,sha256:$input,originHash:$origin,genesisHash:$g,backend:$b,model:$model,taskClass:$task,prompt:$p,at:now|todate}')"; event step.start "$(jq -cn --arg id "$taskId" --arg b "$backend" --arg m "$model" '{stage:"task",taskId:$id,backend:$b,model:$m}')"; ((VIEWS<1))&&VIEWS=1; ((VIEWS>8))&&VIEWS=8; local limit="$(parallel_limit)"; local pids=() i out; :>"$STATE/view-bundle.txt"; for ((i=0;i<VIEWS;i++));do out="$STATE/view-$i.txt"; while (( $(jobs -rp|wc -l) >= limit ));do wait -n 2>/dev/null||true;done; run_view "$PROMPT" "$i" "$out" "$taskId" "$backend" "$model" & pids+=("$!"); done; local rc=0 pid; for pid in "${pids[@]}";do wait "$pid"||rc=1;done; ((rc==0))||die 'one or more views failed'; jq -s 'map(select(.type=="model-output"))|sort_by(-.score)' "$DB/traces.jsonl">"$STATE/last-ranking.json"; event step.stop "$(jq -cn --arg id "$taskId" --argjson v "$VIEWS" '{stage:"ranking",taskId:$id,views:$v}')"; if [[ "$SYNTHESIS" == 1 || "$SYNTHESIS" == true ]];then synthesize "$PROMPT" "$taskId" "$backend" "$model";else cat "$STATE/view-0.txt";fi; append_session user "$PROMPT"; append_session assistant "$(cat "$STATE/final.txt" 2>/dev/null||cat "$STATE/view-0.txt")"; }

# -----------------------------------------------------------------------------
# WebKit/HTML5 coder agent + validator + repair loop
# -----------------------------------------------------------------------------
validate_html(){ local f="$1"; grep -qi '<!doctype html' "$f"||return 10; grep -qi '<html' "$f"||return 11; grep -qi '<head' "$f"||return 12; grep -qi '<body' "$f"||return 13; grep -qi '</html>' "$f"||return 14; local js; js="$(sed -n '/<script\b/,/<\/script>/p' "$f"|sed '1d;$d')"; if [[ -n "$js" ]]&&command -v node >/dev/null 2>&1;then printf '%s\n' "$js">"$STATE/.validate.js"; node --check "$STATE/.validate.js" >/dev/null 2>&1||return 15;fi; local css; css="$(sed -n '/<style\b/,/<\/style>/p' "$f"|sed '1d;$d')"; [[ "$(printf '%s' "$css"|tr -cd '{'|wc -c)" == "$(printf '%s' "$css"|tr -cd '}'|wc -c)" ]]||return 16; return 0; }
validate_file(){ local f="$1" ext rc=0; [[ -f "$f" ]]||die "file not found: $f"; ext="${f##*.}"; case "$ext" in sh|bash) bash -n "$f";; js|mjs|cjs) command -v node >/dev/null 2>&1||die node required; node --check "$f";; json) jq empty "$f";; html|htm) validate_html "$f";; css) [[ "$(tr -cd '{' <"$f"|wc -c)" == "$(tr -cd '}'<"$f"|wc -c)" ]];; *) return 0;; esac; rc=$?; if ((rc==0));then jq -cn --arg path "$f" --arg ext "$ext" '{path:$path,extension:$ext,status:"valid",diagnostics:"static syntax/structure gate passed"}';else jq -cn --arg path "$f" --arg ext "$ext" --argjson rc "$rc" '{path:$path,extension:$ext,status:"invalid",exitCode:$rc}';fi; return "$rc"; }
extract_html(){ local src="$1"; sed -n '/<!doctype html>/I,/<\/html>/Ip' "$src"; }
webkit_prompt(){ local request="$*"; [[ -n "$request" ]]||die 'webkit requires a prompt'; local backend="$(resolve_backend)" model="$MODEL"; [[ "$backend" == ollama&&-z "$model" ]]&&model="$(select_ollama_model coder)"; [[ "$backend" == llama ]]&&model="$LLAMA_MODEL"; local prompt; prompt=$(cat<<EOF
Act as a WebKit-compatible HTML5 coder agent.
Build ONE complete standalone HTML5 document for this request:
$request

Hard contract:
- output only HTML, beginning with <!doctype html>
- embedded CSS and JavaScript only
- no markdown fences, prose, bundler, server, module loader or external network dependency
- standards-based APIs compatible with modern WebKit/Safari
- responsive layout and functional interactions
- use requestAnimationFrame for animation loops
- escape dynamic user data before DOM insertion
- never execute shell commands from browser JavaScript
- no pseudocode or TODO placeholders
EOF
); local tmp="$(mktemp)" out="$STATE/webkit.html"; backend_generate "$backend" "$prompt" "$tmp" 424242 "$model"||die "generation failed: $(tail -n 5 "$tmp.stderr" 2>/dev/null)"; extract_html "$tmp">"$out"; [[ -s "$out" ]]||cp "$tmp" "$out"; local round=0; while ((round<3));do if validate_html "$out";then cp "$out" "$BASE/ai-generated-$(date +%Y%m%d-%H%M%S).html"; cat "$out"; rm -f "$tmp"; return 0;fi; round=$((round+1)); fix_file "$out" "Repair this HTML5 document so it passes the static WebKit/HTML5 gate. Preserve all intended features. Return the complete document only." || break; done; rm -f "$tmp"; die 'generated HTML did not pass validation'; }
fix_file(){ local f="$1" request="${2:-Repair syntax and preserve behavior.}"; [[ -f "$f" ]]||die "file not found: $f"; local backend="$(resolve_backend)" model="$MODEL"; [[ "$backend" == ollama&&-z "$model" ]]&&model="$(select_ollama_model coder)"; [[ "$backend" == llama ]]&&model="$LLAMA_MODEL"; local source="$(cat "$f")" prompt; prompt=$(cat<<EOF
You are a strict local code repair agent.
Repair the following source according to this request:
$request

Rules:
- preserve intent and public behavior
- return ONLY the complete corrected file
- do not add dependencies unless required by the file type
- do not execute commands
- keep security boundaries intact

SOURCE:
$source
EOF
); local tmp="$(mktemp)"; backend_generate "$backend" "$prompt" "$tmp" 818181 "$model"||die "repair generation failed"; local repaired="$tmp".clean; if [[ "${f##*.}" =~ html?|htm ]];then extract_html "$tmp">"$repaired";else sed '/^```/d' "$tmp">"$repaired";fi; validate_file "$repaired" >/dev/null || { warn "repair still fails validation"; rm -f "$tmp" "$repaired"; return 1; }; cp -a "$f" "$f.ai-before-fix.$(date +%s)"; mv "$repaired" "$f"; index_file "$f"; printf '%s\n' "$f"; rm -f "$tmp"; }

# -----------------------------------------------------------------------------
# Ollama bridges / diagnostics / reference
# -----------------------------------------------------------------------------
cmd_models(){ refresh_tags||die "Ollama unavailable"; jq -r '.models[]?|[.name,.size,.modified_at]|@tsv' "$installed_cache"; }
cmd_ps(){ api /api/ps|jq -r '.models[]?|[.name,.size,.size_vram,.context_length,.expires_at]|@tsv'; }
cmd_show(){ api /api/show -d "$(jq -nc --arg n "$1" '{name:$n}')"|jq .; }
cmd_pull(){ api /api/pull -H 'Content-Type: application/json' -d "$(jq -nc --arg n "$1" '{name:$n,stream:false}')"|jq .; }
cmd_delete(){ api /api/delete -H 'Content-Type: application/json' -d "$(jq -nc --arg n "$1" '{name:$n}')"|jq .; }
cmd_copy(){ api /api/copy -H 'Content-Type: application/json' -d "$(jq -nc --arg s "$1" --arg d "$2" '{source:$s,destination:$d}')"|jq .; }
reference(){ if llama_available;then "$LLAMA_BIN" --help>"$REFS/llama-help.txt" 2>&1||true; "$LLAMA_BIN" cli -h>"$REFS/llama-cli-help.txt" 2>&1||true; fi; if ollama_up;then api /api/version>"$REFS/ollama-version.json" 2>/dev/null||true; api /api/tags>"$REFS/ollama-tags.json" 2>/dev/null||true;fi; jq -n --arg backend "$BACKEND" --arg at "$(now)" '{type:"runtime-reference",backend:$backend,capturedAt:$at}'; }
doctor(){ local b=unavailable; if llama_available;then b=llama;elif ollama_up;then b=ollama;fi; printf 'version=%s\nbackend=%s\nbash=%s\njq=%s\ncurl=%s\nllama=%s\nollama=%s\ngemini=%s\nram_available_gb=%s\nram_total_gb=%s\nthreads=%s\nviews=%s\nparallel=%s\n' "$VERSION" "$b" "$BASH_VERSION" "$(jq --version)" "$(curl --version|head -1)" "$(command -v "$LLAMA_BIN" 2>/dev/null||echo missing)" "$(ollama_up&&echo up||echo down)" "$(gemini_available&&echo configured||echo missing)" "$(ram_avail_gb)" "$(ram_total_gb)" "$THREADS" "$VIEWS" "$(parallel_limit)"; }

usage(){ cat<<EOF
ai-fusion.sh $VERSION — llama.cpp + Ollama local agent fusion

CORE
  run PROMPT | prompt PROMPT       2PI/8 multiview execution
  "PROMPT"                         bare prompt compatibility
  doctor                           runtime/RAM/backend diagnostics
  reference                        capture local runtime references
  status                           state summary
  parse DATA                       parse @key=value envelope
  rank DATA                        token entropy/weight ranking
  index DIR                        SHA256 project index
  trace HASH                      lineage lookup

BACKENDS
  --backend auto|llama|ollama|gemini
  --auto                           backend auto-detection
  --model MODEL                   explicit backend model
  --ollama-model MODEL            Ollama default
  --models | --ps | --show MODEL
  --pull MODEL | --delete MODEL | --copy OLD NEW
  gemini-models | agents | agent-get ID | agent-delete ID | agent-create JSON
  gemini-get ID | gemini-poll ID | gemini-delete ID | functions | resume-function ...
  file-search-stores | file-search-create NAME | file-search-upload STORE FILE | file-search-delete NAME | file-search-query STORE PROMPT

PERFORMANCE
  --views N                       1..8 perspectives (default 8)
  --parallel N                    bounded concurrent views (default auto, max 4)
  --threads N                     llama threads (default 8)
  --ctx N                         llama context
  --gpu-layers N                  llama GPU layers
  --temp N --top-p N --top-k N
  --no-synthesis                  skip final synthesis
  --json | --schema FILE          structured output (Ollama/Gemini)
  --file FILE | --image FILE      file/document/multimodal input
  --unload                         unload Ollama model after run
  --generation-config FILE         Gemini generation_config JSON
  --tools FILE                     Gemini function/tool declarations JSON
  --background                     Gemini background interaction
  --agent AGENT                    Gemini managed agent
  --agent-config FILE              inline agent_config JSON
  --environment remote|ENV_ID      Gemini agent environment
  --stream                          stream Gemini Interactions SSE
  --show-steps                     show typed Interaction steps
  --system TEXT                    managed-agent system instruction
  --environment-json FILE           managed-agent environment object JSON
  --google-search                   enable Gemini google_search tool
  --google-maps                     enable Gemini google_maps grounding
  --code-execution                  enable Gemini code_execution tool
  --url-context                     enable Gemini url_context tool
  --computer-use                    enable Gemini computer_use tool where supported
  --image-output                    request image-only Gemini output
  --audio-output                    request audio/TTS output
  --video-output                    request video output
  --music-output                    request music/audio output using configured Lyria model
  --image-size SIZE                 Gemini image size (1K/2K/4K where supported)
  --aspect-ratio RATIO              image/video aspect ratio
  --video-resolution RES             video resolution (360p/720p/1080p/4k where supported)
  --thinking-level LEVEL             Gemini thinking level: minimal|low|medium|high
  --service-tier TIER                Gemini inference tier: standard|flex|priority
  --timeout SEC

CODER AGENT
  webkit PROMPT                   generate standalone HTML5/WebKit artifact
  fix FILE [REQUEST]              AI repair + validate + atomic replacement
  validate FILE                   static syntax/HTML/CSS validation
  artifact FILE                   hash/size/provenance record

FILES
  crud create|read|write|append|delete PATH [TEXT]
  --file FILE                    use file as prompt
  --image FILE                   Ollama vision input
  --session NAME
  --reset
  --verbose

ENV
  AI_BACKEND=auto|llama|ollama|gemini
  GEMINI_API_KEY=... AI_GEMINI_MODEL=gemini-3.7-flash
  GEMINI_UPLOAD_BASE_URL=https://generativelanguage.googleapis.com/upload/v1beta
  AI_GEMINI_AGENT=antigravity-preview-05-2026
  AI_GEMINI_IMAGE_MODEL=gemini-3.1-flash-image
  AI_GEMINI_AUDIO_MODEL=gemini-3.1-flash-tts-preview AI_GEMINI_VIDEO_MODEL=gemini-omni-flash-preview
  AI_GEMINI_MUSIC_MODEL=lyria-3-clip-preview
  AI_GEMINI_RESEARCH_AGENT=deep-research-preview-04-2026
  AI_GEMINI_STORE=true AI_GEMINI_STATEFUL=true AI_GEMINI_THINKING_LEVEL= AI_GEMINI_SERVICE_TIER=standard
  AI_MODEL=Qwen/Qwen2.5-Coder-3B-Instruct-GGUF
  AI_OLLAMA_MODEL=qwen3.5:4b
  OLLAMA_HOST=http://127.0.0.1:11434
  AI_VIEWS=8 AI_PARALLEL=0 AI_THREADS=8 AI_CTX=4096
EOF
}
status(){ jq -cn --arg v "$VERSION" --arg b "$BACKEND" --arg gm "$GEMINI_MODEL" --arg ga "$GEMINI_AGENT" --arg llama "$LLAMA_BIN" --arg om "$OLLAMA_HOST" --arg g "$(genesis_current)" --argjson views "$VIEWS" --argjson threads "$THREADS" --argjson parallel "$(parallel_limit)" '{name:"loopshape-ai-fusion",version:$v,backend:$b,geminiModel:$gm,geminiAgent:$ga,llama:$llama,ollama:$om,genesisHash:$g,views:$views,threads:$threads,parallel:$parallel}'; }
artifact(){ local f="$1"; [[ -f "$f" ]]||die "file not found"; local h="$(sha256_file "$f")" m="$(md5_text "$(cat "$f")")" b="$(wc -c<"$f"|awk '{print $1}')"; append_json artifacts "$(jq -cn --arg p "$f" --arg sha "$h" --arg md5 "$m" --arg g "$(genesis_current)" --argjson b "$b" '{path:$p,sha256:$sha,md5:$md5,genesisHash:$g,bytes:$b,at:now|todate}')"; jq -n --arg p "$f" --arg sha "$h" --arg md5 "$m" --argjson b "$b" '{path:$p,sha256:$sha,md5:$md5,bytes:$b}'; }
trace(){ local q="$1"; [[ -n "$q" ]]||die trace requires hash; jq -c --arg q "$q" 'select((.id//"")|startswith($q) or (.parentHash//"")|startswith($q) or (.genesisHash//"")|startswith($q) or (.originHash//"")|startswith($q))' "$DB/traces.jsonl" 2>/dev/null||true; }

# -----------------------------------------------------------------------------
# CLI
# -----------------------------------------------------------------------------
[[ $# -eq 0 ]]&&{ usage; exit 0; }
cmd="$1"; shift
case "$cmd" in
  -h|--help|help) usage;;
  -v|--version|version) echo "$VERSION";;
  doctor) doctor;; status) status;; reference) reference;;
  agents) gemini_agents | jq .;;
  agent-get) gemini_agent_get "${1:-}" | jq .;;
  agent-delete) gemini_agent_delete "${1:-}" | jq .;;
  agent-create) gemini_agent_create "${1:-}" | jq .;;
  gemini-models) gemini_list_models | jq -r ".models[]? | [.name,.displayName] | @tsv";;
  upload) gemini_upload_cmd "${1:-}";;
  file-search-stores) gemini_file_search_stores | jq .;;
  file-search-create) gemini_file_search_create "${1:-}" "${2:-}" | jq .;;
  file-search-delete) gemini_file_search_delete "${1:-}" | jq .;;
  file-search-upload) gemini_file_search_upload "${1:-}" "${2:-}" | jq .;;
  file-search-query) gemini_file_search_query "${1:-}" "${*:2}";;
  research) gemini_research "$*" "${AI_RESEARCH_AGENT:-$GEMINI_RESEARCH_AGENT}";;
  research-max) gemini_research "$*" "${AI_RESEARCH_AGENT:-$GEMINI_RESEARCH_MAX_AGENT}";;
  gemini-get) gemini_get "${1:-}" | jq .;;
  gemini-poll) gemini_poll "${1:-}" "${2:-5}" | jq .;;
  gemini-delete) gemini_delete "${1:-}" | jq .;;
  functions) jq -c . "$DB/tool-calls.jsonl" 2>/dev/null || true;;
  resume-function) gemini_function_resume "${1:-}" "${2:-}" "${3:-}" "${4:-{}}";;
  models|--models) ollama_up||die "Ollama unavailable"; cmd_models;;
  ps|--ps) ollama_up||die "Ollama unavailable"; cmd_ps;;
  show|--show) ollama_up||die "Ollama unavailable"; cmd_show "${1:?model}";;
  pull|--pull) ollama_up||die "Ollama unavailable"; cmd_pull "${1:?model}";;
  delete|--delete) ollama_up||die "Ollama unavailable"; cmd_delete "${1:?model}";;
  copy|--copy) ollama_up||die "Ollama unavailable"; cmd_copy "${1:?source}" "${2:?destination}";;
  ram|--ram) printf 'available_gb=%s\ntotal_gb=%s\n' "$(ram_avail_gb)" "$(ram_total_gb)";;
  model-list) printf '%-40s %-10s %-8s %-8s %-5s %-5s\n' MODEL CLASS GB CTX VIS TOOLS; printf '%s\n' "${MODELS[@]}"|awk -F'|' '{printf "%-40s %-10s %-8s %-8s %-5s %-5s\n",$1,$2,$3,$4,$5,$6}';;
  parse) parse_envelope "$*"; pm="${MODEL:-$LLAMA_MODEL}"; [[ "$BACKEND" == gemini ]] && pm="${MODEL:-$(gemini_model_for_task "$(classify_task "$PROMPT")")}"; jq -n --arg b "$BACKEND" --arg m "$pm" --arg a "$AGENT" --arg f "$FORMAT" --arg p "$PROMPT" --argjson v "$VIEWS" '{backend:$b,model:$m,agent:$a,format:$f,views:$v,prompt:$p}';;
  rank) local_data="$*"; [[ -n "$local_data" ]]||local_data="$(cat)"; genesis_current>/dev/null; rank_tokens "$local_data"|sort -t$'\t' -k5,5nr;;
  index) index_dir "${1:-$BASE}";;
  trace) trace "${1:-}";;
  artifact) artifact "${1:-}";;
  crud) crud "${1:-}" "${2:-}" "${*:3}";;
  validate) validate_file "${1:-}";;
  fix) fix_file "${1:-}" "${*:2}";;
  webkit|html|html5|build-html) webkit_prompt "$*";;
  agent) mode="${1:-}";shift||true; case "$mode" in --mode) mode="${1:-}";shift;; esac; case "$mode" in webkit) webkit_prompt "$*";; fix) fix_file "${1:-}" "${*:2}";; validate) validate_file "${1:-}";; gemini|antigravity|deep-research) BACKEND=gemini; AGENT="$GEMINI_AGENT"; [[ "$mode" == deep-research ]]&&AGENT="$GEMINI_RESEARCH_AGENT"; ENVIRONMENT="${ENVIRONMENT:-remote}"; run_prompt "$*";; *) die 'agent mode: webkit|fix|validate|gemini|antigravity|deep-research';; esac;;
  run|prompt) # option-aware prompt mode
    while (($#));do case "$1" in --backend) BACKEND="${2:?backend}";shift 2;; --gemini) BACKEND=gemini;shift;; --auto) BACKEND=auto;shift;; --model|-m) MODEL="${2:?model}";EXPLICIT=1;shift 2;; --ollama-model) OLLAMA_MODEL="${2:?model}";shift 2;; --views) VIEWS="${2:?views}";shift 2;; --parallel) PARALLEL="${2:?parallel}";shift 2;; --threads) THREADS="${2:?threads}";shift 2;; --ctx) CTX="${2:?ctx}";shift 2;; --gpu-layers) GPU_LAYERS="${2:?layers}";shift 2;; --temp) TEMP="${2:?temp}";shift 2;; --top-p) TOP_P="${2:?top-p}";shift 2;; --top-k) TOP_K="${2:?top-k}";shift 2;; --think) THINK="${2:?think}";shift 2;; --session) SESSION="${2:?session}";shift 2;; --no-synthesis) SYNTHESIS=false;shift;; --timeout) TIMEOUT="${2:?timeout}";shift 2;; --stream) STREAM=1;shift;; --file) UPLOAD_FILE="${2:?file}"; PROMPT="$(cat "$UPLOAD_FILE")";shift 2;; --image) local_img="${2:?image}"; [[ -f "$local_img" ]]||die "image not found: $local_img"; UPLOAD_FILE="$local_img"; MIME_TYPE="$(gemini_mime "$local_img")"; if command -v base64 >/dev/null 2>&1;then IMAGE_B64="["$(base64 -w0 "$local_img" 2>/dev/null || base64 "$local_img"|tr -d '\n')"]"; fi; shift 2;; --json) FORMAT=json;shift;; --schema) FORMAT=schema;SCHEMA_FILE="${2:?schema}";shift 2;; --generation-config) GENERATION_CONFIG_FILE="${2:?generation-config}";shift 2;; --tools) TOOLS_FILE="${2:?tools}";shift 2;; --background) BACKGROUND=1;shift;; --agent) AGENT="${2:?agent}";BACKEND=gemini;shift 2;; --agent-config) AGENT_CONFIG_FILE="${2:?agent config}";BACKEND=gemini;shift 2;; --system) AGENT_SYSTEM="${2:?system instruction}";shift 2;; --environment) ENVIRONMENT="${2:?environment}";shift 2;; --environment-json) ENVIRONMENT_JSON_FILE="${2:?environment json}";shift 2;; --google-search) enable_gemini_tool google_search;shift;; --google-maps) enable_gemini_tool google_maps;shift;; --code-execution) enable_gemini_tool code_execution;shift;; --url-context) enable_gemini_tool url_context;shift;; --computer-use) enable_gemini_tool computer_use;shift;; --image-output) FORMAT=image;BACKEND=gemini;shift;; --audio-output) FORMAT=audio;BACKEND=gemini;shift;; --video-output) FORMAT=video;BACKEND=gemini;shift;; --music-output) FORMAT=audio;MUSIC_OUTPUT=1;BACKEND=gemini;shift;; --image-size) IMAGE_SIZE="${2:?image size}";shift 2;; --aspect-ratio) IMAGE_ASPECT_RATIO="${2:?aspect ratio}";VIDEO_ASPECT_RATIO="$IMAGE_ASPECT_RATIO";shift 2;; --video-resolution) VIDEO_RESOLUTION="${2:?video resolution}";shift 2;; --thinking-level) GEMINI_THINKING_LEVEL="${2:?thinking level}";shift 2;; --service-tier) GEMINI_SERVICE_TIER="${2:?service tier}";shift 2;; --show-steps) SHOW_STEPS=1;shift;; --show-thinking) SHOW_THINKING=1;shift;; --unload) UNLOAD=1;KEEP_ALIVE=0;shift;; --verbose|-v) VERBOSE=1;shift;; --) shift;break;; *) break;; esac;done; [[ -n "$PROMPT" ]]||PROMPT="$*"; run_prompt "$PROMPT"; rc=$?; if ((UNLOAD))&&[[ "$(resolve_backend 2>/dev/null || echo '')" == ollama ]];then curl -fsS --connect-timeout 2 --max-time 10 "$OLLAMA_HOST/api/generate" -H 'Content-Type: application/json' -d "$(jq -nc --arg m "${MODEL:-$OLLAMA_MODEL}" '{model:$m,prompt:"",keep_alive:0}')" >/dev/null 2>&1||true;fi; exit "$rc";;
  llama) llama_available||die 'llama binary missing'; "$LLAMA_BIN" "$@";;
  cli) llama_available||die 'llama binary missing'; "$LLAMA_BIN" cli "$@";;
  gemini) BACKEND=gemini; run_prompt "$*";;
  *) run_prompt "$cmd ${*:-}";;
esac
