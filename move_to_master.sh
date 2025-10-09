#!/usr/bin/env bash
set -euo pipefail

# move_to_master.sh
# Moves files from a compared folder to the master folder after verifying
# they are not duplicates (by checking hashes against master_hashes.csv).
#
# Usage:
#   ./move_to_master.sh <compared_folder> <master_folder>
#
# The script will:
# - Read hash_file.csv from the compared folder
# - Compare hashes against master_hashes.csv
# - Move only non-duplicate files to the master folder
# - Update master_hashes.csv with the newly moved files

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <compared_folder> <master_folder>" >&2
  exit 2
fi

COMPARED_DIR="$1"
MASTER_DIR="$2"

# Validate directories
if [ ! -d "$COMPARED_DIR" ]; then
  echo "Error: Compared directory not found: $COMPARED_DIR" >&2
  exit 3
fi

if [ ! -d "$MASTER_DIR" ]; then
  echo "Error: Master directory not found: $MASTER_DIR" >&2
  exit 4
fi

# Check for required files
COMPARED_CSV="$COMPARED_DIR/hash_file.csv"
MASTER_CSV="master_hashes.csv"

if [ ! -f "$COMPARED_CSV" ]; then
  echo "Error: hash_file.csv not found in compared folder: $COMPARED_CSV" >&2
  exit 5
fi

if [ ! -f "$MASTER_CSV" ]; then
  echo "Warning: master_hashes.csv not found. Creating new file." >&2
  printf '%s\n' "fullpath,filename,sha256" > "$MASTER_CSV"
fi

echo "Moving unique files from compared folder to master folder..."
echo "Compared folder: $COMPARED_DIR"
echo "Master folder: $MASTER_DIR"
echo ""

# Use Python to compare hashes and move files
python3 - "$COMPARED_CSV" "$MASTER_CSV" "$COMPARED_DIR" "$MASTER_DIR" <<'PY'
import csv
import sys
import os
import shutil

compared_csv = sys.argv[1]
master_csv = sys.argv[2]
compared_dir = sys.argv[3]
master_dir = sys.argv[4]

def rows_from_csv(path):
    """Read CSV rows, skipping markdown fences and headers"""
    with open(path, newline='', encoding='utf-8') as fh:
        def gen():
            for line in fh:
                if line.strip().startswith('```'):
                    continue
                yield line
        reader = csv.reader(gen())
        for row in reader:
            if not row:
                continue
            # Skip header-like rows
            low = [c.strip().lower() for c in row]
            if any(('path' in c or 'fullpath' in c or 'filename' in c or 'sha' in c) for c in low):
                continue
            yield row

def normalize_row(row):
    """Extract path, filename, digest from a CSV row"""
    if len(row) < 3:
        joined = ','.join(row)
        parts = [p.strip() for p in joined.split(',')]
        parts += ['']*(3-len(parts))
        row = parts
    path, filename, digest = row[0].strip(), row[1].strip(), row[2].strip()
    return path, filename, digest

# Load master hashes (digest -> list of paths)
master_digests = set()
master_paths = set()
for row in rows_from_csv(master_csv):
    path, _, digest = normalize_row(row)
    if digest:
        master_digests.add(digest)
    if path:
        master_paths.add(os.path.abspath(path))

print(f'Loaded {len(master_digests)} unique digests from master CSV', file=sys.stderr)
print(f'Loaded {len(master_paths)} unique paths from master CSV', file=sys.stderr)

# Process compared files
files_to_move = []
duplicates_skipped = []
already_in_master_location = []

for row in rows_from_csv(compared_csv):
    path, filename, digest = normalize_row(row)
    if not digest or not path:
        continue
    
    # Check if this digest already exists in master
    if digest in master_digests:
        duplicates_skipped.append((path, filename, digest))
        print(f'  [SKIP] {filename} - duplicate hash already in master', file=sys.stderr)
        continue
    
    # Check if file is already in master directory (might be from previous run)
    abs_path = os.path.abspath(path)
    if abs_path in master_paths:
        already_in_master_location.append((path, filename))
        print(f'  [SKIP] {filename} - already at master location', file=sys.stderr)
        continue
    
    # File is unique, add to move list
    files_to_move.append((path, filename, digest))

print()
print(f'Summary:')
print(f'  Files to move to master: {len(files_to_move)}')
print(f'  Duplicates skipped (hash already exists): {len(duplicates_skipped)}')
print(f'  Files already in master location: {len(already_in_master_location)}')
print()

# Log detailed information about why files were skipped
if duplicates_skipped:
    print(f'Files skipped due to duplicate hashes (first 10 shown):', file=sys.stderr)
    for i, (path, filename, digest) in enumerate(duplicates_skipped[:10]):
        print(f'  [{i+1}] {filename} (hash: {digest[:16]}...)', file=sys.stderr)
    if len(duplicates_skipped) > 10:
        print(f'  ... and {len(duplicates_skipped)-10} more', file=sys.stderr)
    print(file=sys.stderr)

