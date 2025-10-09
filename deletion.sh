#!/usr/bin/env bash
set -euo pipefail

# deletion.sh
# Moves files listed in the "compared_path" (and compared_filename) column
# of a comparison CSV produced by compare_hashes.sh to a quarantine folder.
# By default it looks for a single "*.comparison.csv" file in the current
# directory. The quarantine folder is created in the parent directory with
# the name "<foldername>-quarantined". Usage:
#
#   ./deletion.sh [-n] [-y] [-f comparison.csv]
#
# Options:
#   -n    dry-run: show what would be moved but don't move files
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

# Call Python to parse CSV and move files to quarantine. We pass DRYRUN and CONFIRM as
# arguments (0/1). The Python script will list the files and move them to quarantine.
python3 - "$CSVFILE" "$DRYRUN" "$CONFIRM" <<'PY'
import csv,sys,os,shutil

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

print(f'Read {len(rows)} CSV rows (including header if present) from {csvpath}', file=sys.stderr)

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
    print('No files listed for moving to quarantine in', csvpath)
    sys.exit(0)

# Determine the quarantine folder
# Extract the base folder from the first compared_path
base_folder = None
for row in data_rows:
    if len(row) <= comp_path_idx:
        continue
    comp_path = row[comp_path_idx].strip()
    if comp_path and os.path.isabs(comp_path):
        # Get the directory containing the file
        if os.path.isfile(comp_path):
            base_folder = os.path.dirname(comp_path)
        else:
            base_folder = comp_path
        break

# If we couldn't find an absolute path, try to determine from the CSV filename
if not base_folder:
    # Try to extract from CSV filename (e.g., "_path_to_folder.comparison.csv")
    csv_basename = os.path.basename(csvpath)
    if csv_basename.endswith('.comparison.csv'):
        # This is a heuristic, may not always work
        print('Warning: Could not determine base folder from CSV content.', file=sys.stderr)
        print('Using current directory as base.', file=sys.stderr)
        base_folder = os.getcwd()
    else:
        base_folder = os.getcwd()

# Find the topmost common directory for all files
all_dirs = set()
for p in files:
    if os.path.isabs(p):
        all_dirs.add(os.path.dirname(p))
    else:
        all_dirs.add(os.path.dirname(os.path.abspath(p)))

if all_dirs:
    # Find common prefix
    common_parts = None
    for d in all_dirs:
        parts = d.split(os.sep)
        if common_parts is None:
            common_parts = parts
        else:
            # Find common prefix
            new_common = []
            for i, part in enumerate(parts):
                if i < len(common_parts) and common_parts[i] == part:
                    new_common.append(part)
                else:
                    break
            common_parts = new_common
    
    if common_parts:
        base_folder = os.sep.join(common_parts)
        if not base_folder:
            base_folder = os.sep  # root

# Create quarantine folder name
dirname = os.path.basename(base_folder.rstrip(os.sep))
if not dirname:
    dirname = 'files'
parent_dir = os.path.dirname(base_folder.rstrip(os.sep))
if not parent_dir:
    parent_dir = base_folder
quarantine_dir = os.path.join(parent_dir, f"{dirname}-quarantined")

print(f'Base folder determined: {base_folder}')
print(f'Quarantine folder: {quarantine_dir}')
print()
print(f'Found {len(files)} unique file(s) to move to quarantine (first 20 shown):')
for p in files[:20]:
    print('  ', p)
if len(files) > 20:
    print('  ... and', len(files)-20, 'more')

if dryrun:
    print('\nDry-run mode: no files will be moved.')
    sys.exit(0)

print('Proceeding to move phase...', file=sys.stderr)

if not autoconfirm:
    try:
        resp = input('\nProceed to move these files to quarantine? Type YES to confirm: ')
    except EOFError:
        resp = ''
    if resp != 'YES':
        print('Aborted by user. No files moved.')
        sys.exit(0)

# Create quarantine directory if needed
if not os.path.exists(quarantine_dir):
    os.makedirs(quarantine_dir)
    print(f'Created quarantine directory: {quarantine_dir}')

moved = 0
missing = 0
errors = 0
for p in files:
    try:
        if os.path.isabs(p):
            target = p
        else:
            # interpret relative to current working directory
            target = os.path.abspath(p)
        
        if not os.path.exists(target):
            print('Not found:', target)
            missing += 1
            continue
            
        if not (os.path.isfile(target) or os.path.islink(target)):
            print('Skipping non-file:', target)
            missing += 1
            continue
        
        # Calculate relative path from base folder
        if target.startswith(base_folder + os.sep):
            rel_path = os.path.relpath(target, base_folder)
        else:
            # File might be directly in base_folder or use different path
            rel_path = os.path.basename(target)
        
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
        shutil.move(target, dest_path)
        moved += 1
        print(f'Moved: {target} -> {dest_path}')
        
    except Exception as e:
        print(f'Error moving {target}: {e}', file=sys.stderr)
        errors += 1

print()
print(f'Finished. moved={moved} missing_or_skipped={missing} errors={errors}')
if moved > 0:
    print(f'Files moved to quarantine: {quarantine_dir}')
PY

echo "Done."
