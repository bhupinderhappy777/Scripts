# De-duplication workflow

This folder contains a small set of shell and Python helper scripts to
generate SHA-256 inventories for a master dataset and a compared dataset,
find duplicate files by hash, and safely delete duplicates from the
compared location.

- Files
- `generate_master_hashes.sh` — recursively walks a directory and writes
  `master_hashes.csv` containing the absolute path, filename, and SHA-256
  digest for every regular file. The script is append-aware: if
  `master_hashes.csv` does not exist it will be created with the proper
  header; if it exists the script will stage newly-computed rows in a
  temporary file, verify there are no digest collisions (neither within
  the new batch nor against digests already present in the master CSV),
  and only append the new rows when checks pass. On collision the script
  aborts without modifying the master CSV so you can inspect the conflict
  and decide how to proceed. Concurrency for hash workers is controlled
  by the `CONCURRENCY` environment variable (default: 32).
- `generate_hash_file.sh` — same as the master generator but writes
  `hash_file.csv` inside a compared folder (used by `compare_hashes.sh`).
- `compare_hashes.sh` — compares `hash_file.csv` from a target folder
  against the `master_hasher.csv` (preferred) or `master_hashes.csv` in
  the current working directory and produces a `*.comparison.csv` listing
  matching files.
- `deletion.sh` — reads the produced `*.comparison.csv` and deletes the
  files listed in the `compared_path`/`compared_filename` columns. Supports
  dry-run and confirmation options.
- `fdupes.sh` — uses the `fdupes` tool to find duplicate files within a
  directory and moves duplicates to a quarantine folder while keeping one
  working copy in the original location. The quarantine folder is created
  in the parent directory with the name `<foldername>-quarantined`.
  Supports dry-run and confirmation options.

Prerequisites
- A POSIX-like shell (Bash). On Windows use WSL, Git Bash, or similar.
- `find`, `xargs` (GNU xargs recommended), and one of: `sha256sum`,
  `shasum` (with -a 256), or `openssl`.
- `realpath` or `readlink -f` is preferred for canonical absolute paths;
  the scripts fall back to `python3` to compute absolute paths if needed.
- `python3` (used by `compare_hashes.sh`, `deletion.sh`, and `fdupes.sh`
  for robust CSV parsing and file operations).
- `fdupes` (required only for `fdupes.sh`; install with `apt-get install
  fdupes` on Debian/Ubuntu, `yum install fdupes` on RedHat/CentOS, or
  `brew install fdupes` on macOS).

CSV formats
- Master and hash files (`master_hashes.csv`, `hash_file.csv`) use this
  header and columns:

  fullpath,filename,sha256

  - `fullpath` is the absolute path to the file (script computes this).
  - `filename` is the basename of the file.
  - `sha256` is the SHA-256 digest (hex lower-case).

- Comparison CSV produced by `compare_hashes.sh` has the header:

  master_path,compared_path,master_filename,compared_filename

  Each row represents one matching digest; if multiple files share the
  same digest on either side the script writes all cross-product matches.

Typical safe workflow
1. Generate the master inventory from the master folder (run in the
   directory where you want `master_hashes.csv`):

```bash
./generate_master_hashes.sh /path/to/master/folder
```

2. Generate the hash file for a compared folder:

```bash
./generate_hash_file.sh /path/to/compared/folder
```

3. Compare and produce a comparison CSV:

```bash
./compare_hashes.sh /path/to/compared/folder
# -> creates: <path>.comparison.csv in the current directory
```

4. Review the comparison file. Do a dry-run deletion first:

```bash
./deletion.sh -n
```

5. If the dry-run looks correct, delete interactively (you must type YES)
   or use `-y` to skip the prompt:

```bash
./deletion.sh    # interactive confirmation (type YES)
./deletion.sh -y # delete without prompt
```

Alternative workflow with fdupes
If you prefer a simpler single-folder duplicate removal approach using the
`fdupes` tool, you can use the `fdupes.sh` script:

1. Scan a folder for duplicates and move them to quarantine (dry-run first):

```bash
./fdupes.sh -n /path/to/folder
# or for current directory:
./fdupes.sh -n
```

2. If the dry-run looks correct, move duplicates to quarantine:

```bash
./fdupes.sh /path/to/folder       # interactive confirmation (type YES)
./fdupes.sh -y /path/to/folder    # move without prompt
```

The script will:
- Keep one copy of each duplicate in the original folder
- Move all other duplicates to a `<foldername>-quarantined` folder in the
  parent directory
- Preserve directory structure in the quarantine folder

Options and special cases
- If multiple `*.comparison.csv` files exist in the working directory
  `deletion.sh` will refuse to choose — use `-f <file>` to specify the file.
- `deletion.sh -n` is a recommended safety step; it lists files that would
  be deleted and exits without removing anything.
- The scripts assume SHA-256 digests; if you need a different digest you
  must adapt the hash generation steps accordingly.
- Paths in CSVs are absolute by design — this avoids ambiguity when
  comparing or deleting files.

Safety and auditability suggestions
- Keep copies of `master_hashes.csv` and the produced `*.comparison.csv`
  (they are the audit trail of what was matched and removed).
- Instead of permanent deletion, you can modify `deletion.sh` to move
  files to a quarantine directory or to the OS trash (platform-specific).
- Consider adding file size and modification time into the CSV if you
  want an extra check before deletion.

Troubleshooting
- If `python3` is not found: install it (your distro package manager or
  `pyenv` are good options). See the scripts' top-line comments for more
  hints about dependencies.
- If `realpath`/`readlink -f` aren't available the scripts will call
  `python3` to get absolute paths. Ensure `python3` is available.
- If `sha256sum` isn't available, ensure `shasum` or `openssl` is on PATH.
- If `fdupes` is not found (needed for `fdupes.sh`): install it with
  `apt-get install fdupes` (Debian/Ubuntu), `yum install fdupes`
  (RedHat/CentOS), or `brew install fdupes` (macOS).

Possible improvements
- Add file size and mtime to CSVs for stronger duplicate detection.
- Make `compare_hashes.sh` and `deletion.sh` accept explicit headers or
  configurable column names for more flexibility.
- Add logging (timestamped deletion log) and dry-run logging to keep a
  permanent audit trail of deletions.

License
This README and the scripts in this directory are provided as-is.
