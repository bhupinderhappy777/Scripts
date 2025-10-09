#!/usr/bin/env bash
set -euo pipefail

# deletion.sh
# Deletes files listed in the "compared_path" (and compared_filename) column
# of a comparison CSV produced by compare_hashes.sh. By default it looks for a
# single "*.comparison.csv" file in the current directory. Usage:
#
#   ./deletion.sh [-n] [-y] [-f comparison.csv]
#
# Options:
#   -n    dry-run: show what would be deleted but don't remove files
#   -y    auto-confirm (don't prompt)
#   -f    path to comparison csv (overrides auto-detect)

DRYRUN=0
CONFIRM=0
CSVFILE=""

while getopts ":nyf:" opt; do
  case $opt in
    n) DRYRUN=1 ;;
    y) CONFIRM=1 ;;
    f) CSVFILE="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit 2 ;;
  esac
done

if [ -z "$CSVFILE" ]; then
  # find comparison CSVs
  matches=( *.comparison.csv )
  # if the glob didn't match, bash returns the literal pattern; handle that
  if [ "${matches[0]}" = "*.comparison.csv" ]; then
    matches=()
  fi
  if [ ${#matches[@]} -eq 0 ]; then
    echo "No *.comparison.csv file found in current directory. Use -f to specify one." >&2
    exit 3
  elif [ ${#matches[@]} -gt 1 ]; then
    echo "Multiple comparison CSVs found:" >&2
    for m in "${matches[@]}"; do echo "  $m"; done >&2
    echo "Specify which to use with -f" >&2
    exit 4
  else
    CSVFILE="${matches[0]}"
  fi
fi

if [ ! -f "$CSVFILE" ]; then
  echo "Comparison CSV not found: $CSVFILE" >&2
  exit 5
fi

echo "Using comparison file: $CSVFILE"

# Call Python to parse CSV and perform deletions. We pass DRYRUN and CONFIRM as
# arguments (0/1). The Python script will list the files and perform deletion.
python3 - "$CSVFILE" "$DRYRUN" "$CONFIRM" <<'PY'
import csv,sys,os

csvpath = sys.argv[1]
dryrun = sys.argv[2] == '1'
autoconfirm = sys.argv[3] == '1'

def gen_lines(p):
    with open(p, newline='', encoding='utf-8') as fh:
        for line in fh:
            if line.strip().startswith('```'):
                continue
            yield line

def rows_from_csv(p):
    reader = csv.reader(gen_lines(p))
    for row in reader:
        if not row:
            continue
        yield row

# Determine header and column indices
comp_path_idx = 1
comp_fname_idx = 3
rows = list(rows_from_csv(csvpath))
if not rows:
    print('No rows found in', csvpath)
    sys.exit(0)

first = [c.strip().lower() for c in rows[0]]
has_header = any(h in ('master_path','compared_path','master_filename','compared_filename') for h in first)
if has_header:
    hdr = first
    try:
        comp_path_idx = hdr.index('compared_path')
    except ValueError:
        # fallback to second column
        comp_path_idx = 1 if len(hdr) > 1 else 0
    try:
        comp_fname_idx = hdr.index('compared_filename')
    except ValueError:
        # fallback to fourth column if available
        comp_fname_idx = 3 if len(hdr) > 3 else (len(hdr)-1)
    data_rows = rows[1:]
else:
    data_rows = rows

to_delete = []
for row in data_rows:
    # guard against short rows
    if len(row) <= max(comp_path_idx, comp_fname_idx):
        continue
    comp_path = row[comp_path_idx].strip()
    comp_fname = row[comp_fname_idx].strip()
    # If comp_path already looks like a full path to a file (contains filename
    # equal to comp_fname or ends with comp_fname), use it directly. Otherwise
    # join path and filename.
    if os.path.isabs(comp_path) and comp_fname and (comp_path.endswith(comp_fname) or os.path.basename(comp_path) == comp_fname):
        candidate = comp_path
    elif comp_path and os.path.exists(comp_path) and os.path.isfile(comp_path):
        # comp_path is an existing file
        candidate = comp_path
    elif comp_path == '':
        candidate = comp_fname
    else:
        candidate = os.path.join(comp_path, comp_fname)
    # normalize path
    candidate = os.path.normpath(candidate)
    to_delete.append(candidate)

# deduplicate while preserving order
seen = set()
files = []
for p in to_delete:
    if p in seen:
        continue
    seen.add(p)
    files.append(p)

if not files:
    print('No files listed for deletion in', csvpath)
    sys.exit(0)

print(f'Found {len(files)} unique file(s) to delete (first 20 shown):')
for p in files[:20]:
    print('  ', p)
if len(files) > 20:
    print('  ... and', len(files)-20, 'more')

if dryrun:
    print('\nDry-run mode: no files will be removed.')
    sys.exit(0)

if not autoconfirm:
    try:
        resp = input('\nProceed to delete these files? Type YES to confirm: ')
    except EOFError:
        resp = ''
    if resp != 'YES':
        print('Aborted by user. No files removed.')
        sys.exit(0)

deleted = 0
missing = 0
errors = 0
for p in files:
    try:
        if os.path.isabs(p):
            target = p
        else:
            # interpret relative to current working directory
            target = os.path.abspath(p)
        if os.path.exists(target):
            if os.path.isfile(target) or os.path.islink(target):
                os.remove(target)
                deleted += 1
                print('Deleted:', target)
            else:
                print('Skipping non-file:', target)
                missing += 1
        else:
            print('Not found:', target)
            missing += 1
    except Exception as e:
        print('Error removing', target, '-', e)
        errors += 1

print(f'Finished. deleted={deleted} missing_or_skipped={missing} errors={errors}')
PY

echo "Done."
