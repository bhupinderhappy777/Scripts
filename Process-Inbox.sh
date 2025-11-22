#!/usr/bin/env bash
set -euo pipefail

# Process-Inbox.sh
# Linux/bash equivalent of Process-Inbox.ps1
# - Default paths live under $HOME (Inbox_Folder, Documents, Pictures, Music, Videos)
# - Maps extensions to target folders, moves files from Inbox to targets
# - On name collisions, compares SHA256; if identical moves to Duplicates; if different, renames incoming file
# - Uses flock for a simple lock to prevent concurrent runs
# - Preserves permissions and timestamps using cp -p fallback when necessary

LOCKFILE="$HOME/.process_inbox.lock"
exec 200>"$LOCKFILE"
flock -n 200 || { echo "Another Process-Inbox instance is already running. Exiting."; exit 0; }
trap 'rm -f "$LOCKFILE"; exit' EXIT

INBOX="${INBOX:-$HOME/Inbox_Folder}"
PICTURES="${PICTURES:-$HOME/Pictures}"
MUSIC="${MUSIC:-$HOME/Music}"
VIDEOS="${VIDEOS:-$HOME/Videos}"
DOCUMENTS="${DOCUMENTS:-$HOME/Documents}"
MISC="$DOCUMENTS/Misc_Documents"
DUPLICATES="$INBOX/Duplicates"

# Create destinations if missing
mkdir -p "$INBOX" "$PICTURES" "$MUSIC" "$VIDEOS" "$DOCUMENTS" "$MISC" "$DUPLICATES"

# Extension -> target mapping
declare -A MAPPINGS=(
  [jpg]="$PICTURES" [jpeg]="$PICTURES" [png]="$PICTURES" [zip]="$DOCUMENTS" [heic]="$PICTURES" [gif]="$PICTURES"
  [mp3]="$MUSIC" [m4a]="$MUSIC" [wav]="$MUSIC" [aac]="$MUSIC" [ogg]="$MUSIC"
  [mp4]="$VIDEOS" [mkv]="$VIDEOS" [avi]="$VIDEOS" [mov]="$VIDEOS" [wmv]="$VIDEOS"
  [pdf]="$DOCUMENTS" [docx]="$DOCUMENTS" [doc]="$DOCUMENTS" [xlsx]="$DOCUMENTS" [xls]="$DOCUMENTS"
  [pptx]="$DOCUMENTS" [ppt]="$DOCUMENTS" [txt]="$DOCUMENTS" [rtf]="$DOCUMENTS" [odt]="$DOCUMENTS"
)

echo "Starting Inbox Processing at $(date)"

# Usage helper
usage() {
  cat <<EOF
Usage: $0 [--watch|-w]
  No args: process all existing files found in the Inbox folder and exit.
  --watch, -w : run continuously, watching the Inbox for new files (requires inotifywait).

Environment variables to override defaults:
  INBOX, PICTURES, MUSIC, VIDEOS, DOCUMENTS
EOF
}

# Helper: safely move a file; if mv fails (e.g., cross-filesystem), use cp -p then remove original
move_file() {
  local src="$1" dst="$2"
  # Ensure destination directory exists
  mkdir -p "$(dirname "$dst")"
  if mv -- "$src" "$dst" 2>/dev/null; then
    return 0
  else
    if cp -p -- "$src" "$dst"; then
      rm -f -- "$src"
      return 0
    else
      return 1
    fi
  fi
}

# Helper: move to duplicates folder, ensure unique filename there
move_to_duplicates() {
  local src="$1"
  local name
  name=$(basename -- "$src")
  local base ext
  if [[ "$name" == *.* ]]; then
    base="${name%.*}"
    ext=".${name##*.}"
  else
    base="$name"
    ext=""
  fi
  local dst="$DUPLICATES/$name"
  local i=1
  while [ -e "$dst" ]; do
    dst="$DUPLICATES/${base} (${i})${ext}"
    i=$((i+1))
    if [ $i -gt 1000 ]; then echo "Exceeded rename attempts for duplicates for $name"; break; fi
  done
  mkdir -p "$DUPLICATES"
  if move_file "$src" "$dst"; then
    echo "Moved '$name' to Duplicates as '$(basename "$dst")'"
  else
    echo "Failed to move '$name' to Duplicates. Manual intervention required." >&2
  fi
}

# wait until a file is stable (size doesn't change) or timeout
wait_until_stable() {
  local file="$1"
  local retries=6
  local delay=1
  local i=0
  if [ ! -e "$file" ]; then return 1; fi
  local last_size
  last_size=$(stat --format=%s -- "$file" 2>/dev/null || echo 0)
  while [ $i -lt $retries ]; do
    sleep $delay
    size=$(stat --format=%s -- "$file" 2>/dev/null || echo 0)
    if [ "$size" -eq "$last_size" ]; then
      return 0
    fi
    last_size=$size
    i=$((i+1))
  done
  return 0
}

