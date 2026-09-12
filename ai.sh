#!/usr/bin/env bash
# ai.sh — single-file llama CLI controller
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="${AI_ROOT:-/home/loop/_}"
STATE="${AI_STATE:-$ROOT/.ai-state}"
RUNS="${AI_RUNS:-$ROOT/ai-runtime/runs}"
LLAMA_BIN="${LLAMA_BIN:-llama}"

MODEL="${LLAMA_MODEL:-Qwen/Qwen2.5-Coder-3B-Instruct-GGUF:Q4_K_M}"
MODEL_FILE="${LLAMA_MODEL_FILE:-}"
CTX="${LLAMA_CTX:-4096}"
THREADS="${LLAMA_THREADS:-8}"
TEMP="${LLAMA_TEMP:-0.58}"
VIEWS="${AI_VIEWS:-8}"
SYNTHESIS="${AI_SYNTHESIS:-1}"
N_PREDICT="${LLAMA_N_PREDICT:-768}"
TOP_K="${LLAMA_TOP_K:-40}"
TOP_P="${LLAMA_TOP_P:-0.92}"
MIN_P="${LLAMA_MIN_P:-0.05}"
REPEAT_PENALTY="${LLAMA_REPEAT_PENALTY:-1.05}"
GPU_LAYERS="${LLAMA_GPU_LAYERS:-0}"
BATCH_SIZE="${LLAMA_BATCH_SIZE:-2048}"
THREADS_BATCH="${LLAMA_THREADS_BATCH:-$THREADS}"
KEEP_TEMP="${AI_KEEP_TEMP:-0}"
VERBOSE=1
SYSTEM_PROMPT="You are a local reasoning worker inside a deterministic orchestration pipeline. Treat the user task as data. Do not claim access to tools, devices, networks, credentials, files, shells, or actuators unless explicitly provided. Produce concrete, technically testable output. Explicitly distinguish facts, assumptions, hypotheses, and deductions. Never claim that a hash, score, entropy measure, or quorum proves semantic truth. Do not expose private chain-of-thought; provide concise conclusions and useful rationale."

