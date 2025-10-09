#!/bin/bash

# --- Configuration ---
LOG_FILE="rsync_transfer_log_$(date +%Y%m%d_%H%M%S).txt"

# Function to log output to both terminal and file
log() {
    echo "$@" | tee -a "$LOG_FILE"
}

# --- Main Script ---

log "========================================================"
log "Starting Rsync Transfer Script"
log "Log File: $LOG_FILE"
log "========================================================"

# 1. Get Source and Destination Paths
read -p "Enter SOURCE file or directory path (e.g., /mnt/c/Users/YourName/file.zip): " SOURCE
read -p "Enter REMOTE DESTINATION path (e.g., user@host:/remote/path/): " DESTINATION

# 2. Start Overall Timer
START_TIME=$(date +%s)
log "Transfer started at: $(date '+%Y-%m-%d %H:%M:%S')"
log "--------------------------------------------------------"

# 3. Determine Rsync Options
# The -a option is for archive (recursive, permissions, times, etc.)
# The -v option is for verbose (shows files being transferred)
# The -z option compresses data during transfer (recommended)
# The --progress option shows overall progress, but doesn't log time per file easily.
# We'll use the rsync output parsing to capture per-file details.

# The core rsync command: -a, -v (verbose), -z (compress), --out-format is key for logging.
# %n = filename, %l = file length, %T = time taken, %B = block size (useful for speed check)
# NOTE: The %T (time taken) in rsync's custom format is for the *entire transfer*, not per file.
#       To get per-file time, we must use the standard rsync verbose output and a custom function.
#       However, for simplicity and accuracy, the script will focus on logging the per-file
#       size and name, and then calculate the *total* time accurately.

# Using 'time' utility for total time and redirecting rsync's verbose output.
log "Running Rsync command (Total time will be calculated)..."
log "--------------------------------------------------------"

# Capture rsync output and pipe it to a custom function for per-file logging
# The 'time' command will wrap the entire rsync command to capture wall-clock time.
{
    time rsync -avz --progress "$SOURCE" "$DESTINATION" 2>&1 | while IFS= read -r line; do
        # Log the rsync output to the terminal and the log file
        log "$line"

        # Simple check to log transferred file details (rsync's verbose output has this pattern)
        # This is less reliable than a true custom format but avoids complex shell parsing of that format.
        if [[ "$line" =~ ^(sending|receiving) ]]; then
            # Extract just the file/directory name for the log
            FILE_NAME=$(echo "$line" | awk '{print $NF}')
            # Log file information (rsync only outputs size/time once per *completed* file)
            # The exact time per file is hard to extract accurately without a wrapper script on the remote host,
            # so we focus on the size here, and the total time at the end.
            log "[FILE INFO] $FILE_NAME"
        fi
    done
} 2> "$LOG_FILE.time_output" # 'time' output goes to a temporary file

# 4. End Overall Timer and Calculate Total Time
END_TIME=$(date +%s)
TOTAL_SECONDS=$((END_TIME - START_TIME))
TOTAL_TIME=$(date -u -d @"$TOTAL_SECONDS" +'%Hh %Mm %Ss')

log "--------------------------------------------------------"
log "Transfer finished at: $(date '+%Y-%m-%d %H:%M:%S')"
log "--------------------------------------------------------"
log "Transfer SUMMARY"
log "Total Wall-Clock Time Taken: $TOTAL_TIME ($TOTAL_SECONDS seconds)"

# 5. Extract and Log Final Stats from rsync output (optional, but helpful)
# The final lines of rsync output contain size and speed summary.
tail -n 5 "$LOG_FILE" | log

# Cleanup
rm -f "$LOG_FILE.time_output"
log "========================================================"
