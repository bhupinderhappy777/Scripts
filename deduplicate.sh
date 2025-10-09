#!/usr/bin/env bash
set -euo pipefail

# deduplicate.sh
# Main orchestration script for the complete de-duplication workflow.
# This script automates the entire process:
# 1. Generate/update hashes for master folder
# 2. Generate/update hashes for compared folder
# 3. Compare hashes and find duplicates
# 4. Move duplicates to quarantine
# 5. Run fdupes on compared folder to find internal duplicates
# 6. Move remaining unique files to master folder
# 7. Generate summary report
#
# Usage:
#   ./deduplicate.sh
#   or via curl (no download required):
#   bash <(curl -s https://raw.githubusercontent.com/bhupinderhappy777/Scripts/main/deduplicate.sh)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# GitHub repository base URL for fetching scripts
GITHUB_REPO_URL="https://raw.githubusercontent.com/bhupinderhappy777/Scripts/main"

# Get the directory where this script is located
# If running via curl, use current directory
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR="$(pwd)"
fi

# Log file for the session
LOG_FILE="deduplication_$(date +%Y%m%d_%H%M%S).log"

# Function to fetch and execute a script from GitHub
fetch_and_run() {
    local script_name="$1"
    shift
    local args=("$@")
    
    echo "Fetching $script_name from GitHub..." >&2
    if curl -fsSL "${GITHUB_REPO_URL}/${script_name}" | bash -s -- "${args[@]}"; then
        return 0
    else
        return 1
    fi
}

# Function to print colored messages
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Function to log and print
log_print() {
    echo "$1" | tee -a "$LOG_FILE"
}

# Start logging
log_print "=== De-duplication Process Started ==="
log_print "Date: $(date)"
log_print ""

# Ask for Master Directory Path
print_header "Step 1: Input Directories"
echo -n "Enter Master Directory Path: "
read -r MASTER_DIR
MASTER_DIR="${MASTER_DIR%/}"  # Remove trailing slash

if [ ! -d "$MASTER_DIR" ]; then
    print_error "Master directory does not exist: $MASTER_DIR"
    log_print "ERROR: Master directory does not exist: $MASTER_DIR"
    exit 1
fi

log_print "Master Directory: $MASTER_DIR"

# Ask for Compared Directory Path
echo -n "Enter Path to be Compared: "
read -r COMPARED_DIR
COMPARED_DIR="${COMPARED_DIR%/}"  # Remove trailing slash

if [ ! -d "$COMPARED_DIR" ]; then
    print_error "Compared directory does not exist: $COMPARED_DIR"
    log_print "ERROR: Compared directory does not exist: $COMPARED_DIR"
    exit 1
fi

log_print "Compared Directory: $COMPARED_DIR"
log_print ""

# Initialize counters for summary
TOTAL_START=$(date +%s)

# Step 2: Generate/Update Master Hashes
print_header "Step 2: Generating/Updating Master Hashes"
log_print "=== Step 2: Generating/Updating Master Hashes ==="

STEP_START=$(date +%s)
if fetch_and_run "generate_master_hashes.sh" "$MASTER_DIR" 2>&1 | tee -a "$LOG_FILE"; then
    STEP_END=$(date +%s)
    STEP_TIME=$((STEP_END - STEP_START))
    print_success "Master hashes updated (${STEP_TIME}s)"
    log_print "Master hashes generation completed in ${STEP_TIME}s"
else
    print_error "Failed to generate master hashes"
    log_print "ERROR: Failed to generate master hashes"
    exit 1
fi
log_print ""

# Step 3: Generate/Update Compared Folder Hashes
print_header "Step 3: Generating/Updating Compared Folder Hashes"
log_print "=== Step 3: Generating/Updating Compared Folder Hashes ==="

STEP_START=$(date +%s)
if fetch_and_run "generate_hash_file.sh" "$COMPARED_DIR" 2>&1 | tee -a "$LOG_FILE"; then
    STEP_END=$(date +%s)
    STEP_TIME=$((STEP_END - STEP_START))
    print_success "Compared folder hashes updated (${STEP_TIME}s)"
    log_print "Compared folder hashes generation completed in ${STEP_TIME}s"
