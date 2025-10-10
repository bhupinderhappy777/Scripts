#!/usr/bin/env bash
set -euo pipefail

DIR=${1:-.}
OUT="$DIR/hash_file.csv"
CONCURRENCY=32

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

# If hash file doesn't exist, create with header; otherwise we'll append
if [ ! -f "$OUT" ]; then
  printf '%s\n' "fullpath,filename,sha256" > "$OUT"
fi

echo "Scanning directory: $DIR" >&2

# Prepare temporary files (auto-cleanup on exit)
TMP_NEW=$(mktemp -t hash_file.new.XXXXXX) || exit 1
TMP_EXISTING_PATHS=$(mktemp -t hash_file.existing.XXXXXX) || { rm -f "$TMP_NEW"; exit 1; }
trap 'rm -f "$TMP_NEW" "$TMP_EXISTING_PATHS"' EXIT

# Extract existing paths from hash file CSV (first column) using proper CSV parsing
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

export HASH_PROG HASH_ARGS TMP_EXISTING_PATHS

find "$DIR" -type f ! -name "hash_file.csv" -print0 | \
    xargs -0 -n1 -P "$CONCURRENCY" sh -c '
f="$1"

# Get absolute path first
if command -v realpath >/dev/null 2>&1; then
    fullpath=$(realpath "$f")
elif command -v readlink >/dev/null 2>&1; then
    fullpath=$(readlink -f "$f")
else
    fullpath=$(python3 -c "import os,sys;print(os.path.abspath(sys.argv[1]))" "$f")
fi

# Check if this file is already in the CSV (skip if it exists)
if [ -s "$TMP_EXISTING_PATHS" ] && grep -Fxq "$fullpath" "$TMP_EXISTING_PATHS"; then
    printf "SKIPPING (already in hash_file): %s\n" "$f" >&2
    exit 0
fi

printf "HASHING: %s\n" "$f" >&2
digest=$($HASH_PROG $HASH_ARGS "$f" 2>/dev/null | awk "{print \$1}")
if [ -z "$digest" ]; then
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
filename=$(basename -- "$f")
# escape double-quotes for CSV fields (replace " with "")
esc_fullpath=$(echo "$fullpath" | sed "s/\"/\"\"/g")
esc_filename=$(echo "$filename" | sed "s/\"/\"\"/g")
esc_digest=$(echo "$digest" | sed "s/\"/\"\"/g")
printf "\"%s\",\"%s\",\"%s\"\n" "$esc_fullpath" "$esc_filename" "$esc_digest"
' sh > "$TMP_NEW"

# Append new entries to hash file
if [ -s "$TMP_NEW" ]; then
  cat "$TMP_NEW" >> "$OUT"
  echo "Appended $(wc -l < "$TMP_NEW" | tr -d ' ') new rows to $OUT"
else
  echo "No new files to add to $OUT"
fi

echo "Hash file is at: $OUT"