if already_in_master_location:
    print(f'Files already in master location (first 10 shown):', file=sys.stderr)
    for i, (path, filename) in enumerate(already_in_master_location[:10]):
        print(f'  [{i+1}] {filename}', file=sys.stderr)
    if len(already_in_master_location) > 10:
        print(f'  ... and {len(already_in_master_location)-10} more', file=sys.stderr)
    print(file=sys.stderr)

if not files_to_move:
    print('No unique files to move.')
    sys.exit(0)

# Show files that will be moved
print(f'Files to move (first 20 of {len(files_to_move)} shown):')
for i, (path, filename, _) in enumerate(files_to_move[:20]):
    print(f'  [{i+1}] {filename}')
if len(files_to_move) > 20:
    print(f'  ... and {len(files_to_move)-20} more')
print()

# Move files
moved = 0
errors = 0
skipped_already_exists = 0
new_rows = []

print('Processing files...', file=sys.stderr)

for path, filename, digest in files_to_move:
    try:
        # Verify source file exists
        if not os.path.exists(path):
            print(f'Warning: Source file not found: {path}', file=sys.stderr)
            errors += 1
            continue
        
        # Calculate destination path (preserve relative structure if possible)
        if path.startswith(compared_dir + os.sep):
            rel_path = os.path.relpath(path, compared_dir)
        else:
            rel_path = filename
        
        dest_path = os.path.join(master_dir, rel_path)
        dest_dir = os.path.dirname(dest_path)
        
        # Create destination directory if needed
        if not os.path.exists(dest_dir):
            os.makedirs(dest_dir)
            print(f'  Created directory: {dest_dir}', file=sys.stderr)
        
        # Check if destination file exists
        original_dest = dest_path
        if os.path.exists(dest_path):
            # Calculate hash of existing file to check if it's truly different
            import hashlib
            with open(dest_path, 'rb') as f:
                existing_hash = hashlib.sha256(f.read()).hexdigest()
            
            if existing_hash == digest:
                # Same content, skip the move
                print(f'  [SKIP] {filename} - identical file already exists at destination', file=sys.stderr)
                skipped_already_exists += 1
                # Don't add to master CSV since it should already be there
                continue
            else:
                # Different content, add suffix to avoid overwriting
                print(f'  [WARNING] File exists with different content: {dest_path}', file=sys.stderr)
                print(f'    Existing hash: {existing_hash[:16]}...', file=sys.stderr)
                print(f'    New file hash: {digest[:16]}...', file=sys.stderr)
                base, ext = os.path.splitext(dest_path)
                counter = 1
                while os.path.exists(f"{base}_{counter}{ext}"):
                    counter += 1
                dest_path = f"{base}_{counter}{ext}"
                print(f'    Renaming to: {os.path.basename(dest_path)}', file=sys.stderr)
        
        # Move the file
        shutil.move(path, dest_path)
        moved += 1
        print(f'  [MOVED] {filename} -> {dest_path}', file=sys.stderr)
        
        # Add to new rows for master CSV (use absolute path)
        abs_dest = os.path.abspath(dest_path)
        new_rows.append([abs_dest, filename, digest])
        
    except Exception as e:
        print(f'  [ERROR] Failed to move {path}: {e}', file=sys.stderr)
        errors += 1

# Update master CSV with new files
if new_rows:
    print(f'\nVerifying new entries before adding to master CSV...', file=sys.stderr)
    
    # Before adding, verify none of these digests already exist in master
    new_digests = {row[2] for row in new_rows}
    duplicate_digests = new_digests & master_digests
    
    if duplicate_digests:
        print(f'ERROR: Attempted to add {len(duplicate_digests)} duplicate digest(s) to master CSV!', file=sys.stderr)
        print(f'This should not happen. Duplicate digests:', file=sys.stderr)
        for dig in list(duplicate_digests)[:5]:
            print(f'  {dig}', file=sys.stderr)
        print(f'ABORTING update to master CSV to prevent corruption.', file=sys.stderr)
        sys.exit(10)
    
    # Write new entries
    with open(master_csv, 'a', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        for row in new_rows:
            writer.writerow(row)
    print(f'Successfully updated {master_csv} with {len(new_rows)} new entries', file=sys.stderr)

print()
print(f'===== MOVE TO MASTER SUMMARY =====')
print(f'Files successfully moved:    {moved}')
print(f'Files skipped (same content): {skipped_already_exists}')
print(f'Errors encountered:          {errors}')
print(f'Master CSV entries added:    {len(new_rows)}')
print()

if moved > 0:
    print(f'✓ Successfully moved {moved} unique file(s) to master folder')
if skipped_already_exists > 0:
    print(f'ℹ Skipped {skipped_already_exists} file(s) already in destination with same content')
if errors > 0:
    print(f'⚠ {errors} error(s) occurred during move operation')
    sys.exit(1)
PY

echo "Done."
