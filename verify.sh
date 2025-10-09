#!/bin/bash

# --- Configuration ---
TOLERANCE=10   # seconds difference allowed
BASE_DIR="$(basename "$(pwd)")"
ENCODED_DIR="../${BASE_DIR}_encoded"

MASTER_VERIFY_LOG="ffmpeg_verification_$(date +%Y%m%d_%H%M%S).log"

# Log file for failed files only
FAILED_FILES_LOG="failed_files_$(date +%Y%m%d_%H%M%S).txt"

ok_count=0
fail_count=0
skip_count=0

log() {
    echo "$@" | tee -a "$MASTER_VERIFY_LOG"
}

log "========================================================"
log "Starting Verification Script"
log "Source Directory: $(pwd)"
log "Encoded Directory: $ENCODED_DIR"
log "Tolerance: ±${TOLERANCE}s"
log "Master Log: $MASTER_VERIFY_LOG"
log "========================================================"

if ! command -v ffprobe &> /dev/null; then
    log "ERROR: ffprobe not found. Please install ffmpeg tools."
    exit 1
fi

START_TIME=$(date +%s)

# Find all source files
while IFS= read -r -d '' SOURCE_VIDEO; do
    RELATIVE_PATH="${SOURCE_VIDEO#./}"
    RELATIVE_DIR="$(dirname "$RELATIVE_PATH")"
    FILENAME_NO_EXT="${RELATIVE_PATH%.*}"

    ENCODED_FILE="$ENCODED_DIR/$RELATIVE_DIR/${FILENAME_NO_EXT##*/}_encoded.mp4"

    if [[ ! -f "$ENCODED_FILE" ]]; then
           log "MISSING: $ENCODED_FILE (no encoded file found)"
           echo "$RELATIVE_PATH" >> "$FAILED_FILES_LOG"
           ((fail_count++))
           continue
    fi

    # Get durations
    SRC_DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$SOURCE_VIDEO")
    ENC_DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$ENCODED_FILE")

    SRC_DUR=${SRC_DUR%.*}
    ENC_DUR=${ENC_DUR%.*}

    DIFF=$(( SRC_DUR - ENC_DUR ))
    [[ $DIFF -lt 0 ]] && DIFF=$(( -DIFF ))

    if [[ $DIFF -le $TOLERANCE ]]; then
        log "OK: $RELATIVE_PATH (src=${SRC_DUR}s, enc=${ENC_DUR}s, diff=${DIFF}s)"
        ((ok_count++))
    else
            log "FAIL: $RELATIVE_PATH (src=${SRC_DUR}s, enc=${ENC_DUR}s, diff=${DIFF}s)"
            echo "$RELATIVE_PATH" >> "$FAILED_FILES_LOG"
            ((fail_count++))
    fi
done < <(find . -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.mpg" -o -iname "*.mkv" -o -iname "*.vob" \) -print0)

END_TIME=$(date +%s)
TOTAL_SECONDS=$((END_TIME - START_TIME))
TOTAL_TIME=$(date -u -d "@$TOTAL_SECONDS" +'%Hh %Mm %Ss')

# Count total media files in source
SOURCE_FILE_COUNT=$(find . -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.mkv" -o -iname "*.vob" \) | wc -l)

# Count total encoded files in destination
ENCODED_FILE_COUNT=$(find "$ENCODED_DIR" -type f -iname "*_encoded.mp4" | wc -l)

# Get folder sizes
SOURCE_SIZE=$(du -sh . | cut -f1)
ENCODED_SIZE=$(du -sh "$ENCODED_DIR" | cut -f1)

log "--------------------------------------------------------"
log "Verification finished at: $(date '+%Y-%m-%d %H:%M:%S')"
log "SUMMARY"
log "   OK files:             $ok_count"
log "   Failed files:         $fail_count"
log "   Skipped:              $skip_count"
log "   Total Time:           $TOTAL_TIME ($TOTAL_SECONDS seconds)"
log "   Total Source Files:   $SOURCE_FILE_COUNT"
log "   Total Encoded Files:  $ENCODED_FILE_COUNT"
log "   Source Folder Size:   $SOURCE_SIZE"
log "   Encoded Folder Size:  $ENCODED_SIZE"
log "========================================================"
log "Verification complete. All stats logged above."