#!/usr/bin/env bash
set -euo pipefail

# fdupes.sh
# Uses the fdupes tool to find duplicate files in a directory and moves
# duplicates to a quarantine folder, keeping one working copy in the original
# location. The quarantine folder is created in the parent directory with the
# name "<foldername>-quarantined".
#
# Usage:
#   ./fdupes.sh [-n] [-y] [directory]
#
# Options:
#   -n    dry-run: show what would be moved but don't actually move files
#   -y    auto-confirm (don't prompt before moving files)
#
# Arguments:
#   directory  Path to the directory to scan for duplicates (default: current directory)
#
# Prerequisites:
#   - fdupes tool must be installed (apt-get install fdupes on Debian/Ubuntu)
#   - python3 for file operations

DRYRUN=0
CONFIRM=0

# Parse options
while getopts ":ny" opt; do
  case $opt in
    n) DRYRUN=1 ;;
    y) CONFIRM=1 ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit 2 ;;
  esac
done

shift $((OPTIND-1))

# Get target directory (default to current directory)
TARGET_DIR="${1:-.}"

# Validate target directory exists
if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: Directory not found: $TARGET_DIR" >&2
  exit 3
fi

# Check if fdupes is installed
if ! command -v fdupes >/dev/null 2>&1; then
  echo "Error: fdupes tool not found. Please install it:" >&2
  echo "  On Debian/Ubuntu: sudo apt-get install fdupes" >&2
  echo "  On RedHat/CentOS: sudo yum install fdupes" >&2
  echo "  On macOS: brew install fdupes" >&2
  exit 4
fi

# Get absolute path of target directory
if command -v realpath >/dev/null 2>&1; then
  ABS_TARGET=$(realpath "$TARGET_DIR")
elif command -v readlink >/dev/null 2>&1; then
  ABS_TARGET=$(readlink -f "$TARGET_DIR")
else
  ABS_TARGET=$(python3 -c "import os,sys;print(os.path.abspath(sys.argv[1]))" "$TARGET_DIR")
fi

# Get the basename of the target directory
DIRNAME=$(basename "$ABS_TARGET")

# Create quarantine folder name in parent directory
PARENT_DIR=$(dirname "$ABS_TARGET")
QUARANTINE_DIR="$PARENT_DIR/${DIRNAME}-quarantined"

echo "Scanning directory: $ABS_TARGET"
echo "Quarantine folder: $QUARANTINE_DIR"
echo ""

# Run fdupes to find duplicates
echo "Searching for duplicate files..." >&2
TEMP_DUPES=$(mktemp -t fdupes.XXXXXX)
trap 'rm -f "$TEMP_DUPES"' EXIT

# Use fdupes with recursive scan, showing only duplicates
# The -r flag recursively scans directories
# We'll parse the output which groups duplicates together separated by blank lines
if ! fdupes -r "$ABS_TARGET" > "$TEMP_DUPES" 2>/dev/null; then
  echo "Error: fdupes failed to scan directory" >&2
  exit 5
fi

# Check if any duplicates were found
if [ ! -s "$TEMP_DUPES" ]; then
  echo "No duplicate files found in $ABS_TARGET"
  exit 0
fi

# Use Python to parse fdupes output and prepare move operations
python3 - "$TEMP_DUPES" "$ABS_TARGET" "$QUARANTINE_DIR" "$DRYRUN" "$CONFIRM" <<'PY'
import sys
import os
import shutil

dupes_file = sys.argv[1]
target_dir = sys.argv[2]
quarantine_dir = sys.argv[3]
dryrun = sys.argv[4] == '1'
autoconfirm = sys.argv[5] == '1'

# Parse fdupes output
# fdupes groups duplicates together, separated by blank lines
# Each group has 2+ files that are identical
duplicate_groups = []
current_group = []

with open(dupes_file, 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if line:
            # This is a file path
            current_group.append(line)
        else:
            # Blank line marks end of group
            if len(current_group) >= 2:
                duplicate_groups.append(current_group)
            current_group = []
    # Don't forget the last group if file doesn't end with blank line
    if len(current_group) >= 2:
        duplicate_groups.append(current_group)

if not duplicate_groups:
    print('No duplicate groups found.')
    sys.exit(0)

print(f'Found {len(duplicate_groups)} duplicate group(s)', file=sys.stderr)
print()

# For each group, keep the first file and move the rest to quarantine
files_to_move = []
for group in duplicate_groups:
    # Keep the first file in the original location
    keep_file = group[0]
    duplicates = group[1:]
    
    for dup in duplicates:
        files_to_move.append((dup, keep_file))

if not files_to_move:
    print('No files need to be moved.')
    sys.exit(0)

print(f'Summary: {len(files_to_move)} duplicate file(s) will be moved to quarantine')
print(f'         {len(duplicate_groups)} unique file(s) will be kept in original location')
print()

# Show first 20 files that will be moved
print(f'Files to move (first 20 of {len(files_to_move)} shown):')
for i, (dup, keep) in enumerate(files_to_move[:20]):
    print(f'  [{i+1}] {dup}')
    print(f'      (duplicate of: {keep})')
if len(files_to_move) > 20:
    print(f'  ... and {len(files_to_move)-20} more')
print()

if dryrun:
    print('Dry-run mode: no files will be moved.')
    sys.exit(0)

# Confirm before proceeding
if not autoconfirm:
    try:
        resp = input('Proceed to move these duplicates to quarantine? Type YES to confirm: ')
    except EOFError:
        resp = ''
    if resp != 'YES':
        print('Aborted by user. No files moved.')
        sys.exit(0)

# Create quarantine directory if it doesn't exist
if not os.path.exists(quarantine_dir):
    os.makedirs(quarantine_dir)
    print(f'Created quarantine directory: {quarantine_dir}')

# Move files to quarantine, preserving directory structure
moved = 0
errors = 0
skipped = 0

for dup_path, keep_path in files_to_move:
    try:
        # Check if file still exists
        if not os.path.exists(dup_path):
            print(f'Skipped (not found): {dup_path}')
            skipped += 1
            continue
        
        # Calculate relative path from target directory
        if dup_path.startswith(target_dir + os.sep):
            rel_path = os.path.relpath(dup_path, target_dir)
        else:
            # File is in target dir without separator (unlikely but handle it)
            rel_path = os.path.basename(dup_path)
        
        # Create destination path in quarantine
        dest_path = os.path.join(quarantine_dir, rel_path)
        dest_dir = os.path.dirname(dest_path)
        
        # Create destination directory if needed
        if not os.path.exists(dest_dir):
            os.makedirs(dest_dir)
        
        # Handle file name conflicts in destination
        if os.path.exists(dest_path):
            # Add a suffix to avoid overwriting
            base, ext = os.path.splitext(dest_path)
            counter = 1
            while os.path.exists(f"{base}_dup{counter}{ext}"):
                counter += 1
            dest_path = f"{base}_dup{counter}{ext}"
        
        # Move the file
        shutil.move(dup_path, dest_path)
        moved += 1
        print(f'Moved: {dup_path} -> {dest_path}')
        
    except Exception as e:
        print(f'Error moving {dup_path}: {e}', file=sys.stderr)
        errors += 1

print()
print(f'Finished. moved={moved} skipped={skipped} errors={errors}')
if moved > 0:
    print(f'Duplicate files moved to: {quarantine_dir}')
PY

echo "Done."
