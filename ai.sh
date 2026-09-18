#!/usr/bin/env bash
# ============================================================================
# ai.sh - Upgradable Calculus Orchestrator & Tokenstream Wrapper
# ============================================================================
set -euo pipefail

# Self-Update Stub (Upgradable syntax)
# Uncomment and configure repository to enable self-patching
if [[ "${1:-}" == "--update" ]]; then
    git pull origin main && exec "$0" "$@"
fi

# Environment Bootstrapping
if [[ -f "$HOME/.env.local" ]]; then
    source "$HOME/.env.local"
fi

# Configuration & Permissioned Group State
STATE_DIR="/tmp/ai_orchestrator"
STATE_FILE="$STATE_DIR/timeline_state.json"
GROUP_OWNER="staff" # Adjust to your local permissioned group (e.g., in Termux/proot)

mkdir -p "$STATE_DIR"
if [[ ! -f "$STATE_FILE" ]]; then
    echo '{"interactions": []}' > "$STATE_FILE"
fi

# Enforce secure state path permissions
chown ":$GROUP_OWNER" "$STATE_FILE" || true
chmod 660 "$STATE_FILE"

# Regex-String Validation
# Validates alphanumeric, standard punctuation, and URLs (http/https)
PROMPT="${1:-}"
REGEX="^[a-zA-Z0-9 \.\,\?\!\:\/\-\_\=\+\%\&\#]+$"

if [[ ! "$PROMPT" =~ $REGEX ]]; then
    echo "[ERROR] Invalid regex-string parsed. Token stream rejected to prevent injection." >&2
    exit 1
fi

echo "[INFO] Prompt validated. Routing to calculus orchestrator..."

# Execute Python 3 Orchestrator
python3 orchestrator.py "$PROMPT" "$STATE_FILE"

