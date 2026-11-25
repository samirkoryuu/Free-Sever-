#!/bin/bash
# ============================================================
#  Minecraft Server Auto-Backup Script
#  Backs up world, plugins, and configs → Google Drive via rclone
# ============================================================

# ---------------------- CONFIG ----------------------
SERVER_DIR="$HOME/minecraft"          # Where your server files live
BACKUP_DIR="$SERVER_DIR/backups"      # Local backup staging folder
TMUX_SESSION="minecraft"              # Name of your tmux session
RCLONE_REMOTE="gdrive"               # Name from `rclone config`
RCLONE_FOLDER="MinecraftBackups"     # Folder on Google Drive
LOCAL_KEEP_DAYS=7                     # Delete local backups older than this
REMOTE_KEEP_DAYS=7                    # Delete remote backups older than this
LOG_FILE="$BACKUP_DIR/backup.log"     # Log file path
# ----------------------------------------------------

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_NAME="mc-backup-${TIMESTAMP}.tar.gz"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Logging helper
log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "$LOG_FILE"
}

log "========== BACKUP STARTED =========="

# ---------------------- STEP 1: SAVE & PAUSE ----------------------
SERVER_RUNNING=false
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    SERVER_RUNNING=true
    log "Server is running in tmux session '${TMUX_SESSION}'. Flushing and pausing saves..."

    tmux send-keys -t "$TMUX_SESSION" "say §6[Backup] Starting automatic backup..." Enter
    sleep 1
    tmux send-keys -t "$TMUX_SESSION" "save-all" Enter
    sleep 10  # Give the server time to flush all chunks to disk
    tmux send-keys -t "$TMUX_SESSION" "save-off" Enter
    sleep 2

    log "World saving paused."
else
    log "WARNING: tmux session '${TMUX_SESSION}' not found. Backing up files as-is."
fi

# ---------------------- STEP 2: CREATE ARCHIVE ----------------------
log "Creating backup archive: ${BACKUP_NAME}"

cd "$SERVER_DIR" || { log "ERROR: Cannot cd to ${SERVER_DIR}"; exit 1; }

# Back up: world data, plugins, and all config files
tar -czf "$BACKUP_PATH" \
    --exclude='backups' \
    --exclude='cache' \
    --exclude='libraries' \
    --exclude='versions' \
    --exclude='logs' \
    --exclude='*.jar' \
    --exclude='.git' \
    --exclude='plugins/*/cache' \
    --exclude='plugins/*/libs' \
    --exclude='plugins/Geyser-Spigot/locales' \
    world/ \
    plugins/ \
    server.properties \
    bukkit.yml \
    spigot.yml \
    commands.yml \
    whitelist.json \
    ops.json \
    banned-ips.json \
    banned-players.json \
    usercache.json \
    wepif.yml \
    config/ \
    2>&1 | tee -a "$LOG_FILE"

BACKUP_SIZE=$(du -h "$BACKUP_PATH" | cut -f1)
log "Backup archive created: ${BACKUP_SIZE}"

# ---------------------- STEP 3: RESUME SAVING ----------------------
if [ "$SERVER_RUNNING" = true ]; then
    tmux send-keys -t "$TMUX_SESSION" "save-on" Enter
    sleep 1
    tmux send-keys -t "$TMUX_SESSION" "say §a[Backup] Backup complete! (${BACKUP_SIZE})" Enter
    log "World saving resumed."
fi

# ---------------------- STEP 4: UPLOAD TO GOOGLE DRIVE ----------------------
log "Uploading to Google Drive: ${RCLONE_REMOTE}:${RCLONE_FOLDER}/"

if command -v rclone &>/dev/null; then
    rclone copy "$BACKUP_PATH" "${RCLONE_REMOTE}:${RCLONE_FOLDER}/" --log-file="$LOG_FILE" --log-level INFO
    if [ $? -eq 0 ]; then
        log "Upload successful."
    else
        log "ERROR: rclone upload failed! Check log for details."
    fi
else
    log "ERROR: rclone is not installed! Backup saved locally only."
fi

# ---------------------- STEP 5: CLEANUP OLD BACKUPS ----------------------
# Local cleanup
DELETED_LOCAL=$(find "$BACKUP_DIR" -name "mc-backup-*.tar.gz" -mtime +${LOCAL_KEEP_DAYS} -delete -print | wc -l)
log "Cleaned up ${DELETED_LOCAL} local backup(s) older than ${LOCAL_KEEP_DAYS} days."

# Remote cleanup (delete files older than REMOTE_KEEP_DAYS on Google Drive)
if command -v rclone &>/dev/null; then
    rclone delete "${RCLONE_REMOTE}:${RCLONE_FOLDER}/" --min-age "${REMOTE_KEEP_DAYS}d" --log-file="$LOG_FILE" --log-level INFO
    log "Cleaned up remote backups older than ${REMOTE_KEEP_DAYS} days."
fi

log "========== BACKUP FINISHED ==========="
log ""
