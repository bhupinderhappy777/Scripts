#!/bin/bash

# --- Configuration ---
MASTER_LOG_FILE="ffmpeg_recursive_conversion_$(date +%Y%m%d_%H%M%S).log"
PARALLEL_JOBS=4   # how many files to process at once

BASE_DIR="$(basename "$(pwd)")"
OUTPUT_ROOT_DIR="../${BASE_DIR}_encoded"

log_master() {
    echo "$@" | tee -a "$MASTER_LOG_FILE"
}

# Function to show progress (Original structure retained)
show_progress() {
    local duration="$1"
    local start_time=$(date +%s)
    while IFS='=' read -r key value; do
        case "$key" in
            out_time_ms)
                current_ms=$((value/1000000))
                percent=$((current_ms * 100 / duration))
                elapsed=$(( $(date +%s) - start_time ))
                if [ "$percent" -gt 0 ]; then
                    remaining=$(( (elapsed * 100 / percent) - elapsed ))
                else
                    remaining=0
                fi
                printf "\rProgress: %3d%% | Elapsed: %02d:%02d | ETA: %02d:%02d" \
                    "$percent" $((elapsed/60)) $((elapsed%60)) $((remaining/60)) $((remaining%60))
                ;;
            progress)
                if [[ "$value" == "end" ]]; then
                    echo -e "\rProgress: 100% - Done! "
                fi
                ;;
        esac
    done
}

process_file() {
    SOURCE_VIDEO="$1"
    RELATIVE_PATH="${SOURCE_VIDEO#./}"
    RELATIVE_DIR="$(dirname "$RELATIVE_PATH")"
    FILENAME_NO_EXT="${RELATIVE_PATH%.*}"

    OUTPUT_DIR="$OUTPUT_ROOT_DIR/$RELATIVE_DIR"
    OUTPUT_FILE="$OUTPUT_DIR/${FILENAME_NO_EXT##*/}_encoded.mp4"

    mkdir -p "$OUTPUT_DIR"

    {
        echo
        echo "========== $(date '+%Y-%m-%d %H:%M:%S') =========="
        echo "Source: $SOURCE_VIDEO"
        echo "Output: $OUTPUT_FILE"
    } >> "$MASTER_LOG_FILE"

    echo "--- Processing: $SOURCE_VIDEO ---"
    echo "   -> Output: $OUTPUT_FILE"

    # Get duration in seconds (Safety check included)
    duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$SOURCE_VIDEO")
    duration=${duration%.*}
    if [ -z "$duration" ] || [ "$duration" -eq 0 ]; then
        duration=1
    fi
    
    # --- TWEAK 1: FPS Extraction Logic ---
    FPS_RAW=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=noprint_wrappers=1:nokey=1 "$SOURCE_VIDEO")
    
    if [[ "$FPS_RAW" =~ "/" ]]; then
        FPS=$(echo "$FPS_RAW" | awk -F/ '{printf "%.2f", $1/$2}')
    else
        FPS=$FPS_RAW
        if [ -z "$FPS" ]; then
            FPS=25
        fi
    fi
    # --------------------------------------------------------------------

# Skip if output file already exists
if [[ -f "$OUTPUT_FILE" ]]; then
    echo "   -> Skipping (already exists): $OUTPUT_FILE"
    echo "SKIPPED $SOURCE_VIDEO" >> "$MASTER_LOG_FILE"
    return 0
fi

    # --- TWEAK 2: New Conditional Scaling Logic (Shell-Safe) ---
    # Get height of the source video
    SRC_HEIGHT=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$SOURCE_VIDEO")
    
    # Use standard Bash 'if' to decide the filter, avoiding complex FFmpeg expression language
    if [ "$SRC_HEIGHT" -gt 1080 ]; then
        # Scale down to 1080p if original is larger
        SCALE_FILTER="-vf scale=-2:1080"
    else
        # Do not scale if original is 1080p or smaller
        SCALE_FILTER=""
    fi
    
    # FINAL FFmpeg Command (One Line for Stability)
    # TWEAK 3: Added -r "$FPS" to lock frame rate.
    ffmpeg -i "$SOURCE_VIDEO" -c:v libx264 -preset slow -crf 28 -movflags faststart -profile:v high -level 4.0 -r "$FPS" $SCALE_FILTER -c:a aac -b:a 96k -y "$OUTPUT_FILE" -progress - -nostats 2>>"$MASTER_LOG_FILE" | show_progress "$duration"

    FFMPEG_EXIT_CODE=${PIPESTATUS[0]}

    if [ "$FFMPEG_EXIT_CODE" -eq 0 ]; then
        echo "   -> Status: SUCCESS"
        echo "SUCCESS $SOURCE_VIDEO" >> "$MASTER_LOG_FILE"
    else
        echo "   -> Status: FAILED ($FFMPEG_EXIT_CODE)"
        echo "FAILED $SOURCE_VIDEO" >> "$MASTER_LOG_FILE"
        [ -f "$OUTPUT_FILE" ] && rm -f "$OUTPUT_FILE"
    fi
    echo "--------------------------------------------------------"
}

export -f process_file show_progress
export MASTER_LOG_FILE OUTPUT_ROOT_DIR

# --- Main Script ---
log_master "========================================================"
log_master "Starting Parallel FFmpeg Conversion Script (Final Stable Version)"
log_master "Parallel Jobs: $PARALLEL_JOBS"
log_master "Master Log File: $MASTER_LOG_FILE"
log_master "Output Root Directory: $OUTPUT_ROOT_DIR"
log_master "========================================================"

if ! command -v ffmpeg &> /dev/null; then
    log_master "ERROR: FFmpeg not found. Exiting."
    exit 1
fi
if ! command -v ffprobe &> /dev/null; then
    log_master "ERROR: FFprobe not found (required to detect video properties). Exiting."
    exit 1
fi

mkdir -p "$OUTPUT_ROOT_DIR"

START_TIME=$(date +%s)
log_master "Conversion started at: $(date '+%Y-%m-%d %H:%M:%S')"
log_master "--------------------------------------------------------"

# Use xargs to launch parallel jobs
find . -type f \( -iname "*.MOV" -o -iname "*.mov" -o -iname "*.mpg" -o -iname "*.mkv" -o -iname "*.vob" \) \
    ! -path "$OUTPUT_ROOT_DIR/*" -print0 | \
xargs -0 -n1 -P"$PARALLEL_JOBS" bash -c 'process_file "$@"' _

END_TIME=$(date +%s)
TOTAL_SECONDS=$((END_TIME - START_TIME))
TOTAL_TIME=$(date -u -d "@$TOTAL_SECONDS" +'%Hh %Mm %Ss')

# --- Final Summary ---
success_count=$(grep -c "^SUCCESS" "$MASTER_LOG_FILE")
fail_count=$(grep -c "^FAILED" "$MASTER_LOG_FILE")
skip_count=$(grep -c "^SKIPPED" "$MASTER_LOG_FILE")

log_master "--------------------------------------------------------"
log_master "Script finished at: $(date '+%Y-%m-%d %H:%M:%S')"
log_master "OVERALL SUMMARY"
log_master "   Successful encodes: $success_count"
log_master "   Failed encodes:     $fail_count"
log_master "   Skipped files:      $skip_count"
log_master "   Total Time Taken:   $TOTAL_TIME ($TOTAL_SECONDS seconds)"
log_master "All encoded files saved to: $OUTPUT_ROOT_DIR"
log_master "========================================================"
exit 0
