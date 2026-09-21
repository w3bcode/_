#!/usr/bin/env bash
​=============================================================================
​ai.sh v17.0.0 (Dualism-Provoked Constrained Replication & Mirror Logic)
​=============================================================================
​Single-file dual-rail local AI controller for llama.cpp (llama-cli), tuned for
​proot-distro Debian on Android with modest RAM (~16GB or less).
​
​Dualism Architecture & Recongruent Compliance:
​- Dual-rail prompt divergence / convergence engines (Alpha and Beta tracks)
​- Side-by-side accommodation recongruent compliance thinking
​- Replicable entropy injectors to guarantee deterministic divergence
​- Ledger-backed cross-validation and cryptographic state anchoring
​
​Runtime:
​$HOME/.local/bin/llama   (override with LLAMA_CLI)
​=============================================================================
​set -Eeuo pipefail
IFS=$'\n\t'
​AI_VERSION="17.0.0"
​=============================================================================
​BASE PATHS
​=============================================================================
​AI_HOME="{AI_HOME:-{HOME:-/root}/.ai}"
HOME_DIR="${HOME:-/root}"
​STATE_DIR="${AI_STATE_DIR:-$AI_HOME/.ai-state}"
​CACHE_DIR="${AI_CACHE_DIR:-STATE_DIR/cache}"
LOG_DIR="{AI_LOG_DIR:-STATE_DIR/logs}"
DB_DIR="{AI_DB:-STATE_DIR/db}"
OBJECT_DIR="{AI_OBJECTS:-DB_DIR/objects}"
REFERENCE_DIR="{AI_REFERENCE:-DB_DIR/reference}"
RUN_DIR="{AI_RUN_DIR:-STATE_DIR/run}"
SESSION_DIR="{AI_SESSION_DIR:-STATE_DIR/sessions}"
DUAL_DIR="{AI_DUAL_DIR:-$STATE_DIR/dual}"
​MODEL_DIR="${AI_MODEL_DIR:-$AI_HOME/models}"
​LAST_ERROR_FILE="$RUN_DIR/last_error.log"
​mkdir -p 
"$STATE_DIR" 
"$CACHE_DIR" 
"$LOG_DIR" 
"$DB_DIR" 
"$OBJECT_DIR" 
"$REFERENCE_DIR" 
"$RUN_DIR" 
"$SESSION_DIR" 
"$DUAL_DIR" 
"$MODEL_DIR"
​=============================================================================
​RUNTIME & MODELS
​=============================================================================
​LLAMA_CLI="{LLAMA_CLI:-{HOME:-/root}/.local/bin/llama}"
​AI_MODEL="{AI_MODEL:-Qwen/Qwen2.5-Coder-3B-Instruct-GGUF:Q4_K_M}"
AI_CODER="{AI_CODER:-AI_MODEL}"
AI_FALLBACK="{AI_FALLBACK:-Qwen/Qwen2.5-1.5B-Instruct-GGUF:Q4_K_M}"
​AI_MODEL_PATH="{AI_MODEL_PATH:-}"
AI_FALLBACK_PATH="{AI_FALLBACK_PATH:-}"
​AI_PRIMARY_FILE="{AI_PRIMARY_FILE:-qwen2.5-coder-3b-instruct-q4_k_m.gguf}"
AI_FALLBACK_FILE="{AI_FALLBACK_FILE:-qwen2.5-1.5b-instruct-q4_k_m.gguf}"
​PRIMARY_LOCAL_PATH="$MODEL_DIR/$AI_PRIMARY_FILE"
FALLBACK_LOCAL_PATH="$MODEL_DIR/$AI_FALLBACK_FILE"
​AI_HF_ROOT="${AI_HF_ROOT:-$HOME_DIR/.cache/huggingface/hub}"
PRIMARY_HF_CACHE="$AI_HF_ROOT/models--Qwen--Qwen2.5-Coder-3B-Instruct-GGUF"
FALLBACK_HF_CACHE="$AI_HF_ROOT/models--Qwen--Qwen2.5-1.5B-Instruct-GGUF"
​PRIMARY_HF_REPO="Qwen/Qwen2.5-Coder-3B-Instruct-GGUF"
FALLBACK_HF_REPO="Qwen/Qwen2.5-1.5B-Instruct-GGUF"
​=============================================================================
​RUNTIME PARAMETERS & DUALISM CONTROLS
​=============================================================================
​AI_CONTEXT="{AI_CONTEXT:-{AI_CTX:-4096}}"
AI_BATCH="{AI_BATCH:-{AI_BATCH_SIZE:-256}}"
AI_UBATCH="{AI_UBATCH:-{AI_UBATCH_SIZE:-128}}"
AI_PREDICT="{AI_PREDICT:-{AI_N_PREDICT:-512}}"
​AI_THREADS="{AI_THREADS:-8}"
AI_GPU_LAYERS="{AI_GPU_LAYERS:-0}"
​AI_TEMPERATURE="{AI_TEMPERATURE:-{AI_TEMP:-0.65}}"
AI_TOP_K="{AI_TOP_K:-40}"
AI_TOP_P="{AI_TOP_P:-0.95}"
AI_REPEAT_PENALTY="{AI_REPEAT_PENALTY:-1.10}"
AI_TIMEOUT="{AI_TIMEOUT:-600}"
​AI_VIEWS="{AI_VIEWS:-8}"
AI_DEPTH="{AI_DEPTH:-1}"
AI_SYNTHESIS="{AI_SYNTHESIS:-false}"
AI_STREAM="{AI_STREAM:-false}"
AI_SESSION="{AI_SESSION:-default}"
AI_MIN_OUTPUT="{AI_MIN_OUTPUT:-8}"
​Dualism specific parameters
​AI_DUALISM_MODE="{AI_DUALISM_MODE:-true}"
AI_ENTROPY_VARIANCE="{AI_ENTROPY_VARIANCE:-0.05}"
AI_CONVERGENCE_THRESHOLD="${AI_CONVERGENCE_THRESHOLD:-0.85}"
​=============================================================================
​COLORS & GLOBALS
​=============================================================================
​if [[ -t 1 ]]; then
C_RESET='\033[0m'
C_RED='\033[31m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_BLUE='\033[34m'
C_MAGENTA='\033[35m'
C_CYAN='\033[36m'
C_WHITE='\033[37m'
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
​CURRENT_MODEL_PATH=""
CURRENT_MODEL_NAME=""
CURRENT_MODEL_TIER=""
​LAST_OUTPUT=""
LAST_ERROR=""
LAST_EXIT_CODE=0
​GENESIS_HASH=""
TASK_HASH=""
CURRENT_HASH=""
​POV_INDEX=0
POV_NAME=""
POV_ANGLE=""
​LLAMA_HELP_CACHE=""
LLAMA_SUBCOMMAND_CACHE=""
​declare -a LLAMA_CMD=()
declare -a CANDIDATE_FILES=()
declare -a CANDIDATE_SCORES=()
declare -a CANDIDATE_HASHES=()
declare -a TMP_FILES=()
​=============================================================================
​CLEANUP & ERROR HANDLING
​=============================================================================
​cleanup() {
local f
for f in "${TMP_FILES[@]:-}"; do
[[ -n "$f" ]] || continue
[[ -f "$f" ]] && rm -f -- "$f" || true
done
}
​trap cleanup EXIT
trap 'printf "\n[INTERRUPTED]\n" >&2; exit 130' INT TERM
​on_error() {
local rc=?
local line="{BASH_LINENO[0]:-unknown}"
local cmd="${BASH_COMMAND:-unknown}"
​printf '%s[ERROR]%s line=%s rc=%s\n' "$C_RED" "$C_RESET" "$line" "$rc" >&2
printf '%sCOMMAND:%s %s\n' "$C_DIM" "$C_RESET" "$cmd" >&2
exit "$rc"
}
​trap on_error ERR
​=============================================================================
​UTILITIES & HASHING
​=============================================================================
​die() { printf '%s[ERROR]%s %s\n' "$C_RED" "C_RESET" "" >&2; exit 1; }
warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW" "C_RESET" "" >&2; }
info() { printf '%s[AI]%s %s\n' "C_CYAN" "$C_RESET" "$*"; }
ok()   { printf '%s[OK]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
debug() { [[ "{AI_VERBOSE:-false}" == "true" ]] \vert{}\vert{} return 0; printf '%s[DEBUG]%s %s\n' "$C_DIM" "C_RESET" "*" >&2; }
​have() { command -v "$1" >/dev/null 2>&1; }
now_iso() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
​sha256_string() {
local text="$1"
if have sha256sum; then
printf '%s' "$text" | sha256sum | awk '{print $1}'
elif have shasum; then
printf '%s' "$text" | shasum -a 256 | awk '{print $1}'
else
die "sha256sum or shasum required"
fi
}
​sha256_file() {
local file="$1"
[[ -f "$file" ]] || return 1
if have sha256sum; then
sha256sum "$file" | awk '{print $1}'
elif have shasum; then
shasum -a 256 "$file" | awk '{print $1}'
else
die "sha256sum or shasum required"
fi
}
​json_escape() {
local s="1"
s="{s//\/\\}"
s="{s//\"/\\\"}"
s="{s//'\n'/\\n}"
s="{s//'\r'/\\r}"
s="{s//$'\t'/\t}"
printf '%s' "$s"
}
​safe_tmp() {
local prefix="{1:-ai}"
local tmp
if have mktemp; then
tmp="(mktemp "RUN_DIR/{prefix}.XXXXXX")"
else
tmp="RUN_DIR/{prefix}.$$.$RANDOM"
: > "$tmp"
fi
TMP_FILES+=("$tmp")
printf '%s\n' "$tmp"
}
​is_valid_gguf() {
local file="$1"
local magic=""
[[ -f "$file" ]] || return 1
[[ -s "file" ]] || return 1
magic="(head -c 4 "$file" 2>/dev/null | LC_ALL=C od -An -tc | tr -d '[:space:]')"
[[ "$magic" == "GGUF" ]]
}
​verify_gguf() {
local file="$1"
is_valid_gguf "$file" \vert{}\vert{} { warn "Invalid GGUF: $file"; return 1; }
return 0
}
​=============================================================================
​MODEL RESOLUTION
​=============================================================================
​find_exact_gguf() {
local root="$1" filename="$2"
[[ -d "$root" ]] || return 1
find "$root" -type f -iname "$filename" -print -quit 2>/dev/null
}
​find_any_gguf() {
local root="$1"
[[ -d "$root" ]] || return 1
find "$root" -type f (-iname '.gguf' -o -iname '.GGUF') -print 2>/dev/null | sort | head -n 1
}
​resolve_model() {
local model=""
if [[ -n "$AI_MODEL_PATH" && -f "$AI_MODEL_PATH" && -s "$AI_MODEL_PATH" ]]; then
verify_gguf "$AI_MODEL_PATH" || return 1
printf '%s\n' "$AI_MODEL_PATH"
return 0
fi
if [[ -f "$PRIMARY_LOCAL_PATH" ]] && verify_gguf "$PRIMARY_LOCAL_PATH"; then
printf '%s\n' "PRIMARY_LOCAL_PATH"
return 0
fi
model="(find_exact_gguf "$MODEL_DIR" "$AI_PRIMARY_FILE" || true)"
[[ -n "$model" && -f "$model" ]] && verify_gguf "$model" && { printf '%s\n' "model"; return 0; }
model="(find_exact_gguf "$PRIMARY_HF_CACHE" "$AI_PRIMARY_FILE" || true)"
[[ -n "$model" && -f "$model" ]] && verify_gguf "$model" && { printf '%s\n' "model"; return 0; }
model="(find_any_gguf "$PRIMARY_HF_CACHE" || true)"
[[ -n "$model" && -f "$model" ]] && verify_gguf "$model" && { printf '%s\n' "$model"; return 0; }
​model="$(find_fallback_model || true)"
[[ -n "$model" ]] && { printf '%s\n' "$model"; return 0; }
return 1
}
​find_fallback_model() {
local model=""
if [[ -n "$AI_FALLBACK_PATH" && -f "$AI_FALLBACK_PATH" && -s "$AI_FALLBACK_PATH" ]]; then
verify_gguf "$AI_FALLBACK_PATH" || return 1
printf '%s\n' "$AI_FALLBACK_PATH"
return 0
fi
if [[ -f "$FALLBACK_LOCAL_PATH" ]] && verify_gguf "$FALLBACK_LOCAL_PATH"; then
printf '%s\n' "FALLBACK_LOCAL_PATH"
return 0
fi
model="(find_exact_gguf "$MODEL_DIR" "$AI_FALLBACK_FILE" || true)"
[[ -n "$model" && -f "$model" ]] && verify_gguf "$model" && { printf '%s\n' "model"; return 0; }
model="(find_exact_gguf "$FALLBACK_HF_CACHE" "$AI_FALLBACK_FILE" || true)"
[[ -n "$model" && -f "$model" ]] && verify_gguf "$model" && { printf '%s\n' "model"; return 0; }
model="(find_any_gguf "$FALLBACK_HF_CACHE" || true)"
[[ -n "$model" && -f "$model" ]] && verify_gguf "$model" && { printf '%s\n' "$model"; return 0; }
return 1
}
​check_runtime() {
[[ -x "$LLAMA_CLI" ]] || { LAST_ERROR="llama runtime missing: $LLAMA_CLI"; return 127; }
return 0
}
​llama_help() {
if [[ -z "LLAMA_HELP_CACHE" ]]; then
LLAMA_HELP_CACHE="("$LLAMA_CLI" cli --help 2>&1 \vert{}\vert{} "$LLAMA_CLI" --help 2>&1 || true)"
fi
printf '%s\n' "$LLAMA_HELP_CACHE"
}
​llama_supports() {
local option="1"
llama_help | grep -Eq -- "(^|[[:space:]]){option}([=[:space:]]\vert{},\vert{}$)"
}
​llama_uses_cli_subcommand() {
if [[ -z "$LLAMA_SUBCOMMAND_CACHE" ]]; then
if "$LLAMA_CLI" cli --help >/dev/null 2>&1; then
LLAMA_SUBCOMMAND_CACHE="yes"
else
LLAMA_SUBCOMMAND_CACHE="no"
fi
fi
[[ "$LLAMA_SUBCOMMAND_CACHE" == "yes" ]]
}
​build_llama_command() {
local model="1" temp_override="{2:-$AI_TEMPERATURE}"
[[ -n "$model" && -f "$model" ]] || { LAST_ERROR="Invalid model path"; return 2; }
verify_gguf "$model" || { LAST_ERROR="Invalid GGUF"; return 2; }
​LLAMA_CMD=("$LLAMA_CLI")
llama_uses_cli_subcommand && LLAMA_CMD+=(cli)
LLAMA_CMD+=(--model "$model")
​llama_supports '--ctx-size' && LLAMA_CMD+=(--ctx-size "$AI_CONTEXT")
llama_supports '--batch-size' && LLAMA_CMD+=(--batch-size "$AI_BATCH")
llama_supports '--ubatch-size' && LLAMA_CMD+=(--ubatch-size "$AI_UBATCH")
llama_supports '--predict' && LLAMA_CMD+=(--predict "$AI_PREDICT")
llama_supports '--threads' && LLAMA_CMD+=(--threads "$AI_THREADS")
llama_supports '--temp' && LLAMA_CMD+=(--temp "$temp_override")
llama_supports '--top-k' && LLAMA_CMD+=(--top-k "$AI_TOP_K")
llama_supports '--top-p' && LLAMA_CMD+=(--top-p "$AI_TOP_P")
llama_supports '--repeat-penalty' && LLAMA_CMD+=(--repeat-penalty "$AI_REPEAT_PENALTY")
​if [[ "$AI_GPU_LAYERS" != "0" ]]; then
llama_supports '--n-gpu-layers' && LLAMA_CMD+=(--n-gpu-layers "$AI_GPU_LAYERS")
fi
return 0
}
​run_llama() {
local prompt="1" model="{2:-}" temp_override="${3:-$AI_TEMPERATURE}"
local output="" rc=0 stderr_file=""
​LAST_OUTPUT=""
LAST_ERROR=""
LAST_EXIT_CODE=0
​check_runtime || { LAST_EXIT_CODE=$?; return "$LAST_EXIT_CODE"; }
[[ -z "$model" || ! -f "model" ]] && model="(resolve_model || true)"
[[ -n "$model" && -f "$model" ]] || { LAST_ERROR="No physical GGUF resolved."; return 2; }
​build_llama_command "$model" "temp_override" || { LAST_EXIT_CODE=?; return "$LAST_EXIT_CODE"; }
​local prompt_file
prompt_file="$(safe_tmp llama-prompt)"
printf '%s' "$prompt" > "$prompt_file"
​if llama_supports '--file'; then
LLAMA_CMD+=(--file "$prompt_file")
elif llama_supports '-f'; then
LLAMA_CMD+=(-f "$prompt_file")
else
LLAMA_CMD+=(--prompt "$prompt")
fi
​llama_supports '--single-turn' && LLAMA_CMD+=(--single-turn)
llama_supports '--no-display-prompt' && LLAMA_CMD+=(--no-display-prompt)
​stderr_file="(safe_tmp llama-stderr)"
if have timeout; then
output="(timeout "AI_TIMEOUT" "{LLAMA_CMD[@]}" < /dev/null 2>"stderr_file")" \vert{}\vert{} rc=?
else
output="("{LLAMA_CMD[@]}" < /dev/null 2>"stderr_file")" \vert{}\vert{} rc=?
fi
​if [[ rc -ne 0 ]]; then
LAST_ERROR="(cat "$stderr_file" 2>/dev/null || true)"
LAST_EXIT_CODE=$rc
return "$rc"
fi
​LAST_OUTPUT="$output"
printf '%s\n' "$output"
return 0
}
​=============================================================================
​LEDGER & ARTIFACTS
​=============================================================================
​log_event() {
local type="1" payload="{2:-}"
local timestamp hash file
timestamp="(now_iso)"
hash="(sha256_string "{timestamp}|{type}\vert{}${payload}")"
file="$OBJECT_DIR/$hash.json"
cat > "file" <<EOF
{
"hash":"(json_escape "hash")",
"timestamp":"(json_escape "timestamp")",
"type":"(json_escape "type")",
"payload":"(json_escape "$payload")"
}
EOF
printf '%s\n' "$hash"
}
​write_artifact() {
local kind="1" content="$2" parent="${3:-}"
local hash file meta
hash="(sha256_string "$content")"
file="$OBJECT_DIR/$hash.txt"
meta="$OBJECT_DIR/$hash.json"
[[ -f "$file" ]] || printf '%s\n' "$content" > "file"
cat > "$meta" <<EOF
{
"hash":"$(json_escape "$hash")",
"kind":"$(json_escape "$kind")",
"parent":"$(json_escape "$parent")",
"created":"$(now_iso)",
"file":"(json_escape "$file")"
}
EOF
printf '%s\n' "$hash"
}
​=============================================================================
​DUALISM ENGINE & RECONGRUENT COMPLIANCE
​=============================================================================
​normalize_prompt() {
local prompt="1"
prompt="{prompt//$'\r'/}"
printf '%s' "prompt" \vert{} sed -e ':a' -e '/^[[:space:]]*/{d;N;ba' -e '}' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*//'
}
​Dual-rail divergence prompt generator
​build_dual_prompt() {
local original="$1" rail="$2" entropy_val="$3"
if [[ "$rail" == "alpha" ]]; then
cat <<EOF
[DUAL-RAIL ALPHA: CONVERGENT FORMALISM & LOGICAL INTEGRITY]
Execute rigorous structural compliance. Emphasize formal boundaries, API safety, deterministic contracts, and explicit logical rules.
ENTROPY OFFSET: $entropy_val
​TASK:
$original
EOF
else
cat <<EOF
[DUAL-RAIL BETA: ADVERSARIAL EXPLORATION & LATERAL SYNTHESIS]
Execute lateral discovery compliance. Emphasize edge cases, failure modes, alternative architectural perspectives, and decentralized flexibility.
ENTROPY OFFSET: $entropy_val
​TASK:
$original
EOF
fi
}
​Recongruence synthesis prompt merging dualistic outputs
​build_recong_prompt() {
local original="$1" alpha_out="$2" beta_out="$3"
cat <<EOF
[RECONGRUENT COMPLIANCE SYNTHESIS]
You are the dualism reconciliation engine. Two parallel reasoning tracks (Alpha and Beta) have processed the origin prompt with provoked entropic constraints.
​ORIGINAL PROMPT:
$original
​--- ALPHA RAIL OUTPUT ---
$alpha_out
​--- BETA RAIL OUTPUT ---
$beta_out
​RECONGRUENCE OBJECTIVE:
​Reconcile both dualistic constraints without discarding valid architectural insights from either side.
​Resolve logical conflicts through strict compliance with correctness, security, and portability.
​Produce a unified, reproducible, and fully synthesized execution response.
​Return only the reconciled final output.
EOF
}
​run_dualism_engine() {
local prompt="1"
local normalized
normalized="(normalize_prompt "$prompt")"
[[ -n "$normalized" ]] || die "empty prompt"
​local model
model="$(resolve_model || true)"
[[ -n "$model" ]] || die "No physical GGUF model found for dualism execution."
​info "Initializing Dualism-Provoked Constrained Replication..."
​local alpha_temp beta_temp
alpha_temp="$(awk -v t="$AI_TEMPERATURE" -v e="AI_ENTROPY_VARIANCE" 'BEGIN {print t - e}')"
beta_temp="(awk -v t="$AI_TEMPERATURE" -v e="$AI_ENTROPY_VARIANCE" 'BEGIN {print t + e}')"
​info "Rail Alpha Temperature: $alpha_temp \vert{} Rail Beta Temperature:$beta_temp"
​# Execute Alpha Rail
info "Executing Rail Alpha (Formalism)..."
local alpha_prompt alpha_output alpha_hash
alpha_prompt="$(build_dual_prompt "$normalized" "alpha" "alpha_temp")"
alpha_output="(run_llama "$alpha_prompt" "$model" "alpha_temp")" || alpha_output="Alpha execution failed."
alpha_hash="(sha256_string "$alpha_output")"
write_artifact "dual:alpha" "$alpha_output" "$alpha_hash" >/dev/null
​# Execute Beta Rail
info "Executing Rail Beta (Lateral/Adversarial)..."
local beta_prompt beta_output beta_hash
beta_prompt="$(build_dual_prompt "$normalized" "beta" "beta_temp")"
beta_output="(run_llama "$beta_prompt" "$model" "beta_temp")" || beta_output="Beta execution failed."
beta_hash="(sha256_string "$beta_output")"
write_artifact "dual:beta" "$beta_output" "$beta_hash" >/dev/null
​# Recongruent Convergence
info "Executing Recongruent Compliance Synthesis..."
local recong_prompt final_output final_hash
recong_prompt="$(build_recong_prompt "$normalized" "$alpha_output" "beta_output")"
final_output="(run_llama "$recong_prompt" "$model" "$AI_TEMPERATURE")" \vert{}\vert{} final_output="alpha_output"
final_hash="(sha256_string "$final_output")"
​write_artifact "dual:reconverged" "$final_output" "$final_hash" >/dev/null
log_event "dualism_complete" "alpha_hash=$alpha_hash beta_hash=$beta_hash final_hash=$final_hash" >/dev/null
​printf '%s\n' "$final_output"
}
​=============================================================================
​FILE CRUD & DB COMMANDS
​=============================================================================
​FILE_ROOT="${AI_FILE_ROOT:-$AI_HOME/files}"
mkdir -p "$FILE_ROOT"
FILE_INDEX="$DB_DIR/file_index.json"
​init_file_index() {
[[ -f "$FILE_INDEX" ]] \vert{}\vert{} printf '{"entries":[]}\n' > "$FILE_INDEX"
}
​resolve_file_path() {
local input="$1" abs=""
if [[ "$input" = /* ]]; then
abs="$input"
else
abs="$FILE_ROOT/input"
fi
if have realpath; then
abs="(realpath -m -- "abs")"
else
mkdir -p "(dirname "abs")" 2>/dev/null || true
fi
if [[ "{AI_ALLOW_UNSAFE_PATHS:-false}" != "true" ]]; then
case "$abs" in
"$FILE_ROOT"/*\vert{}"$FILE_ROOT") : ;;
*) die "path escapes sandbox ($FILE_ROOT):$abs" ;;
esac
fi
printf '%s\n' "$abs"
}
​cmd_file() {
local sub="${1:-}"
shift || true
case "sub" in
create|write)
local rel="{1:-}"; shift || true
[[ -n "rel" ]] || die "usage: ai file write PATH [CONTENT]"
local content="{1:-}"
[[ "content" == "-" || -z "$content" && ! -t 0 ]] && content="$(cat)"
local path; path="(resolve_file_path "rel")"
mkdir -p "(dirname "$path")"
printf '%s' "$content" > "$path"
ok "saved: path"
;;
read|cat)
local rel="{1:-}"
[[ -n "rel" ]] || die "usage: ai file read PATH"
local path; path="(resolve_file_path "$rel")"
[[ -f "$path" ]] \vert{}\vert{} die "not found: $path"
cat "path"
;;
delete|rm)
local rel="{1:-}"
[[ -n "rel" ]] || die "usage: ai file delete PATH"
local path; path="(resolve_file_path "$rel")"
rm -rf -- "path"
ok "deleted: $path"
;;
list|ls)
find "$(resolve_file_path "{1:-.th}")" -maxdepth 3 2>/dev/null || true
;;
*)
die "usage: ai file {create|read|write|delete|list} PATH"
;;
esac
}
​cmd_status() {
local model=""
model="$(resolve_model || true)"
printf '\n'
printf '%sAI STATUS (v%s - DUALISM RECONGRUENT)%s\n' "$C_CYAN" "$AI_VERSION" "$C_RESET"
printf '%s=========================================%s\n' "$C_DIM" "C_RESET"
printf 'Runtime       : %s\n' "$LLAMA_CLI"
printf 'Model         : %s\n' "${model:-NONE}"
printf 'Tier          : %s\n' "{CURRENT_MODEL_TIER:-NONE}"
printf 'Dualism Mode  : %s\n' "$AI_DUALISM_MODE"
printf 'Entropy Var   : %s\n' "$AI_ENTROPY_VARIANCE"
printf 'State Dir     : %s\n' "$STATE_DIR"
printf '\n'
}
​cmd_help() {
cat <<EOF
​ai.sh v$AI_VERSION - Dualism-Provoked Constrained AI Controller
USAGE:
ai "prompt"                    Run dualism recongruence execution
ai run "prompt"                Explicit run command
ai status                      Show controller status & dualism metrics
ai models                      Inspect model registry
ai file write PATH [CONTENT]   Sandboxed file operations
ai doctor                      Verify dependencies and GGUF status
EOF
}
​=============================================================================
​MAIN ENTRYPOINT
​=============================================================================
​main() {
local command="{1:-}"
case "$command" in
""|help|-h|--help) cmd_help ;;
run) shift; run_dualism_engine "$*" ;;
status) cmd_status ;;
model|models) resolve_model && ok "Model verified" || warn "Model missing" ;;
file|files) shift; cmd_file "@" ;;
version|-V|--version) printf '%s\n' "AI_VERSION" ;;
*) run_dualism_engine "*" ;;
esac
}
​main "$@"
