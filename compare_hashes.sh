#!/usr/bin/env bash
set -euo pipefail

# compare_hashes.sh
# Usage: ./compare_hashes.sh /path/to/compared/folder
# Looks for "hash_file.csv" inside the given folder, compares its hashes
# against the master hash CSV in the current directory (prefers
# master_hasher.csv, falls back to master_hashes.csv). Writes a comparison
# CSV named after the compared folder.

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /path/to/compared/folder" >&2
  exit 2
fi

TARGET_DIR="$1"
TARGET_CSV="$TARGET_DIR/hash_file.csv"

if [ ! -f "$TARGET_CSV" ]; then
  echo "Error: hash file not found: $TARGET_CSV" >&2
  exit 3
fi

# Prefer master_hasher.csv, then master_hashes.csv
if [ -f master_hasher.csv ]; then
  MASTER_CSV="master_hasher.csv"
elif [ -f master_hashes.csv ]; then
  MASTER_CSV="master_hashes.csv"
else
  echo "Error: no master_hasher.csv or master_hashes.csv found in current directory." >&2
  exit 4
fi

# Create a safe output filename from the target dir path
safe_name() {
  local s="$1"
  # remove trailing slash/backslash
  s=${s%/}
  s=${s%\\}
  # replace drive colon (Windows) and path separators with underscore
  s=${s//:/}
  s=${s//\\/_}
  s=${s//\/_}
  # replace other unsafe chars with underscore
  s=$(echo "$s" | sed -E 's/[^A-Za-z0-9._-]/_/g')
  printf '%s' "$s"
}

OUT="$(safe_name "$TARGET_DIR").comparison.csv"

echo "Comparing hashes: master='$MASTER_CSV'  target='$TARGET_CSV' -> $OUT"

echo "Reading master CSV and target CSV..." >&2

# Use embedded Python for robust CSV parsing (handles quoted fields and
# ignores surrounding markdown fences like ``` or ```csv that may be in files)
python3 - <<'PY'
import csv,sys,os

master = os.path.abspath(sys.argv[1]) if False else None
PY

python3 - "$MASTER_CSV" "$TARGET_CSV" "$OUT" <<'PY'
import csv,sys,os

MASTER_CSV = sys.argv[1]
TARGET_CSV = sys.argv[2]
OUT = sys.argv[3]

def rows_from_csv(path):
    with open(path, newline='', encoding='utf-8') as fh:
        # filter out lines that are markdown fences (```...)
        def gen():
            for line in fh:
                if line.strip().startswith('```'):
                    continue
                yield line
        reader = csv.reader(gen())
        for row in reader:
            if not row:
                continue
            # skip header-like rows (contain column names)
            low = [c.strip().lower() for c in row]
            if any(('path' in c or 'fullpath' in c or 'filename' in c or 'sha' in c) for c in low):
                continue
            yield row

def normalize_row(row):
    # Expect at least 3 columns: path/fullpath, filename, sha256
    if len(row) < 3:
        # try splitting on commas as last resort
        joined = ','.join(row)
        parts = [p.strip() for p in joined.split(',')]
        # pad
        parts += ['']*(3-len(parts))
        row = parts
    path, filename, digest = row[0].strip(), row[1].strip(), row[2].strip()
    return path, filename, digest

master_map = {}
for row in rows_from_csv(MASTER_CSV):
    path, filename, digest = normalize_row(row)
    if not digest:
        continue
    master_map.setdefault(digest, []).append((path, filename))

print(f'Read {len(master_map)} unique digests from master', file=sys.stderr)

target_map = {}
for row in rows_from_csv(TARGET_CSV):
    path, filename, digest = normalize_row(row)
    if not digest:
        continue
    target_map.setdefault(digest, []).append((path, filename))

print(f'Read {len(target_map)} unique digests from target', file=sys.stderr)

# Build comparison rows: for every digest present in both, produce all combinations
rows = []
for digest, masters in master_map.items():
    targets = target_map.get(digest)
    if not targets:
        continue
    for mp, mf in masters:
        for tp, tf in targets:
            rows.append((mp, tp, mf, tf))

with open(OUT, 'w', newline='', encoding='utf-8') as outfh:
    writer = csv.writer(outfh)
    writer.writerow(['master_path','compared_path','master_filename','compared_filename'])
    for r in rows:
        writer.writerow(r)

if rows:
    print(f'Wrote {len(rows)} matching rows to {OUT}')
else:
    print(f'No matches found. Wrote header to {OUT}')
PY

echo "Done."
