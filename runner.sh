#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_DIR="/home/loop/_"
WORKER="$TARGET_DIR/bin/unattended_worker.sh"
PID_FILE="$TARGET_DIR/worker.pid"
FIFO_PIPE="$TARGET_DIR/fifo/prompt.fifo"

case "${1:-status}" in
    start)
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "Worker already running (PID: $(cat "$PID_FILE"))"
        else
            nohup "$WORKER" >/dev/null 2>&1 &
            echo $! > "$PID_FILE"
            echo "Unattended AI worker started (PID: $!)"
        fi
        ;;
    stop)
        if [[ -f "$PID_FILE" ]]; then
            kill "$(cat "$PID_FILE")" 2>/dev/null || true
            rm -f "$PID_FILE"
            echo "Worker stopped."
        else
            echo "Worker not running."
        fi
        ;;
    push)
        shift
        prompt="$*"
        if [[ -z "$prompt" ]]; then
            echo "Usage: ./runner.sh push \"Prompt text\""
            exit 1
        fi
        echo "$prompt" > "$FIFO_PIPE"
        echo "Prompt queued -> $FIFO_PIPE"
        ;;
    status)
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "Worker ACTIVE (PID: $(cat "$PID_FILE"))"
        else
            echo "Worker INACTIVE"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|status|push \"prompt\"}"
        ;;
esac
