#!/bin/bash

# Define strict internal absolute pathing matching your framework specs
SCRIPT_DIR="$HOME/_/qwen_cli"
SCRIPT_PATH="$SCRIPT_DIR/cli_chat_final.py"

# Enforce active working directory containment context
cd "$SCRIPT_DIR" || exit 1

# Provide clean fallbacks if arguments are empty
PROFILE=${1:-"standard"}

case "$PROFILE" in
    "code"|"coding"|"math")
        echo "🚀 Booting Qwen Engine [Profile: Precise/Deterministic]..."
        python "$SCRIPT_PATH" --temperature 0.1 --top-p 0.90 --context-window 4096
        ;;
    "creative"|"writer"|"brainstorm")
        echo "🎨 Booting Qwen Engine [Profile: Creative/Exploratory]..."
        python "$SCRIPT_PATH" --temperature 1.1 --top-p 0.98 --context-window 4096
        ;;
    "deep"|"long"|"8k")
        echo "🧠 Booting Qwen Engine [Profile: Deep Expanded Context]..."
        python "$SCRIPT_PATH" --temperature 0.7 --top-p 0.95 --context-window 8192
        ;;
    "cpu")
        echo "💻 Booting Qwen Engine [Profile: CPU Execution Mode]..."
        python "$SCRIPT_PATH" --gpu-layers 0
        ;;
    "standard"|"default"|*)
        echo "⚡ Booting Qwen Engine [Profile: Balanced Default]..."
        python "$SCRIPT_PATH" --temperature 0.7 --top-p 0.95 --context-window 4096
        ;;
esac