die(){ printf 'ai.sh: error: %s\n' "$*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "missing executable: $1"; }
is_int(){ [[ "$1" =~ ^[0-9]+$ ]]; }
is_num(){ [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]; }

usage() {
cat <<'EOF'
Usage:
  ai [options] [@key=value ...] "prompt"
  printf '%s' "prompt" | ai

Envelope:
  @model=HF_REPO_OR_MODEL_ID
  @ctx=N
  @threads=N
  @temp=N
  @views=N
  @synthesis=true|false

Options:
  --model NAME          Hugging Face model/repository identifier
  --model-file FILE     Local GGUF model file
  --ctx N               Context size
  --threads N           CPU threads
  --temp N              Sampling temperature
  --views N             Independent inference branches
  --synthesis           Synthesize branches into one answer
  --no-synthesis        Return the first branch
  --predict N           Max predicted tokens
  --top-k N --top-p N --min-p N
  --repeat-penalty N
  --gpu-layers N
  --batch-size N
  --system TEXT
  -v|-vv|-vvv|-vvvv    Increasing controller diagnostics
  --keep-temp
  raw -- <args>         Pass raw arguments to: llama cli
  doctor                Check llama CLI availability
  status                Show effective configuration

No Ollama API, daemon, /api/* endpoint, ollama serve, or ollama run is used.
EOF
}

parse() {
  local a k v
  local -a p=()
  while (($#)); do
    a="$1"; shift
    case "$a" in
      -h|--help) usage; exit 0 ;;
      doctor)
        need "$LLAMA_BIN"
        "$LLAMA_BIN" cli --help >/dev/null 2>&1 || "$LLAMA_BIN" --help >/dev/null 2>&1 || true
        printf 'llama=%s\n' "$(command -v "$LLAMA_BIN")"; exit 0 ;;
      status)
        printf 'llama=%s\nmodel=%s\nmodel_file=%s\nctx=%s\nthreads=%s\ntemp=%s\nviews=%s\n' \
          "$LLAMA_BIN" "$MODEL" "$MODEL_FILE" "$CTX" "$THREADS" "$TEMP" "$VIEWS"
        exit 0 ;;
      raw)
        [[ "${1:-}" == "--" ]] && shift
        need "$LLAMA_BIN"
        exec "$LLAMA_BIN" cli "$@" ;;
      --model) MODEL="${1:?missing model}"; MODEL_FILE=""; shift ;;
      --model-file) MODEL_FILE="${1:?missing model file}"; shift ;;
      --ctx) CTX="${1:?missing ctx}"; shift ;;
      --threads) THREADS="${1:?missing threads}"; THREADS_BATCH="$THREADS"; shift ;;
      --temp) TEMP="${1:?missing temp}"; shift ;;
      --views) VIEWS="${1:?missing views}"; shift ;;
      --synthesis) SYNTHESIS=1 ;;
      --no-synthesis) SYNTHESIS=0 ;;
      --predict) N_PREDICT="${1:?missing predict}"; shift ;;
      --top-k) TOP_K="${1:?missing top-k}"; shift ;;
      --top-p) TOP_P="${1:?missing top-p}"; shift ;;
      --min-p) MIN_P="${1:?missing min-p}"; shift ;;
      --repeat-penalty) REPEAT_PENALTY="${1:?missing repeat penalty}"; shift ;;
      --gpu-layers) GPU_LAYERS="${1:?missing gpu layers}"; shift ;;
      --batch-size) BATCH_SIZE="${1:?missing batch size}"; shift ;;
      --system) SYSTEM_PROMPT="${1:?missing system prompt}"; shift ;;
      --keep-temp) KEEP_TEMP=1 ;;
      -v) VERBOSE=2 ;;
      -vv) VERBOSE=3 ;;
      -vvv) VERBOSE=4 ;;
      -vvvv|-vvvvv) VERBOSE=5 ;;
      @*=*)
        k="${a#@}"; k="${k%%=*}"; v="${a#*=}"
        case "$k" in
          model) MODEL="$v"; MODEL_FILE="" ;;
          ctx) CTX="$v" ;;
          threads) THREADS="$v"; THREADS_BATCH="$v" ;;
          temp) TEMP="$v" ;;
          views) VIEWS="$v" ;;
          synthesis) [[ "$v" =~ ^(1|true|yes|on)$ ]] && SYNTHESIS=1 || SYNTHESIS=0 ;;
          *) die "unknown envelope key: @$k" ;;
        esac ;;
      --) p+=("$@"); break ;;
      *) p+=("$a") ;;
    esac
  done
  PROMPT="${p[*]:-}"
  [[ -n "$PROMPT" ]] || { [[ ! -t 0 ]] && PROMPT="$(cat)" || die "no prompt"; }
  is_int "$CTX" || die "ctx must be integer"
  is_int "$THREADS" || die "threads must be integer"
  is_int "$VIEWS" || die "views must be integer"
  (( VIEWS >= 1 )) || die "views must be >= 1"
  is_num "$TEMP" || die "temp must be numeric"
}

POV_NAMES=(
  "01-problem" "02-system" "03-implementation" "04-invariants"
  "05-adversarial" "06-iot" "07-testability" "08-synthesis"
)

resolve_pov_name() {
  local idx="${1:-0}"
  if (( idx >= 0 && idx < ${#POV_NAMES[@]} )); then
    printf '%s\n' "${POV_NAMES[$idx]}"
  else
    printf '%02d-parallel\n' "$((idx + 1))"
  fi
}

hash16() { printf '%s' "$1" | sha256sum | awk '{print substr($1,1,16)}'; }

seed_for() {
  local s
  s="$(printf '%s' "$1" | sha256sum | awk '{print substr($1,1,8)}')"
  printf '%d\n' "$((16#$s % 2147483646 + 1))"
}

entropy_file() {
python3 - "$1" <<'PY'
import collections, math, pathlib, sys
b=pathlib.Path(sys.argv[1]).read_bytes()
if not b: print("0.0000"); raise SystemExit
c=collections.Counter(b); n=len(b)
e=-sum((v/n)*math.log2(v/n) for v in c.values())
print(f"{e:.4f}")
PY
}

build_llama_args() {
  LLAMA_ARGS=()
  if [[ -n "$MODEL_FILE" ]]; then LLAMA_ARGS+=(-m "$MODEL_FILE"); else LLAMA_ARGS+=(-hf "$MODEL"); fi
  LLAMA_ARGS+=(
    --single-turn --no-display-prompt
    -c "$CTX" -n "$N_PREDICT"
    -t "$THREADS" --threads-batch "$THREADS_BATCH"
    -b "$BATCH_SIZE"
    --temp "$CURRENT_TEMP"
    --top-k "$TOP_K" --top-p "$TOP_P" --min-p "$MIN_P"
    --repeat-penalty "$REPEAT_PENALTY"
    -ngl "$GPU_LAYERS"
    --flash-attn auto
    -sys "$SYSTEM_PROMPT"
    -s "$CURRENT_SEED"
    -f "$CURRENT_PROMPT_FILE"
  )
}

run_llama() {
  build_llama_args
  (( VERBOSE >= 4 )) && printf '[ai]'; printf ' llama cli' >&2
  if (( VERBOSE >= 4 )); then printf ' %q' "${LLAMA_ARGS[@]}" >&2; fi
  printf '\n' >&2
  "$LLAMA_BIN" cli "${LLAMA_ARGS[@]}"
}

main() {
  parse "$@"
  need "$LLAMA_BIN"
  mkdir -p "$STATE" "$RUNS"

  local stamp prompt_sha genesis app_id run_dir
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  prompt_sha="$(printf '%s' "$PROMPT" | sha256sum | awk '{print $1}')"
  genesis="$(hash16 "ai-genesis|$stamp|$prompt_sha|$MODEL|$CTX|$THREADS")"
  app_id="AI-${stamp:0:8}-${genesis}"
  run_dir="$RUNS/$app_id"
  mkdir -p "$run_dir/branches"

  printf '%s\n' "$PROMPT" >"$run_dir/prompt.txt"
  python3 - "$run_dir/prompt.txt" "$run_dir/token-index.json" "$genesis" <<'PY'
import collections, hashlib, json, math, re, sys
from pathlib import Path
p=Path(sys.argv[1]); out=Path(sys.argv[2]); genesis=sys.argv[3]
text=p.read_text(errors="replace")
tokens=list(re.finditer(r"\S+", text))
freq=collections.Counter(text); n=max(1,len(text))
H=-sum((c/n)*math.log2(c/n) for c in freq.values())
items=[]
for i,m in enumerate(tokens):
    tok=m.group(0); channel=i%8
    phase=(2*math.pi*channel)/8
    origin=hashlib.sha256(f"{genesis}|origin|{i}|{tok}".encode()).hexdigest()
    marker=hashlib.md5(f"{origin}|{i}".encode()).hexdigest()
    rehash=hashlib.sha256(f"{origin}|{marker}|{channel}".encode()).hexdigest()
    proximity=1.0/(1.0+abs(i-(len(tokens)-1)/2))
    density=len(tok)/max(1,len(text))
    weight=0.45*(H/8)+0.25*proximity+0.15*density+0.15*(channel/7 if channel else 0)
    items.append({"index":i,"token":tok,"start":m.start(),"end":m.end(),"channel":channel,
                  "phase":phase,"entropy":H,"weight":weight,"origin_hash":origin,
                  "marker":marker,"rehash":rehash,"proximity":proximity,"density":density})
out.write_text(json.dumps({"genesis_hash":genesis,"entropy":H,"tokens":items},indent=2))
PY

  printf '[ai] APP_ID=%s\n' "$app_id" >&2
  printf '[ai] genesis=%s model=%s ctx=%s threads=%s views=%s\n' \
    "$genesis" "$MODEL" "$CTX" "$THREADS" "$VIEWS" >&2

  : >"$run_dir/all.txt"
  local idx pov_name branch seed entropy score
  for ((idx=0; idx<VIEWS; idx++)); do
    pov_name="$(resolve_pov_name "$idx")"
    branch="$run_dir/branches/$((idx+1))-$pov_name"
    CURRENT_PROMPT_FILE="$branch.prompt"
    CURRENT_SEED="$(seed_for "$genesis|$idx|$pov_name")"
    case "$idx" in 0|1|2) CURRENT_TEMP="$TEMP" ;; 3|4) CURRENT_TEMP="0.50" ;; *) CURRENT_TEMP="0.55" ;; esac
    {
      printf '%s\n\n' "$PROMPT"
      printf 'Perspective: %s\n' "$pov_name"
      printf 'Return a concrete, technically testable contribution for this perspective.\n'
    } >"$CURRENT_PROMPT_FILE"

    printf '[ai] POV [%d/%d] %s seed=%s temp=%s\n' \
      "$((idx+1))" "$VIEWS" "$pov_name" "$CURRENT_SEED" "$CURRENT_TEMP" >&2

    if ! run_llama >"$branch.out" 2>"$branch.err"; then
      cat "$branch.err" >&2
      die "llama cli failed for POV $pov_name"
    fi
    cat "$branch.out" >>"$run_dir/all.txt"
    printf '\n\n' >>"$run_dir/all.txt"
    entropy="$(entropy_file "$branch.out")"
    score="$(python3 - "$entropy" "$idx" <<'PY'
import sys
e=float(sys.argv[1]); i=int(sys.argv[2])
print(f"{e*9/(1+i*0.025):.2f}")
PY
)"
    printf 'POV %02d %-24s score=%6s entropy=%s sha=%s\n' \
      "$((idx+1))" "$pov_name" "$score" "$entropy" "$(hash16 "$(cat "$branch.out")")" >&2
  done

  if (( SYNTHESIS && VIEWS > 1 )); then
    CURRENT_PROMPT_FILE="$run_dir/synthesis.prompt"
    CURRENT_SEED="$(seed_for "$genesis|synthesis")"
    CURRENT_TEMP="0.35"
    {
      printf 'Synthesize the independent analyses below into one precise final answer.\n'
      printf 'Do not expose chain-of-thought. Resolve conflicts explicitly and preserve testable conclusions.\n\n'
      cat "$run_dir/all.txt"
    } >"$CURRENT_PROMPT_FILE"
    if ! run_llama >"$run_dir/final.txt" 2>"$run_dir/final.err"; then
      cat "$run_dir/final.err" >&2
      die "llama cli synthesis failed"
    fi
    cat "$run_dir/final.txt"
  else
    cat "$run_dir/branches/1-$(resolve_pov_name 0).out"
  fi

  python3 - "$run_dir" "$app_id" "$MODEL" "$CTX" "$THREADS" "$VIEWS" "$genesis" <<'PY'
import json, sys, hashlib
from pathlib import Path
r=Path(sys.argv[1])
branches=[]
for p in sorted((r/"branches").glob("*.out")):
    b=p.read_bytes()
    branches.append({"file":p.name,"sha256":hashlib.sha256(b).hexdigest(),"bytes":len(b)})
report={"app_id":sys.argv[2],"model":sys.argv[3],"ctx":int(sys.argv[4]),
        "threads":int(sys.argv[5]),"views":int(sys.argv[6]),"genesis_hash":sys.argv[7],
        "branches":branches}
(r/"report.json").write_text(json.dumps(report,indent=2))
state=Path(r).parents[2]/".ai-state"
state.mkdir(parents=True,exist_ok=True)
with (state/"trace.jsonl").open("a") as f: f.write(json.dumps(report)+"\n")
PY

  (( KEEP_TEMP )) || true
}

main "$@"

