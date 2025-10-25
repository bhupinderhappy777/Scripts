#!/usr/bin/env bash
set -euo pipefail
umask 0077

# daily_wsl_triple_backup.sh
# Simple wrapper that runs three sequential restic backups:
#  1) Local filesystem repo (fast, primary)
#  2) rclone backend (GDrive) if supported by restic on your platform
#  3) rest-server backend (remote restic server)
#
# The script logs output to logs/, uses a simple lock to avoid concurrent runs,
# and continues through failures (reports how many steps failed at the end).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd -P)"
LOG_DIR="${LOG_DIR:-${SCRIPT_DIR}/logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/triple-backup-$(date +%Y%m%d-%H%M%S).log"
LOCK_DIR="${SCRIPT_DIR}/.triple_backup.lock"

# Configurable (override via environment)
SOURCE_DIR="${SOURCE_DIR:-${HOME}/Final_Folder}"
RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-/mnt/c/Users/bhupi/password.txt}"

# Repositories (adjust if needed)
LOCAL_REPO="${LOCAL_REPO:-/mnt/d/WSL_Backups/restic-repo}"
RCLONE_REPO="${RCLONE_REPO:-rclone:GDrive:backup/restic_repo}"
REST_SERVER_REPO="${REST_SERVER_REPO:-rest:http://100.105.179.38:8001/}"

# Behaviour
VERBOSE="${VERBOSE:-1}"   # if 1, pass --verbose to restic

log() {
  local ts
  ts="$(date --iso-8601=seconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
  printf '%s %s\n' "$ts" "$*" | tee -a "$LOG_FILE"
}

# Acquire a simple lock (mkdir atomic)
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log "Another triple-backup run appears to be active (lock exists: $LOCK_DIR). Exiting."
  exit 2
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

# Sanity checks
if [ ! -d "$SOURCE_DIR" ]; then
  log "ERROR: source dir does not exist: $SOURCE_DIR"
  exit 1
fi
if [ ! -f "$RESTIC_PASSWORD_FILE" ]; then
  log "ERROR: restic password file missing: $RESTIC_PASSWORD_FILE"
  exit 1
fi

if ! command -v restic >/dev/null 2>&1; then
  log "ERROR: restic binary not found in PATH"
  exit 1
fi

export RESTIC_PASSWORD_FILE

run_backup() {
  local repo="$1"
  local tag="$2"
  local extra_args=()
  [ "$VERBOSE" -eq 1 ] && extra_args+=("--verbose")

  log "Starting restic backup -> $repo (tag=$tag)"
  if restic -r "$repo" backup "$SOURCE_DIR" --tag "$tag" "${extra_args[@]}" 2>&1 | tee -a "$LOG_FILE"; then
    log "Backup to $repo succeeded"
    return 0
  else
    log "WARNING: Backup to $repo failed"
    return 1
  fi
}

failures=0

# 1) local repo
if ! run_backup "$LOCAL_REPO" "final-folder-local"; then
  failures=$((failures+1))
fi

# 2) rclone/GDrive repo
# Note: this uses restic's rclone backend syntax. If your restic doesn't support rclone backend,
# you can replace this step with mounting rclone or using rclone copy of the repo directory.
if ! run_backup "$RCLONE_REPO" "final-folder-data"; then
  failures=$((failures+1))
fi

# 3) rest-server remote
if ! run_backup "$REST_SERVER_REPO" "final-folder-remote"; then
  failures=$((failures+1))
fi

if [ "$failures" -eq 0 ]; then
  log "All backups completed successfully"
  exit 0
else
  log "Completed with $failures failed backup(s). See $LOG_FILE"
  exit 3
fi