else
    print_error "Failed to generate compared folder hashes"
    log_print "ERROR: Failed to generate compared folder hashes"
    exit 1
fi
log_print ""

# Step 4: Compare Hashes
print_header "Step 4: Comparing Hashes"
log_print "=== Step 4: Comparing Hashes ==="

STEP_START=$(date +%s)
if fetch_and_run "compare_hashes.sh" "$COMPARED_DIR" 2>&1 | tee -a "$LOG_FILE"; then
    STEP_END=$(date +%s)
    STEP_TIME=$((STEP_END - STEP_START))
    print_success "Hash comparison completed (${STEP_TIME}s)"
    log_print "Hash comparison completed in ${STEP_TIME}s"
else
    print_error "Failed to compare hashes"
    log_print "ERROR: Failed to compare hashes"
    exit 1
fi
log_print ""

# Step 5: Move Duplicates to Quarantine
print_header "Step 5: Moving Duplicates to Quarantine"
log_print "=== Step 5: Moving Duplicates to Quarantine ==="

STEP_START=$(date +%s)

# Check if comparison file was created
COMPARISON_FILES=(*.comparison.csv)
if [ ! -f "${COMPARISON_FILES[0]}" ] || [ "${COMPARISON_FILES[0]}" = "*.comparison.csv" ]; then
    print_warning "No comparison file found. Skipping deletion step."
    log_print "WARNING: No comparison file found. Skipping deletion step."
else
    # Count matches in comparison file
    MATCH_COUNT=$(awk 'NR>1' "${COMPARISON_FILES[0]}" | wc -l | tr -d ' ')
    if [ "$MATCH_COUNT" -eq 0 ]; then
        print_warning "No duplicates found in comparison. Skipping deletion step."
        log_print "No duplicates found in comparison."
    else
        log_print "Found $MATCH_COUNT duplicate matches. Moving to quarantine..."
        if fetch_and_run "deletion.sh" "-y" 2>&1 | tee -a "$LOG_FILE"; then
            STEP_END=$(date +%s)
            STEP_TIME=$((STEP_END - STEP_START))
            print_success "Duplicates moved to quarantine (${STEP_TIME}s)"
            log_print "Duplicates moved to quarantine in ${STEP_TIME}s"
        else
            print_warning "Deletion script encountered issues (non-fatal)"
            log_print "WARNING: Deletion script encountered issues"
        fi
    fi
fi
log_print ""

# Step 6: Run fdupes on Compared Folder
print_header "Step 6: Finding Internal Duplicates with fdupes"
log_print "=== Step 6: Finding Internal Duplicates with fdupes ==="

STEP_START=$(date +%s)

# Check if fdupes is available
if ! command -v fdupes >/dev/null 2>&1; then
    print_warning "fdupes not installed. Skipping internal duplicate detection."
    log_print "WARNING: fdupes not installed. Skipping internal duplicate detection."
else
    if fetch_and_run "fdupes.sh" "-y" "$COMPARED_DIR" 2>&1 | tee -a "$LOG_FILE"; then
        STEP_END=$(date +%s)
        STEP_TIME=$((STEP_END - STEP_START))
        print_success "Internal duplicates processed (${STEP_TIME}s)"
        log_print "Internal duplicates processed in ${STEP_TIME}s"
    else
        print_warning "fdupes script encountered issues (non-fatal)"
        log_print "WARNING: fdupes script encountered issues"
    fi
fi
log_print ""

# Step 7: Move Remaining Files to Master
print_header "Step 7: Moving Unique Files to Master Folder"
log_print "=== Step 7: Moving Unique Files to Master Folder ==="

STEP_START=$(date +%s)

# Count remaining files in compared directory
REMAINING_COUNT=$(find "$COMPARED_DIR" -type f ! -name "hash_file.csv" | wc -l | tr -d ' ')
log_print "Remaining files in compared directory: $REMAINING_COUNT"

if [ "$REMAINING_COUNT" -eq 0 ]; then
    print_warning "No files remaining in compared directory to move."
    log_print "No files remaining to move to master."
