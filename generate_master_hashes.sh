
#!/usr/bin/env bash
set -euo pipefail

# generate_csv.sh
# Recursively walk a directory (default: current directory), compute SHA-256
# for every regular file in parallel (8 workers) and write results to
# master_hashes.csv with columns: path,filename,sha256
#
# Usage:
#   ./generate_csv.sh [directory]
# Example:
#   ./generate_csv.sh /path/to/data

DIR=${1:-.}
OUT="master_hashes.csv"
CONCURRENCY=${CONCURRENCY:-32}

# Detect available SHA-256 tool (prefer sha256sum, fallback to shasum)
if command -v sha256sum >/dev/null 2>&1; then
	HASH_PROG=sha256sum
	HASH_ARGS="--"
elif command -v shasum >/dev/null 2>&1; then
	HASH_PROG=shasum
	HASH_ARGS="-a 256 --"
else
	echo "Error: neither sha256sum nor shasum is available on PATH." >&2
	echo "Install coreutils (sha256sum) or use a system with shasum." >&2
	exit 2
fi

# If master CSV missing, create with header; otherwise keep it and append after checks
if [ ! -f "$OUT" ]; then
  printf '%s\n' "fullpath,filename,sha256" > "$OUT"
fi

echo "Scanning directory: $DIR" >&2

# Prepare temporary files (auto-cleanup on exit)
TMP_NEW=$(mktemp -t master_hashes.new.XXXXXX) || exit 1
TMP_EXIST=$(mktemp -t master_hashes.exist.XXXXXX) || { rm -f "$TMP_NEW"; exit 1; }
TMP_NEW_DIG=$(mktemp -t master_hashes.newdig.XXXXXX) || { rm -f "$TMP_NEW" "$TMP_EXIST"; exit 1; }
TMP_EXISTING_PATHS=$(mktemp -t master_hashes.existing.XXXXXX) || { rm -f "$TMP_NEW" "$TMP_EXIST" "$TMP_NEW_DIG"; exit 1; }
trap 'rm -f "$TMP_NEW" "$TMP_EXIST" "$TMP_NEW_DIG" "$TMP_EXISTING_PATHS"' EXIT

# Extract existing paths from master CSV (first column) using proper CSV parsing
if [ -s "$OUT" ]; then
  python3 -c "
import csv, sys
with open('$OUT', 'r', encoding='utf-8') as f:
    reader = csv.reader(f)
    next(reader, None)  # skip header
    for row in reader:
        if len(row) >= 1:
            print(row[0].strip())
" > "$TMP_EXISTING_PATHS"
fi

# Worker: compute hash for a single file and print CSV line.
# We use a single output stream so parallel workers can write safely.

export HASH_PROG HASH_ARGS TMP_EXISTING_PATHS

find "$DIR" -type f ! -name "master_hashes.csv" -print0 |
	xargs -0 -n1 -P "$CONCURRENCY" sh -c '\
f="$1"

# Get absolute path first
if command -v realpath >/dev/null 2>&1; then
	fullpath=$(realpath "$f")
elif command -v readlink >/dev/null 2>&1; then
	fullpath=$(readlink -f "$f")
else
	# python fallback for absolute path
	fullpath=$(python3 -c "import os,sys;print(os.path.abspath(sys.argv[1]))" "$f")
fi

# Check if this file is already in the CSV (skip if it exists)
if [ -s "$TMP_EXISTING_PATHS" ] && grep -Fxq "$fullpath" "$TMP_EXISTING_PATHS"; then
	printf "SKIPPING (already in master): %s\n" "$f" >&2
	exit 0
fi

printf "HASHING: %s\n" "$f" >&2
# compute hash (capture only the digest)
# compute hash (capture only the digest)
digest=$($HASH_PROG $HASH_ARGS "$f" 2>/dev/null | awk "{print \$1}")
# fallback if digest empty
if [ -z "$digest" ]; then
	# try openssl if available
	if command -v openssl >/dev/null 2>&1; then
		digest=$(openssl dgst -sha256 -r "$f" 2>/dev/null | awk "{print \$1}")
	fi
fi
# Validate that digest is a valid SHA256 (64 hex characters)
if [ -n "$digest" ]; then
	digest_len=$(echo -n "$digest" | wc -c | tr -d " ")
	if [ "$digest_len" -ne 64 ]; then
		printf "WARNING: Invalid hash length for file: %s\n" "$f" >&2
		printf "  Hash: [%s] (length: %s, expected: 64)\n" "$digest" "$digest_len" >&2
	elif ! echo "$digest" | grep -qE "^[a-fA-F0-9]{64}$"; then
		printf "WARNING: Hash contains non-hex characters for file: %s\n" "$f" >&2
		printf "  Hash: [%s]\n" "$digest" >&2
	fi
fi
# compute filename
filename=$(basename -- "$f")
# escape double-quotes for CSV fields (replace " with "")
esc_fullpath=$(echo "$fullpath" | sed "s/\"/\"\"/g")
esc_filename=$(echo "$filename" | sed "s/\"/\"\"/g")
esc_digest=$(echo "$digest" | sed "s/\"/\"\"/g")
printf "\"%s\",\"%s\",\"%s\"\n" "$esc_fullpath" "$esc_filename" "$esc_digest"
' sh > "$TMP_NEW"

# If no new entries, exit cleanly
if [ ! -s "$TMP_NEW" ]; then
  echo "No files found under $DIR; nothing to append." >&2
  exit 0