# Process a single file path
process_file() {
  local src="$1"
  case "$src" in
    "$DUPLICATES"* ) return 0 ;;
  esac
  if [ ! -f "$src" ]; then return 0; fi
  wait_until_stable "$src" || true

  local filename ext ext_lc target dest base extpart i unique src_hash dst_hash
  filename=$(basename -- "$src")
  if [[ "$filename" == *.* ]]; then
    ext="${filename##*.}"
  else
    ext=""
  fi
  ext_lc=$(printf "%s" "$ext" | tr 'A-Z' 'a-z')

  target="${MAPPINGS[$ext_lc]:-$MISC}"
  echo "Processing '$filename' (.$ext_lc) -> $target"
  mkdir -p "$target"
  dest="$target/$filename"

  if [ -e "$dest" ]; then
    echo "  Name collision: '$filename' exists in '$target'. Computing hashes..."
    if ! src_hash=$(sha256sum -- "$src" 2>/dev/null | awk '{print $1}'); then
      echo "  Failed to compute hash for source '$src'. Leaving file in Inbox for manual review." >&2
      return 0
    fi
    if ! dst_hash=$(sha256sum -- "$dest" 2>/dev/null | awk '{print $1}'); then
      echo "  Failed to compute hash for destination '$dest'. Leaving file in Inbox for manual review." >&2
      return 0
    fi

    if [ "$src_hash" = "$dst_hash" ]; then
      echo "  File contents match (hash equal). Moving incoming file to Duplicates for review."
      move_to_duplicates "$src"
      return 0
    else
      echo "  Same name but different contents. Renaming incoming file and moving to destination."
      if [[ "$filename" == *.* ]]; then
        base="${filename%.*}"
        extpart=".${filename##*.}"
      else
        base="$filename"
        extpart=""
      fi
      i=1
      unique="$target/${base} (${i})${extpart}"
      while [ -e "$unique" ]; do
        i=$((i+1))
        unique="$target/${base} (${i})${extpart}"
        if [ $i -gt 1000 ]; then echo "Exceeded max rename attempts for file '$filename' in '$target'"; break; fi
      done
      if move_file "$src" "$unique"; then
        echo "  Successfully moved and renamed to '$(basename "$unique")'."
      else
        echo "  Failed to move and rename '$filename' to '$target'. Leaving in Inbox for manual review." >&2
      fi
    fi
  else
    if move_file "$src" "$dest"; then
      echo "  Successfully moved '$filename' to '$target'."
    else
      echo "  Failed to move '$filename' to '$target'. Leaving in Inbox for manual review." >&2
    fi
  fi
}

# CLI: support --watch mode
if [ "${1:-}" = "--watch" ] || [ "${1:-}" = "-w" ]; then
  if ! command -v inotifywait >/dev/null 2>&1; then
    echo "inotifywait not found. Install 'inotify-tools' (e.g., sudo apt install inotify-tools)" >&2
    exit 1
  fi
  echo "Entering watch mode; monitoring $INBOX for new files..."
  # Process any existing files first
  while IFS= read -r -d '' f; do
    process_file "$f"
  done < <(find "$INBOX" -mindepth 1 -path "$DUPLICATES" -prune -o -type f -print0)

  # Monitor for new files and moved-to events using process substitution so the loop runs
  # in the main shell (avoids subshell issues under systemd). Use -r to watch subdirectories
  # and include close_write so files written by writers that rename into place are handled.
  # Wrap in a restart loop so if inotifywait exits, we restart it automatically.
  while true; do
    while IFS= read -r newfile; do
      # skip events inside duplicates folder
      case "$newfile" in
        "$DUPLICATES"*) continue ;;
      esac
      # only process regular files
      if [ -f "$newfile" ]; then
        process_file "$newfile"
      fi
    done < <(inotifywait -m -r -e create -e moved_to -e close_write --format '%w%f' "$INBOX")

    echo "inotifywait exited unexpectedly; restarting in 1s" >&2
    sleep 1
  done
else
  # Batch mode: find and process all existing files
  files_found=()
  while IFS= read -r -d '' f; do
    files_found+=("$f")
  done < <(find "$INBOX" -mindepth 1 -path "$DUPLICATES" -prune -o -type f -print0)

  if [ ${#files_found[@]} -eq 0 ]; then
    echo "No new files found in Inbox to process."
    exit 0
  fi

  echo "Found ${#files_found[@]} files to process."

  for src in "${files_found[@]}"; do
    process_file "$src"
  done

  echo "Inbox Processing Complete at $(date)"
fi

# Release lock and exit (trap will remove lockfile)
exit 0
