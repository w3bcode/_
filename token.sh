#!/usr/bin/env bash
# =============================================================================
# token.sh - Thread-Parallelized 2Pi/8 Double-Buffer Token Engine
# =============================================================================
set -Eeuo pipefail

AI_HOME="${AI_HOME:-${HOME}/.ai}"
FRAME_DIR="${AI_HOME}/.ai-state/frames"
mkdir -p "$FRAME_DIR"

execute_vector_frame_pipeline() {
    python3 - "$1" <<'EOF'
import sys
import math
import json
import hashlib
from concurrent.futures import ThreadPoolExecutor

raw_tokenstream = sys.argv[1]

def rol32(value: int, shift: int) -> int:
    shift %= 32
    return ((value << shift) & 0xFFFFFFFF) | ((value & 0xFFFFFFFF) >> (32 - shift))

def process_sector_thread(sector_args):
    k, chunk_tokens = sector_args
    angle_deg = k * 45
    angle_rad = k * (math.pi / 4.0)
    chunk_str = " ".join(chunk_tokens)

    sha_digest = hashlib.sha256(chunk_str.encode('utf-8')).hexdigest()
    sha_seed32 = int(sha_digest[:8], 16)
    rotated_val = rol32(sha_seed32, k)

    magnitude = math.sqrt(rotated_val % 1_000_000)
    phase_xor_match = (rotated_val ^ (k * 0x2A)) & 0xFFFFFFFF

    return {
        "sector": k,
        "angle": f"{angle_deg}°",
        "rad": round(angle_rad, 4),
        "seed": hex(sha_seed32),
        "rol_token": hex(rotated_val),
        "bound_magnitude": round(magnitude, 4),
        "vector_bound_match": hex(phase_xor_match),
        "chunk": chunk_str
    }

# Split into 8 polar chunks
tokens = raw_tokenstream.split()
chunk_size = max(1, math.ceil(len(tokens) / 8.0))
segmented_chunks = [tokens[i:i + chunk_size] for i in range(0, len(tokens), chunk_size)]

while len(segmented_chunks) < 8:
    segmented_chunks.append(["<PAD_VECTOR>"])
segmented_chunks = segmented_chunks[:8]

# Dispatch 8 parallel sector evaluation threads
worker_payloads = [(k, segmented_chunks[k]) for k in range(8)]

with ThreadPoolExecutor(max_workers=8) as executor:
    aligned_vector_bounds = list(executor.map(process_sector_thread, worker_payloads))

aligned_vector_bounds.sort(key=lambda x: x["sector"])

output_telemetry = {
    "execution_mode": "THREADED_PARALLEL_2PI_8_SWEEP",
    "active_threads": 8,
    "segmented_vectors": aligned_vector_bounds
}

print(json.dumps(output_telemetry, indent=2))
EOF
}

main() {
    local prompt_input="${1:-}"
    if [[ -z "$prompt_input" ]]; then
        echo "Usage: $0 \"<tokenstream_prompt_string>\"" >&2
        exit 1
    fi
    execute_vector_frame_pipeline "$prompt_input"
}

main "$@"
