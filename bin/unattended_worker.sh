#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_DIR="/home/loop/_"
AI_BIN="$TARGET_DIR/bin/ai.sh"
FIFO_PIPE="$TARGET_DIR/fifo/prompt.fifo"
TARGET_HTML="$TARGET_DIR/dist/genesis_app.html"
LOG_FILE="$TARGET_DIR/logs/worker.log"

export AI_HOME="${AI_HOME:-$HOME/.ai}"

exec 3<>"$FIFO_PIPE"

printf "[%s] Worker daemon active. Listening on %s\n" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$FIFO_PIPE" >> "$LOG_FILE"

while true; do
    if read -t 2 -r prompt <&3; then
        prompt="$(echo "$prompt" | xargs)"
        [[ -z "$prompt" ]] && continue

        printf "[%s] Processing prompt: %s\n" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$prompt" >> "$LOG_FILE"

        # Execute via ai.sh engine
        if [[ -x "$AI_BIN" ]]; then
            output="$("$AI_BIN" run "$prompt" 2>>"$LOG_FILE" || true)"
        else
            output="Error: AI engine binary missing at $AI_BIN"
        fi

        # Compute payload Hash
        hash="$(printf '%s|%s' "$(date +\%s)" "$output" | sha256sum | awk '{print $1}')"

        # Inject result into single-file HTML5 DOM
        python3 - "$TARGET_HTML" "$hash" "$output" <<'PYEOF'
import sys
html_path, node_hash, raw_payload = sys.argv[1], sys.argv[2], sys.argv[3]
with open(html_path, 'r', encoding='utf-8') as f:
    content = f.read()

clean_payload = raw_payload.replace('\\', '\\\\').replace('`', '\\`').replace('$', '\\$')
injection = f"\n<script>window.appendRealtimeNode(`{node_hash}`, `{clean_payload}`);</script>\n</body>"

if '</body>' in content:
    updated = content.replace('</body>', injection)
else:
    updated = content + injection

with open(html_path, 'w', encoding='utf-8') as f:
    f.write(updated)
PYEOF

        printf "[%s] Processed HASH: %s\n" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$hash" >> "$LOG_FILE"
    fi
done
