
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

# Prepare temporary files (auto-cleanup on exit)
TMP_NEW=$(mktemp -t master_hashes.new.XXXXXX) || exit 1
TMP_EXIST=$(mktemp -t master_hashes.exist.XXXXXX) || { rm -f "$TMP_NEW"; exit 1; }
TMP_NEW_DIG=$(mktemp -t master_hashes.newdig.XXXXXX) || { rm -f "$TMP_NEW" "$TMP_EXIST"; exit 1; }
trap 'rm -f "$TMP_NEW" "$TMP_EXIST" "$TMP_NEW_DIG"' EXIT

# Worker: compute hash for a single file and print CSV line.
# We use a single output stream so parallel workers can write safely.

export HASH_PROG HASH_ARGS

find "$DIR" -type f -print0 |
	xargs -0 -n1 -P "$CONCURRENCY" sh -c '\
f="$1"
# compute hash (capture only the digest)
digest=$($HASH_PROG $HASH_ARGS "$f" 2>/dev/null | awk "{print \$1}")
# fallback if digest empty
if [ -z "$digest" ]; then
	# try openssl if available
	if command -v openssl >/dev/null 2>&1; then
		digest=$(openssl dgst -sha256 -r "$f" 2>/dev/null | awk "{print \$1}")
	fi
fi
# compute path and filename
# compute filename and absolute path
filename=$(basename -- "$f")
if command -v realpath >/dev/null 2>&1; then
	fullpath=$(realpath "$f")
elif command -v readlink >/dev/null 2>&1; then
	fullpath=$(readlink -f "$f")
else
	# python fallback for absolute path
	fullpath=$(python3 -c "import os,sys;print(os.path.abspath(sys.argv[1]))" "$f")
fi
# escape double-quotes for CSV fields
esc() {
	s="$1"
	s=${s//\"/\"\"}
	printf '"%s"' "$s"
}
printf "%s,%s,%s\n" "$(esc "$fullpath")" "$(esc "$filename")" "$(esc "$digest")"
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
  sort "$TMP_NEW_DIG" | uniq -d >&2
  exit 6
fi

# Check for digests that already exist in master
if [ -s "$TMP_EXIST" ] && grep -Fxf "$TMP_NEW_DIG" "$TMP_EXIST" >/dev/null 2>&1; then
  echo "Error: one or more computed digests already exist in $OUT. Aborting to avoid duplicates." >&2
  grep -Fxf "$TMP_NEW_DIG" "$TMP_EXIST" | sort -u >&2
  exit 7
fi

# Append new entries to master
cat "$TMP_NEW" >> "$OUT"
echo "Appended $(wc -l < "$TMP_NEW" | tr -d ' ') rows to $OUT"
