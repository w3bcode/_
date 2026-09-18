#!/usr/bin/env bash

# STREAMING_CHUNK:Setting up script configuration and variables...
# ==============================================================================
# Llama-CLI Tripod Orchestrator
# A bash wrapper managing a Python forwarder, Node.js proxy, and llama-cli.
# ==============================================================================

set -euo pipefail

# ANSI Colors for logging
C_CYAN='\033[1;36m'
C_MAGENTA='\033[1;35m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[1;31m'
C_RESET='\033[0m'

# Configuration
TEMP_DIR=$(mktemp -d)
NODE_SCRIPT="$TEMP_DIR/tripod_orchestrator.js"
PYTHON_SCRIPT="$TEMP_DIR/reloop_forwarder.py"
MODEL_PATH="${MODEL_PATH:-models/llama-2-7b-chat.gguf}" # Default path, can be overridden via env
PROMPT="${1:-"Hello, tell me a short story."}"

# STREAMING_CHUNK:Defining cleanup and logging functions...
cleanup() {
    log_info "Cleaning up temporary files in $TEMP_DIR"
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

log_info() {
    echo -e "${C_CYAN}[INFO]${C_RESET} $1"
}

log_error() {
    echo -e "${C_RED}[ERROR]${C_RESET} $1" >&2
}

log_step() {
    echo -e "\n${C_MAGENTA}>>> $1${C_RESET}"
}

# STREAMING_CHUNK:Generating the Node.js Tripod Orchestrator script...
generate_node_script() {
    log_info "Generating Node.js Tripod script..."
    cat << 'EOF' > "$NODE_SCRIPT"
const { spawn } = require('child_process');
const readline = require('readline');

const args = process.argv.slice(2);
const modelPath = args[0];
const promptText = args[1];

if (!modelPath || !promptText) {
    console.error("Usage: node tripod_orchestrator.js <model_path> <prompt>");
    process.exit(1);
}

// Ensure llama-cli is available or mock it for demonstration if not found
const command = 'llama-cli'; 
const llamaArgs = ['-m', modelPath, '-p', promptText, '-n', '128'];

console.log(`[Tripod-JS] Spawning: ${command} ${llamaArgs.join(' ')}`);

const llamaProcess = spawn(command, llamaArgs);

llamaProcess.stdout.on('data', (data) => {
    // Process output, maybe add formatting or metadata
    const output = data.toString().trim();
    if(output) {
        process.stdout.write(`[Tripod-JS-Out] ${output}\n`);
    }
});

llamaProcess.stderr.on('data', (data) => {
    // Suppress verbose llama.cpp loading logs, only show actual errors if needed
    const output = data.toString();
    if(output.toLowerCase().includes('error')) {
         process.stderr.write(`[Tripod-JS-Err] ${output}\n`);
    }
});

llamaProcess.on('close', (code) => {
    console.log(`\n[Tripod-JS] Process exited with code ${code}`);
    process.exit(code);
});

llamaProcess.on('error', (err) => {
    console.error(`[Tripod-JS] Failed to start llama-cli: ${err.message}`);
    console.error("[Tripod-JS] Ensure llama.cpp is installed and in your PATH.");
    process.exit(1);
});
EOF
}

# STREAMING_CHUNK:Generating the Python Reloop Forwarder script...
generate_python_script() {
    log_info "Generating Python Reloop Forwarder script..."
    cat << 'EOF' > "$PYTHON_SCRIPT"
import sys
import subprocess
import argparse

def main():
    parser = argparse.ArgumentParser(description="Reloop Forwarder for Llama Tripod")
    parser.add_argument("--node-script", required=True, help="Path to Node.js script")
    parser.add_argument("--model", required=True, help="Path to GGUF model")
    parser.add_argument("--prompt", required=True, help="Prompt text")
    
    args = parser.parse_args()

    print(f"[Py-Forwarder] Initializing Reloop protocol for model: {args.model}")
    print(f"[Py-Forwarder] Forwarding prompt: '{args.prompt}'")

    cmd = ["node", args.node_script, args.model, args.prompt]
    
    try:
        # Run the node process, piping stdout/stderr
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1
        )

        # Stream output line by line
        for line in process.stdout:
            print(f"[Py-Stream] {line.strip()}")
            
        # Catch any remaining errors
        _, stderr = process.communicate()
        if process.returncode != 0:
            print(f"[Py-Error] Node process failed with code {process.returncode}", file=sys.stderr)
            if stderr:
                print(stderr.strip(), file=sys.stderr)
            sys.exit(process.returncode)
            
    except FileNotFoundError:
        print("[Py-Error] Node.js is not installed or not in PATH.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"[Py-Error] Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF
}

# STREAMING_CHUNK:Executing the orchestration pipeline...
main() {
    clear
    log_step "Initializing Llama Tripod Environment"
    log_info "Model Path: $MODEL_PATH"
    log_info "Prompt: $PROMPT"

    # Pre-flight checks
    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed. Please install it to continue."
        exit 1
    fi
    if ! command -v python3 &> /dev/null; then
        log_error "Python3 is not installed. Please install it to continue."
        exit 1
    fi

    # Check if llama-cli exists, provide warning if not
    if ! command -v llama-cli &> /dev/null; then
         echo -e "${C_YELLOW}[WARNING] llama-cli not found in PATH. The Node.js layer will likely fail to execute the model.${C_RESET}"
         echo -e "${C_YELLOW}[WARNING] Ensure you have built llama.cpp and added it to your PATH.${C_RESET}"
    fi

    generate_node_script
    generate_python_script

    log_step "Launching Reloop Forwarder Pipeline"
    
    # Execute the Python forwarder, which calls Node, which calls llama-cli
    python3 "$PYTHON_SCRIPT" \
        --node-script "$NODE_SCRIPT" \
        --model "$MODEL_PATH" \
        --prompt "$PROMPT"
        
    log_step "Orchestration Complete"
}

main
