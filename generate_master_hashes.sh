
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

# Extract existing paths from master CSV (first column, unquoted)
if [ -s "$OUT" ]; then
  awk -F, 'NR>1{p=$1; gsub(/^\s*"?/,"",p); gsub(/"?\s*$/,"",p); print p}' "$OUT" > "$TMP_EXISTING_PATHS"
fi

# Worker: compute hash for a single file and print CSV line.
# We use a single output stream so parallel workers can write safely.

export HASH_PROG HASH_ARGS TMP_EXISTING_PATHS

find "$DIR" -type f ! -name "master_hashes.csv" -print0 |
	xargs -0 -n1 -P "$CONCURRENCY" sh -c '\
f="$1"

# Defensive check: only hash if it is a regular file
if [ ! -f "$f" ]; then
	printf "SKIPPING (not a regular file): %s\n" "$f" >&2
	exit 0
fi

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

# Skip if we still could not compute a valid digest
if [ -z "$digest" ]; then
	printf "WARNING: Failed to compute hash for: %s\n" "$f" >&2
	exit 0
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

# Extract existing digests from master (third CSV column), strip quotes/spaces
awk -F, 'NR>1{g=$3; gsub(/^\s*"?/,"",g); gsub(/"?\s*$/,"",g); print g}' "$OUT" > "$TMP_EXIST" || true

# Extract new digests
awk -F, '{g=$3; gsub(/^\s*"?/,"",g); gsub(/"?\s*$/,"",g); print g}' "$TMP_NEW" > "$TMP_NEW_DIG"

# Check for duplicates within new digests
if sort "$TMP_NEW_DIG" | uniq -d | grep -q .; then
  echo "Error: duplicate digests found within new files to add. Aborting." >&2
  echo "" >&2
  echo "EXPLANATION: Multiple files in the directory have identical content (same hash)." >&2
  echo "This indicates duplicate files exist in the source directory itself." >&2
  echo "Please remove duplicates from the source directory first, or use fdupes to clean them up." >&2
  echo "" >&2
  echo "Files with duplicate content:" >&2
  # Show files grouped by their duplicate hashes
  sort "$TMP_NEW_DIG" | uniq -d | while read -r dup_hash; do
    echo "  Hash: $dup_hash" >&2
    grep -F "\"$dup_hash\"" "$TMP_NEW" | awk -F, '{gsub(/^\\s*"?/,"",$1); gsub(/"?\\s*$/,"",$1); print "    - " $1}' >&2
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
  # Show new files that have hashes already in master
  grep -Fxf "$TMP_NEW_DIG" "$TMP_EXIST" | sort -u | head -10 | while read -r dup_hash; do
    echo "  Hash: $dup_hash" >&2
    # Show new files with this hash
    grep -F "\"$dup_hash\"" "$TMP_NEW" | awk -F, '{gsub(/^\\s*"?/,"",$1); gsub(/"?\\s*$/,"",$1); print "    New file: " $1}' >&2
    # Show existing files in master with this hash
    grep -F "\"$dup_hash\"" "$OUT" | awk -F, '{gsub(/^\\s*"?/,"",$1); gsub(/"?\\s*$/,"",$1); print "    In master: " $1}' | head -3 >&2
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
