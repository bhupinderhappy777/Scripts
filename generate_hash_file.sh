#!/usr/bin/env bash
set -euo pipefail

DIR=${1:-.}
OUT="hash_file.csv"
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

# Write CSV header (full absolute path in first column)
printf '%s\n' "fullpath,filename,sha256" > "$OUT"

echo "Scanning directory: $DIR" >&2

export HASH_PROG HASH_ARGS

find "$DIR" -type f -print0 | \
    xargs -0 -n1 -P "$CONCURRENCY" sh -c '
f="$1"
printf "HASHING: %s\n" "$f" >&2
digest=$($HASH_PROG $HASH_ARGS "$f" 2>/dev/null | awk "{print \$1}")
if [ -z "$digest" ]; then
    if command -v openssl >/dev/null 2>&1; then
        digest=$(openssl dgst -sha256 -r "$f" 2>/dev/null | awk "{print \$1}")
    fi
fi
filename=$(basename -- "$f")
if command -v realpath >/dev/null 2>&1; then
    fullpath=$(realpath "$f")
elif command -v readlink >/dev/null 2>&1; then
    fullpath=$(readlink -f "$f")
else
    fullpath=$(python3 -c "import os,sys;print(os.path.abspath(sys.argv[1]))" "$f")
fi
esc() {
    s="$1"
    s=${s//\"/\"\"}
    printf "\"%s\"" "$s"
}
printf "%s,%s,%s\n" "$(esc "$fullpath")" "$(esc "$filename")" "$(esc "$digest")"
' sh >> "$OUT"

echo "Wrote hashes to $OUT"