else
    if fetch_and_run "move_to_master.sh" "$COMPARED_DIR" "$MASTER_DIR" 2>&1 | tee -a "$LOG_FILE"; then
        STEP_END=$(date +%s)
        STEP_TIME=$((STEP_END - STEP_START))
        print_success "Unique files moved to master (${STEP_TIME}s)"
        log_print "Unique files moved to master in ${STEP_TIME}s"
    else
        print_warning "Move to master encountered issues (non-fatal)"
        log_print "WARNING: Move to master encountered issues"
    fi
fi
log_print ""

# Step 8: Generate Summary
print_header "Step 8: Summary"
log_print "=== Step 8: Summary ==="

TOTAL_END=$(date +%s)
TOTAL_TIME=$((TOTAL_END - TOTAL_START))

# Count files in various locations
MASTER_FILE_COUNT=$(find "$MASTER_DIR" -type f ! -name "master_hashes.csv" 2>/dev/null | wc -l | tr -d ' ')
COMPARED_FILE_COUNT=$(find "$COMPARED_DIR" -type f ! -name "hash_file.csv" 2>/dev/null | wc -l | tr -d ' ')

# Find quarantine directories
COMPARED_BASENAME=$(basename "$COMPARED_DIR")
COMPARED_PARENT=$(dirname "$COMPARED_DIR")
QUARANTINE_DIR="$COMPARED_PARENT/${COMPARED_BASENAME}-quarantined"
QUARANTINE_FILE_COUNT=0
if [ -d "$QUARANTINE_DIR" ]; then
    QUARANTINE_FILE_COUNT=$(find "$QUARANTINE_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
fi

echo ""
log_print "╔════════════════════════════════════════════════════════╗"
log_print "║           DE-DUPLICATION SUMMARY REPORT                 ║"
log_print "╟────────────────────────────────────────────────────────╢"
log_print "║ Master Directory: $MASTER_DIR"
log_print "║ Compared Directory: $COMPARED_DIR"
log_print "║"
log_print "║ Final File Counts:"
log_print "║   Files in Master:      $MASTER_FILE_COUNT"
log_print "║   Files in Compared:    $COMPARED_FILE_COUNT"
log_print "║   Files in Quarantine:  $QUARANTINE_FILE_COUNT"
log_print "║"
log_print "║ Total Processing Time:  ${TOTAL_TIME}s"
log_print "║ Log File: $LOG_FILE"
log_print "╚════════════════════════════════════════════════════════╝"
echo ""

# Add diagnostic information if files remain in compared directory
if [ "$COMPARED_FILE_COUNT" -gt 0 ]; then
    print_warning "Files remaining in compared directory!"
    log_print ""
    log_print "═══ DIAGNOSTIC INFORMATION ═══"
    log_print "Files remain in the compared directory. Possible reasons:"
    log_print "  1. Files have duplicate hashes (same content as master)"
    log_print "  2. Files encountered errors during move operation"
    log_print "  3. Files already exist at destination with same content"
    log_print "  4. Script was interrupted or encountered unexpected conditions"
    log_print ""
    log_print "Listing remaining files in compared directory:"
    find "$COMPARED_DIR" -type f ! -name "hash_file.csv" 2>/dev/null | head -20 | while read -r file; do
        log_print "  - $file"
    done
    REMAINING_TOTAL=$(find "$COMPARED_DIR" -type f ! -name "hash_file.csv" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$REMAINING_TOTAL" -gt 20 ]; then
        log_print "  ... and $((REMAINING_TOTAL - 20)) more files"
    fi
    log_print ""
    log_print "To investigate further:"
    log_print "  - Check the log file for detailed error messages: $LOG_FILE"
    log_print "  - Compare hash_file.csv in compared directory with master_hashes.csv"
    log_print "  - Verify if files have permissions issues or are in use"
    log_print ""
fi

print_success "De-duplication process completed!"
log_print ""
log_print "=== De-duplication Process Completed ==="
log_print "End Time: $(date)"

echo ""
echo "Full log saved to: $LOG_FILE"
