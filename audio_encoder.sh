#!/bin/bash

# --- Configuration ---
MASTER_LOG_FILE="ffmpeg_audio_conversion_$(date +%Y%m%d_%H%M%S).log"
PARALLEL_JOBS=4   # how many files to process at once

BASE_DIR="$(basename "$(pwd)")"
OUTPUT_ROOT_DIR="../${BASE_DIR}_audio_encoded"

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
    SOURCE_AUDIO="$1"
    RELATIVE_PATH="${SOURCE_AUDIO#./}"
    RELATIVE_DIR="$(dirname "$RELATIVE_PATH")"
    FILENAME_NO_EXT="${RELATIVE_PATH%.*}"

    OUTPUT_DIR="$OUTPUT_ROOT_DIR/$RELATIVE_DIR"
    OUTPUT_FILE="$OUTPUT_DIR/${FILENAME_NO_EXT##*/}_encoded.m4a"

    mkdir -p "$OUTPUT_DIR"

    {
        echo
        echo "========== $(date '+%Y-%m-%d %H:%M:%S') =========="
        echo "Source: $SOURCE_AUDIO"
        echo "Output: $OUTPUT_FILE"
    } >> "$MASTER_LOG_FILE"

    echo "--- Processing: $SOURCE_AUDIO ---"
    echo "   -> Output: $OUTPUT_FILE"

    # Get duration in seconds (Safety check included)
    duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$SOURCE_AUDIO")
    duration=${duration%.*}
    if [ -z "$duration" ] || [ "$duration" -eq 0 ]; then
        duration=1
    fi

# Skip if output file already exists
if [[ -f "$OUTPUT_FILE" ]]; then
    echo "   -> Skipping (already exists): $OUTPUT_FILE"
    echo "SKIPPED $SOURCE_AUDIO" >> "$MASTER_LOG_FILE"
    return 0
fi

    # Detect source audio bitrate to avoid upsampling
    SRC_BITRATE=$(ffprobe -v error -select_streams a:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$SOURCE_AUDIO")
    
    # Default target bitrate: 128k (optimal balance of quality and file size)
    TARGET_BITRATE="128k"
    
    # If source bitrate is available and lower than 128k, match source to avoid upsampling
    if [ -n "$SRC_BITRATE" ] && [ "$SRC_BITRATE" != "N/A" ]; then
        SRC_BITRATE_K=$((SRC_BITRATE / 1000))
        if [ "$SRC_BITRATE_K" -lt 128 ] && [ "$SRC_BITRATE_K" -gt 0 ]; then
            TARGET_BITRATE="${SRC_BITRATE_K}k"
        fi
    fi

    # FFmpeg Command for audio encoding
    # Using AAC codec with optimized bitrate for efficient file size and acceptable quality
    # Target: 128k for most files (transparent quality), lower if source is already low bitrate
    ffmpeg -i "$SOURCE_AUDIO" -c:a aac -b:a "$TARGET_BITRATE" -vn -y "$OUTPUT_FILE" -progress - -nostats 2>>"$MASTER_LOG_FILE" | show_progress "$duration"

    FFMPEG_EXIT_CODE=${PIPESTATUS[0]}

    if [ "$FFMPEG_EXIT_CODE" -eq 0 ]; then
        echo "   -> Status: SUCCESS"
        echo "SUCCESS $SOURCE_AUDIO" >> "$MASTER_LOG_FILE"
    else
        echo "   -> Status: FAILED ($FFMPEG_EXIT_CODE)"
        echo "FAILED $SOURCE_AUDIO" >> "$MASTER_LOG_FILE"
        [ -f "$OUTPUT_FILE" ] && rm -f "$OUTPUT_FILE"
    fi
    echo "--------------------------------------------------------"
}

export -f process_file show_progress
export MASTER_LOG_FILE OUTPUT_ROOT_DIR

# --- Main Script ---
log_master "========================================================"
log_master "Starting Parallel FFmpeg Audio Conversion Script"
log_master "Parallel Jobs: $PARALLEL_JOBS"
log_master "Master Log File: $MASTER_LOG_FILE"
log_master "Output Root Directory: $OUTPUT_ROOT_DIR"
log_master "========================================================"

if ! command -v ffmpeg &> /dev/null; then
    log_master "ERROR: FFmpeg not found. Exiting."
    exit 1
fi
if ! command -v ffprobe &> /dev/null; then
    log_master "ERROR: FFprobe not found (required to detect audio properties). Exiting."
    exit 1
fi

mkdir -p "$OUTPUT_ROOT_DIR"

START_TIME=$(date +%s)
log_master "Conversion started at: $(date '+%Y-%m-%d %H:%M:%S')"
log_master "--------------------------------------------------------"

# Use xargs to launch parallel jobs
find . -type f \( -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.aac" -o -iname "*.m4a" -o -iname "*.ogg" -o -iname "*.wma" \) \
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
