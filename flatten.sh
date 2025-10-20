#!/usr/bin/env bash
# flatten.sh - Move all files from subdirectories into the current directory.
# Usage: flatten.sh [-n|--dry-run] [-v|--verbose] [target_dir]
set -o errexit
set -o nounset
set -o pipefail

dry_run=false
verbose=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [-n|--dry-run] [-v|--verbose] [target_dir]
  -n, --dry-run    Show what would be moved (no changes)
  -v, --verbose    Print each move
If target_dir is omitted, uses current directory.
EOF
}

# parse args
while (( "$#" )); do
  case "$1" in
    -n|--dry-run) dry_run=true; shift ;;
    -v|--verbose) verbose=true; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      target_dir="$1"
      shift
      ;;
  esac
done

target_dir="${target_dir:-$(pwd)}"

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