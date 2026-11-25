#!/bin/bash
# ============================================================
#  Start Minecraft server inside a named tmux session
#  Usage: ./start-server.sh
# ============================================================

SESSION_NAME="minecraft"
SERVER_DIR="$HOME/minecraft"
JAR_FILE="paper.jar"
MIN_RAM="1G"
MAX_RAM="3G"

# Check if session already exists
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "Server is already running in tmux session '${SESSION_NAME}'."
    echo "Attach with: tmux attach -t ${SESSION_NAME}"
    exit 1
fi

echo "Starting Minecraft server in tmux session '${SESSION_NAME}'..."

tmux new-session -d -s "$SESSION_NAME" -c "$SERVER_DIR" \
    "java -Xms${MIN_RAM} -Xmx${MAX_RAM} -jar ${JAR_FILE} nogui"

echo "Server started! Attach with: tmux attach -t ${SESSION_NAME}"
echo "Detach with: Ctrl+B then D"