fi

# Extract existing digests from master (third CSV column) using proper CSV parsing
python3 -c "
import csv, sys
with open('$OUT', 'r', encoding='utf-8') as f:
    reader = csv.reader(f)
    next(reader, None)  # skip header
    for row in reader:
        if len(row) >= 3:
            print(row[2].strip())
" > "$TMP_EXIST" || true

# Extract new digests using proper CSV parsing with validation
python3 -c "
import csv, sys, re
hash_pattern = re.compile(r'^[a-fA-F0-9]{64}$')
with open('$TMP_NEW', 'r', encoding='utf-8') as f:
    reader = csv.reader(f)
    for row in reader:
        if len(row) >= 3:
            digest = row[2].strip()
            # Validate SHA256 format (64 hex characters)
            if not hash_pattern.match(digest):
                print(f'WARNING: Invalid SHA256 hash detected!', file=sys.stderr)
                print(f'  File: {row[0]}', file=sys.stderr)
                print(f'  Filename: {row[1]}', file=sys.stderr)
                print(f'  Hash value: [{digest}] (length: {len(digest)})', file=sys.stderr)
                print(f'  Expected: 64 hexadecimal characters', file=sys.stderr)
            print(digest)
" > "$TMP_NEW_DIG"

# Check for duplicates within new digests
if sort "$TMP_NEW_DIG" | uniq -d | grep -q .; then
  echo "Error: duplicate digests found within new files to add. Aborting." >&2
  echo "" >&2
  echo "EXPLANATION: Multiple files in the directory have identical content (same hash)." >&2
  echo "This indicates duplicate files exist in the source directory itself." >&2
  echo "Please remove duplicates from the source directory first, or use fdupes to clean them up." >&2
  echo "" >&2
  echo "Files with duplicate content:" >&2
  # Show files grouped by their duplicate hashes with proper CSV parsing
  sort "$TMP_NEW_DIG" | uniq -d | while read -r dup_hash; do
    echo "  Hash: $dup_hash" >&2
    # Use Python to properly parse CSV and find matching files
    python3 -c "
import csv, sys
hash_to_find = sys.argv[1]
with open('$TMP_NEW', 'r', encoding='utf-8') as f:
    reader = csv.reader(f)
    for row in reader:
        if len(row) >= 3 and row[2].strip() == hash_to_find:
            print(f'    - {row[0]}')
" "$dup_hash" >&2
  done
  exit 6
fi

# Check for digests that already exist in master
if [ -s "$TMP_EXIST" ] && grep -Fxf "$TMP_NEW_DIG" "$TMP_EXIST" >/dev/null 2>&1; then
  echo "Error: one or more computed digests already exist in $OUT. Aborting to avoid duplicates." >&2
  echo "" >&2
  echo "EXPLANATION: Files you're trying to add have the same content (hash) as files already in master." >&2
  echo "This is the safety check that prevents adding duplicate entries to master_hashes.csv." >&2
  echo "" >&2
  echo "WHAT THIS MEANS:" >&2
  echo "  - These files were likely already processed in a previous run" >&2
  echo "  - OR: The same files exist in both the master and the directory being scanned" >&2
  echo "  - OR: You're trying to re-run the script on files already in master" >&2
  echo "" >&2
  echo "WHAT TO DO:" >&2
  echo "  1. If these files are already in master folder: This is expected, no action needed" >&2
  echo "  2. If you need to re-scan: Delete or backup master_hashes.csv and regenerate from scratch" >&2
  echo "  3. If files are in a different location: These are true duplicates (same content)" >&2
  echo "" >&2
  echo "New files that match existing master hashes (showing first 10):" >&2
  # Show new files that have hashes already in master with proper CSV parsing
  grep -Fxf "$TMP_NEW_DIG" "$TMP_EXIST" | sort -u | head -10 | while read -r dup_hash; do
    echo "  Hash: $dup_hash" >&2
    # Show new files with this hash using Python CSV parsing
    python3 -c "
import csv, sys
hash_to_find = sys.argv[1]
with open('$TMP_NEW', 'r', encoding='utf-8') as f:
    reader = csv.reader(f)
    for row in reader:
        if len(row) >= 3 and row[2].strip() == hash_to_find:
            print(f'    New file: {row[0]}')
" "$dup_hash" >&2
    # Show existing files in master with this hash using Python CSV parsing
    python3 -c "
import csv, sys
hash_to_find = sys.argv[1]
count = 0
with open('$OUT', 'r', encoding='utf-8') as f:
    reader = csv.reader(f)
    next(reader, None)  # skip header
    for row in reader:
        if len(row) >= 3 and row[2].strip() == hash_to_find:
            print(f'    In master: {row[0]}')
            count += 1
            if count >= 3:
                break
" "$dup_hash" >&2
  done
  TOTAL_DUPS=$(grep -Fxf "$TMP_NEW_DIG" "$TMP_EXIST" | sort -u | wc -l | tr -d ' ')
  if [ "$TOTAL_DUPS" -gt 10 ]; then
    echo "... and $((TOTAL_DUPS - 10)) more duplicate hash(es)" >&2
  fi
  exit 7
fi

# Append new entries to master
cat "$TMP_NEW" >> "$OUT"
echo "Appended $(wc -l < "$TMP_NEW" | tr -d ' ') rows to $OUT"
