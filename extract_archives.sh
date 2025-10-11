#!/usr/bin/env bash
set -euo pipefail

# extract_archives.sh
# Finds all compressed archive files in a directory (recursively), extracts them,
# and removes the original archive files after successful extraction.
#
# Usage:
#   ./extract_archives.sh [-n] [-y] [directory]
#
# Options:
#   -n    dry-run: show what would be extracted but don't extract or delete
#   -y    auto-confirm (don't prompt before proceeding)
#
# Arguments:
#   directory  Path to search for archives (default: current directory)
#
# Supported formats:
#   .zip, .tar, .tar.gz, .tgz, .tar.bz2, .tbz2, .tar.xz, .txz, .gz, .bz2, .xz, .7z, .rar

DRYRUN=0
CONFIRM=0
TARGET_DIR="."

# Parse options
while getopts ":ny" opt; do
  case $opt in
    n) DRYRUN=1 ;;
    y) CONFIRM=1 ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit 2 ;;
  esac
done

shift $((OPTIND-1))

# Get target directory argument
if [ $# -gt 0 ]; then
  TARGET_DIR="$1"
fi

# Validate directory
if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: Directory not found: $TARGET_DIR" >&2
  exit 1
fi

# Get absolute path
if command -v realpath >/dev/null 2>&1; then
  ABS_TARGET=$(realpath "$TARGET_DIR")
elif command -v readlink >/dev/null 2>&1; then
  ABS_TARGET=$(readlink -f "$TARGET_DIR")
else
  ABS_TARGET=$(python3 -c "import os,sys;print(os.path.abspath(sys.argv[1]))" "$TARGET_DIR")
fi

echo "Searching for archives in: $ABS_TARGET"
echo ""

# Find all archive files
TEMP_LIST=$(mktemp -t archives.XXXXXX)
trap 'rm -f "$TEMP_LIST"' EXIT

# Search for various archive formats
find "$ABS_TARGET" -type f \( \
  -name "*.zip" -o \
  -name "*.tar" -o \
  -name "*.tar.gz" -o \
  -name "*.tgz" -o \
  -name "*.tar.bz2" -o \
  -name "*.tbz2" -o \
  -name "*.tar.xz" -o \
  -name "*.txz" -o \
  -name "*.gz" -o \
  -name "*.bz2" -o \
  -name "*.xz" -o \
  -name "*.7z" -o \
  -name "*.rar" \
\) > "$TEMP_LIST"

ARCHIVE_COUNT=$(wc -l < "$TEMP_LIST" | tr -d ' ')

if [ "$ARCHIVE_COUNT" -eq 0 ]; then
  echo "No archive files found."
  exit 0
fi

echo "Found $ARCHIVE_COUNT archive file(s):"
head -20 "$TEMP_LIST" | while read -r line; do echo "  $line"; done
if [ "$ARCHIVE_COUNT" -gt 20 ]; then
  echo "  ... and $((ARCHIVE_COUNT - 20)) more"
fi
echo ""

if [ "$DRYRUN" -eq 1 ]; then
  echo "Dry-run mode: no files will be extracted or deleted."
  exit 0
fi

if [ "$CONFIRM" -eq 0 ]; then
  echo "This will extract all archives and DELETE the originals after successful extraction."
  read -p "Proceed? Type YES to confirm: " response
  if [ "$response" != "YES" ]; then
    echo "Aborted by user."
    exit 0
  fi
fi

echo ""
echo "Starting extraction process..."
echo ""

# Process archives using Python for better error handling and cross-platform support
python3 - "$TEMP_LIST" "$ABS_TARGET" <<'PY'
import sys
import os
import subprocess
import shutil

archive_list_file = sys.argv[1]
base_dir = sys.argv[2]

# Read archive list
with open(archive_list_file, 'r') as f:
    archives = [line.strip() for line in f if line.strip()]

total = len(archives)
extracted = 0
failed = 0
skipped = 0

def extract_archive(archive_path):
    """Extract archive and return True if successful, False otherwise."""
    if not os.path.exists(archive_path):
        return False, "File not found"
    
    # Get the directory containing the archive
    archive_dir = os.path.dirname(archive_path)
    archive_name = os.path.basename(archive_path)
    
    # Determine extraction method based on extension
    lower_name = archive_name.lower()
    
    try:
        if lower_name.endswith('.zip'):
            # Use unzip command
            result = subprocess.run(
                ['unzip', '-q', '-o', archive_path, '-d', archive_dir],
                capture_output=True,
                text=True
            )
            if result.returncode != 0:
                return False, f"unzip failed: {result.stderr}"
        
        elif lower_name.endswith(('.tar.gz', '.tgz')):
            # Use tar command for .tar.gz and .tgz
            result = subprocess.run(
                ['tar', '-xzf', archive_path, '-C', archive_dir],
                capture_output=True,
                text=True
            )
            if result.returncode != 0:
                return False, f"tar failed: {result.stderr}"
        
        elif lower_name.endswith(('.tar.bz2', '.tbz2')):
            # Use tar command for .tar.bz2 and .tbz2
            result = subprocess.run(
                ['tar', '-xjf', archive_path, '-C', archive_dir],
                capture_output=True,
                text=True
            )
            if result.returncode != 0:
                return False, f"tar failed: {result.stderr}"
        
        elif lower_name.endswith(('.tar.xz', '.txz')):
            # Use tar command for .tar.xz and .txz
            result = subprocess.run(
                ['tar', '-xJf', archive_path, '-C', archive_dir],
                capture_output=True,
                text=True
            )
            if result.returncode != 0:
                return False, f"tar failed: {result.stderr}"
        
        elif lower_name.endswith('.tar'):
            # Use tar command for .tar
            result = subprocess.run(
                ['tar', '-xf', archive_path, '-C', archive_dir],
                capture_output=True,
                text=True
            )
            if result.returncode != 0:
                return False, f"tar failed: {result.stderr}"
        
        elif lower_name.endswith('.gz') and not lower_name.endswith('.tar.gz'):
            # Use gunzip for standalone .gz files
            # gunzip removes the .gz extension automatically
            result = subprocess.run(
                ['gunzip', '-kf', archive_path],
                capture_output=True,
                text=True
            )
            if result.returncode != 0:
                return False, f"gunzip failed: {result.stderr}"
        
        elif lower_name.endswith('.bz2') and not lower_name.endswith('.tar.bz2'):
            # Use bunzip2 for standalone .bz2 files
            result = subprocess.run(
                ['bunzip2', '-kf', archive_path],
                capture_output=True,
                text=True
            )
            if result.returncode != 0:
                return False, f"bunzip2 failed: {result.stderr}"
        
        elif lower_name.endswith('.xz') and not lower_name.endswith('.tar.xz'):
            # Use unxz for standalone .xz files
            result = subprocess.run(
                ['unxz', '-kf', archive_path],
                capture_output=True,
                text=True
            )
            if result.returncode != 0:
                return False, f"unxz failed: {result.stderr}"
        
        elif lower_name.endswith('.7z'):
            # Use 7z command
            result = subprocess.run(
                ['7z', 'x', '-y', f'-o{archive_dir}', archive_path],
                capture_output=True,
                text=True
            )
            if result.returncode != 0:
                return False, f"7z failed: {result.stderr}"
        
        elif lower_name.endswith('.rar'):
            # Use unrar command
            result = subprocess.run(
                ['unrar', 'x', '-y', '-o+', archive_path, archive_dir],
                capture_output=True,
                text=True
            )
            if result.returncode != 0:
                return False, f"unrar failed: {result.stderr}"
        
        else:
            return False, "Unknown archive format"
        
        return True, "Success"
    
    except FileNotFoundError as e:
        return False, f"Extraction tool not found: {e.filename}"
    except Exception as e:
        return False, f"Unexpected error: {str(e)}"

# Process each archive
for i, archive in enumerate(archives, 1):
    print(f"[{i}/{total}] Processing: {archive}")
    
    success, message = extract_archive(archive)
    
    if success:
        print(f"  ✓ Extracted successfully")
        # Remove the original archive
        try:
            os.remove(archive)
            print(f"  ✓ Removed original archive")
            extracted += 1
        except Exception as e:
            print(f"  ✗ Failed to remove archive: {e}")
            failed += 1
    else:
        print(f"  ✗ Extraction failed: {message}")
        print(f"  → Archive preserved: {archive}")
        failed += 1
    print()

# Print summary
print("=" * 60)
print("EXTRACTION SUMMARY")
print(f"  Total archives found:     {total}")
print(f"  Successfully extracted:   {extracted}")
print(f"  Failed extractions:       {failed}")
print(f"  Skipped:                  {skipped}")
print("=" * 60)

if failed > 0:
    print()
    print("Note: Archives that failed to extract were preserved.")
    sys.exit(1)

PY

echo ""
echo "Extraction process completed."
