#!/usr/bin/env bash
# flatten.sh - Move all files from subdirectories into the current directory.
# Usage: flatten.sh [-n|--dry-run] [-v|--verbose] [target_dir]
set -o errexit
set -o nounset
set -o pipefail

#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Interactive flatten script
# Prompts for file extension to collect (e.g. .jpg or jpg) and output directory

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [-n|--dry-run] [-v|--verbose]
This script will move files with a given extension from subdirectories into an output directory.
You will be prompted for the extension and the output directory at runtime.
Options:
  -n, --dry-run    Show what would be moved without making changes
  -v, --verbose    Print each move
EOF
}

dry_run=false
verbose=false

while (("$#")); do
  case "$1" in
    -n|--dry-run) dry_run=true; shift ;;
    -v|--verbose) verbose=true; shift ;;
    -h|--help) print_usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; print_usage; exit 2 ;;
    *) break ;;
  esac
done

read -rp "Enter file extension to collect (e.g. .jpg or jpg) : " user_ext
# Normalize extension: allow "jpg" or ".jpg" -> ".jpg"
if [[ -z "$user_ext" ]]; then
  echo "No extension provided, aborting." >&2
  exit 2
fi
if [[ "$user_ext" == .* ]]; then
  ext="$user_ext"
else
  ext=".$user_ext"
fi

read -rp "Enter output directory (absolute or relative). Will be created if missing: " out_dir
if [[ -z "$out_dir" ]]; then
  echo "No output directory provided, aborting." >&2
  exit 2
fi

# Expand to absolute path
out_dir=$(cd "$out_dir" 2>/dev/null && pwd || (mkdir -p "$out_dir" && cd "$out_dir" && pwd))
echo "Collecting files with extension '$ext' into: $out_dir"

# Find files matching extension under current directory (skip files at top-level)
root_dir=$(pwd)

# Use find with -print0 to handle special chars in filenames
find "$root_dir" -mindepth 2 -type f -name "*${ext}" -print0 |
  while IFS= read -r -d '' file; do
    base=$(basename -- "$file")

    # Determine a safe destination path and avoid collisions
    name="${base%.*}"
    # For dotfiles that start with dot and have no other dot, keep the full name
    if [[ "$base" == .* && "$base" != *.* ]]; then
      name="$base"
      file_ext=""
    else
      file_ext=".${base##*.}"
    fi

    dest="$out_dir/${name}${file_ext}"
    count=1
    while [[ -e "$dest" ]]; do
      dest="$out_dir/${name}_$count${file_ext}"
      ((count++))
    done

    if $dry_run; then
      printf "DRY-RUN: %s -> %s\n" "$file" "$dest"
    else
      if $verbose; then
        printf "MOVE: %s -> %s\n" "$file" "$dest"
      fi
      mv -- "$file" "$dest"
    fi
  done

echo "Done."

if [[ ! -d "$target_dir" ]]; then
  echo "Target directory does not exist: $target_dir" >&2
  exit 2
fi

# Use find from target_dir, but skip files already directly under target_dir
# We'll use -mindepth 2 so we don't touch files in the root itself.
# Use -print0 to safely handle all filenames.
find "$target_dir" -mindepth 2 -type f -print0 |
  while IFS= read -r -d '' file; do
    base=$(basename -- "$file")

    # Split name and extension, handling dotfiles correctly:
    # - If name starts with a dot and has no other dots, treat as name with no ext (".bashrc").
    # - Otherwise, the "ext" is the suffix after the last dot (if any).
    if [[ "$base" == .* && "$base" != *.* ]]; then
      name="$base"
      ext=""
    elif [[ "$base" == *.* ]]; then
      name="${base%.*}"
      ext=".${base##*.}"
    else
      name="$base"
      ext=""
    fi

    dest="$target_dir/${name}${ext}"
    count=1
    while [[ -e "$dest" ]]; do
      dest="$target_dir/${name}_$count${ext}"
      ((count++))
    done

    if $dry_run; then
      printf "DRY-RUN: %s -> %s\n" "$file" "$dest"
    else
      if $verbose; then
        printf "MOVE: %s -> %s\n" "$file" "$dest"
      fi
      mv -- "$file" "$dest"
    fi
  done