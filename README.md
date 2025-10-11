# De-duplication workflow

This folder contains a small set of shell and Python helper scripts to
generate SHA-256 inventories for a master dataset and a compared dataset,
find duplicate files by hash, and safely delete duplicates from the
compared location.

## Quick Start (No Download Required)

You can run the complete deduplication workflow directly from GitHub without downloading any scripts:

```bash
bash <(curl -s https://raw.githubusercontent.com/bhupinderhappy777/Scripts/main/deduplicate.sh)
```

This command will:
- Fetch the main orchestration script from GitHub
- Automatically download and execute all required helper scripts on-the-fly
- Not leave any script files on your system (only data files like CSVs and logs)
- Work exactly the same as if you had cloned the repository locally

**Prerequisites**: You only need `bash`, `curl`, and `python3` installed. The script will prompt you for:
- Master Directory Path (your main file collection)
- Compared Directory Path (folder with files to deduplicate)

## Complete Automated Deduplication Process

The `deduplicate.sh` script provides a **fully automated end-to-end workflow**
that orchestrates all the individual scripts to perform a complete deduplication
process. This is the **recommended way** to use the deduplication system.

### What the Automated Process Does

The automated deduplication workflow performs the following steps:

1. **Generate/Update Master Hashes** - Scans the master folder and creates or
   updates `master_hashes.csv` with SHA-256 hashes of all files. The master
   folder is your "source of truth" containing your primary file collection.

2. **Generate/Update Compared Folder Hashes** - Scans the folder to be compared
   (typically a new folder with files you want to integrate) and creates
   `hash_file.csv` in that folder with SHA-256 hashes of all files.

3. **Compare Hashes** - Compares the hashes from both folders to identify exact
   duplicates (files that already exist in the master folder). Creates a
   `*.comparison.csv` file listing all duplicate matches.

4. **Move Duplicates to Quarantine** - Moves duplicate files from the compared
   folder to a quarantine folder named `<foldername>-quarantined` in the parent
   directory. This ensures duplicates are safely stored (not deleted) for review.

5. **Find Internal Duplicates** - Uses the `fdupes` tool to find duplicates
   within the compared folder itself (files that are duplicates of each other
   within the same folder). Moves these internal duplicates to quarantine,
   keeping one copy.

6. **Move Unique Files to Master** - After removing duplicates, moves all
   remaining unique files from the compared folder to the master folder,
   preserving directory structure. Updates `master_hashes.csv` with the new files.

7. **Generate Summary Report** - Displays a comprehensive summary showing file
   counts, processing time, and locations of all files.

### Usage: Running the Automated Process

You have two options to run the complete automated deduplication:

**Option 1: Direct execution from GitHub (recommended for one-time use)**

No download required - the script fetches everything from GitHub:

```bash
bash <(curl -s https://raw.githubusercontent.com/bhupinderhappy777/Scripts/main/deduplicate.sh)
```

**Option 2: Clone repository and run locally**

If you prefer to have the scripts locally or want to modify them:

```bash
git clone https://github.com/bhupinderhappy777/Scripts.git
cd Scripts
./deduplicate.sh
```

Both methods work identically. The script will interactively prompt you for:
- **Master Directory Path**: Your main/primary file collection
- **Compared Directory Path**: The folder containing files to be deduplicated and integrated

### Example Workflow

```bash
$ ./deduplicate.sh
========================================
Step 1: Input Directories
========================================
Enter Master Directory Path: /home/user/Photos/Master
Enter Path to be Compared: /home/user/Photos/NewPhotos

========================================
Step 2: Generating/Updating Master Hashes
========================================
Scanning directory: /home/user/Photos/Master
HASHING: /home/user/Photos/Master/vacation/img001.jpg
HASHING: /home/user/Photos/Master/vacation/img002.jpg
...
✓ Master hashes updated (45s)

========================================
Step 3: Generating/Updating Compared Folder Hashes
========================================
Scanning directory: /home/user/Photos/NewPhotos
HASHING: /home/user/Photos/NewPhotos/photo1.jpg
...
✓ Compared folder hashes updated (23s)

========================================
Step 4: Comparing Hashes
========================================
Read 1500 unique digests from master
Read 800 unique digests from target
Wrote 150 matching rows to /home/user/Photos/NewPhotos.comparison.csv
✓ Hash comparison completed (2s)

========================================
Step 5: Moving Duplicates to Quarantine
========================================
Found 150 duplicate matches. Moving to quarantine...
Base folder determined: /home/user/Photos/NewPhotos
Quarantine folder: /home/user/Photos/NewPhotos-quarantined
Moved: photo1.jpg -> /home/user/Photos/NewPhotos-quarantined/photo1.jpg
...
✓ Duplicates moved to quarantine (12s)

========================================
Step 6: Finding Internal Duplicates with fdupes
========================================
Found 5 duplicate group(s)
Summary: 5 duplicate file(s) will be moved to quarantine
...
✓ Internal duplicates processed (8s)

========================================
Step 7: Moving Unique Files to Master Folder
========================================
Remaining files in compared directory: 645
Files to move (first 20 of 645 shown):
  [1] unique_photo1.jpg
  [2] unique_photo2.jpg
...
Moved: unique_photo1.jpg -> /home/user/Photos/Master/unique_photo1.jpg
✓ Unique files moved to master (35s)

========================================
Step 8: Summary
========================================

╔════════════════════════════════════════════════════════╗
║           DE-DUPLICATION SUMMARY REPORT                 ║
╟────────────────────────────────────────────────────────╢
║ Master Directory: /home/user/Photos/Master
║ Compared Directory: /home/user/Photos/NewPhotos
║
║ Final File Counts:
║   Files in Master:      2145
║   Files in Compared:    0
║   Files in Quarantine:  155
║
║ Total Processing Time:  125s
║ Log File: deduplication_20251009_152430.log
╚════════════════════════════════════════════════════════╝

✓ De-duplication process completed!
```

### What Happens to Your Files

After the automated process completes:

- **Master Folder**: Contains all original files PLUS all unique files from the
  compared folder. This is your complete, deduplicated collection.
  
- **Compared Folder**: Should be nearly empty (only `hash_file.csv` remains).
  All files have been either moved to master (if unique) or quarantined (if duplicate).
  
- **Quarantine Folder** (`<foldername>-quarantined`): Contains all duplicate files
  that were found. These files are safely stored, not deleted. You can:
  - Review them to ensure they are truly duplicates
  - Permanently delete them if you're confident they're duplicates
  - Restore any files if needed

- **Log File** (`deduplication_YYYYMMDD_HHMMSS.log`): Contains a complete
  timestamped log of the entire process, including which files were hashed,
  which were moved, and any errors encountered.

**Note**: When using the curl method (Quick Start), no script files are downloaded to your
system. All scripts are fetched from GitHub and executed directly, leaving only your
data files (CSVs, logs) and your actual file collections.

### Safety Features

The automated process includes several safety features:

- **No Permanent Deletion**: Files are moved to quarantine, never deleted
- **Hash-Based Comparison**: Uses SHA-256 cryptographic hashes for reliable duplicate detection
- **Automatic Logging**: All operations are logged for audit trail
- **Step-by-Step Progress**: Clear visual feedback at each step
- **Error Handling**: Continues processing even if individual steps encounter non-fatal errors
- **Collision Detection**: Aborts if hash collisions are detected in master updates
- **Duplicate Prevention**: Prevents adding duplicate entries to master_hashes.csv
- **Detailed Diagnostics**: Explains why files remain in compared folder after processing
- **File Conflict Resolution**: If file with same name but different content exists, renames with _1, _2 suffix

### Recent Improvements

**Enhanced Diagnostic Logging and Duplicate Prevention** (Latest Update)

The deduplication scripts have been significantly improved to address common issues and provide better diagnostic information:

1. **Detailed Explanations for Remaining Files**: When files remain in the compared folder after processing, the script now explains exactly why:
   - Files with duplicate hashes (same content as master)
   - Files already at destination with same content
   - Errors during move operation
   - Files already in master location from previous run

2. **Duplicate Prevention**: Added comprehensive checks to prevent duplicate digest entries:
   - Pre-validation before updating master_hashes.csv
   - Clear error messages explaining why duplicates were found
   - Actionable guidance on what to do about duplicates

3. **File Conflict Resolution**: Enhanced handling of file name conflicts:
   - Hash verification when file exists at destination
   - If same content: Skip the move (file already there)
   - If different content: Rename with _1, _2 suffix and log the decision
   - Never overwrites files with different content

4. **Comprehensive Error Messages**: All error messages now include:
   - Explanation of what went wrong
   - What it means in your specific situation
   - Actionable steps to resolve the issue

For detailed information about these improvements, see [IMPROVEMENTS.md](IMPROVEMENTS.md).

### Prerequisites for Automated Process

The automated script requires:
- `bash` shell
- `curl` (for remote execution method)
- `python3` for CSV parsing and file operations
- `sha256sum` or `shasum` for hash generation
- `fdupes` (optional, but recommended for step 6 - internal duplicate detection)

When running locally, all the individual scripts must be in the same directory
(`generate_master_hashes.sh`, `generate_hash_file.sh`, `compare_hashes.sh`,
`deletion.sh`, `fdupes.sh`, `move_to_master.sh`). When using the curl method,
scripts are fetched automatically from GitHub.

If `fdupes` is not installed, step 6 will be skipped with a warning, but the rest
of the process will continue normally.

### When to Use the Automated Process

Use `deduplicate.sh` when you want to:
- Integrate a new batch of files into your master collection
- Remove duplicates from a folder before adding to master
- Consolidate multiple folders into one deduplicated master folder
- Ensure no duplicate files exist between two folder hierarchies

### Manual Process vs Automated Process

You can still use the individual scripts for fine-grained control (see "Typical
safe workflow" section below), but the automated `deduplicate.sh` script is
recommended for most use cases as it:
- Handles all steps automatically in the correct order
- Provides clear progress indication
- Generates comprehensive logs
- Includes error handling and recovery
- Saves time and reduces the chance of mistakes

---

## Individual Scripts

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
- `deletion.sh` — reads the produced `*.comparison.csv` and moves the
  files listed in the `compared_path`/`compared_filename` columns to a
  quarantine folder. The quarantine folder is created in the parent directory
  with the name `<foldername>-quarantined`, similar to how `fdupes.sh` works.
  Supports dry-run and confirmation options.
- `fdupes.sh` — uses the `fdupes` tool to find duplicate files within a
  directory and moves duplicates to a quarantine folder while keeping one
  working copy in the original location. The quarantine folder is created
  in the parent directory with the name `<foldername>-quarantined`.
  Supports dry-run and confirmation options.
- `move_to_master.sh` — moves unique files from a compared folder to the
  master folder after verifying they are not duplicates. Takes two arguments:
  the compared folder and the master folder. Reads `hash_file.csv` from the
  compared folder, checks hashes against `master_hashes.csv`, and only moves
  files that don't already exist in the master collection. Updates
  `master_hashes.csv` with newly moved files.

  ```bash
  ./move_to_master.sh /path/to/compared/folder /path/to/master/folder
  ```
- `deduplicate.sh` — **main orchestration script** that automates the complete
  de-duplication workflow. Runs all the above scripts in the correct order to:
  generate hashes for master and compared folders, compare them, move duplicates
  to quarantine, find internal duplicates with fdupes, move unique files to
  master, and generate a comprehensive summary report. See "Complete Automated
  Deduplication Process" section above for details.

### Additional Utility Scripts

- `encoder.sh` — video encoding script that recursively processes video files
  (MP4, MOV, MPG, MKV, VOB) in the current directory and encodes them to H.264
  format with optimized settings. Outputs to a parallel directory structure
  named `<dirname>_encoded`. Features: parallel processing (4 jobs default),
  automatic scaling for videos >1080p, progress tracking, and comprehensive
  logging. Requires `ffmpeg` and `ffprobe`.

  ```bash
  cd /path/to/video/folder
  ./encoder.sh
  ```

- `audio_encoder.sh` — audio encoding script that recursively processes audio
  files (MP3, FLAC, WAV, AAC, M4A, OGG, WMA) in the current directory and
  encodes them to AAC format. Outputs to a parallel directory structure named
  `<dirname>_audio_encoded`. Features: parallel processing (4 jobs default),
  intelligent bitrate selection (avoids upsampling), progress tracking, and
  comprehensive logging. Requires `ffmpeg` and `ffprobe`.

  ```bash
  cd /path/to/audio/folder
  ./audio_encoder.sh
  ```

- `verify.sh` — verification script for encoded video files. Compares source
  videos with their encoded versions by checking duration differences
  (default tolerance: ±10 seconds). Generates detailed verification logs and
  a list of failed files. Expects encoded files in a parallel directory
  structure named `<dirname>_encoded` with `_encoded.mp4` suffix.

  ```bash
  cd /path/to/source/video/folder
  ./verify.sh
  ```

- `rsync_transfer.sh` — interactive rsync transfer script with progress
  tracking and detailed logging. Prompts for source and destination paths
  and performs rsync with archive, compression, and verbose options.
  Generates timestamped logs with transfer statistics.

  ```bash
  ./rsync_transfer.sh
  # Then follow the prompts to enter source and destination paths
  ```

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

Manual workflow (using individual scripts)

If you prefer fine-grained control over each step, you can run the individual
scripts manually. This is useful for advanced users who want to inspect results
at each stage or integrate the scripts into custom workflows.

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

4. Review the comparison file. Do a dry-run first to see what would be moved:

```bash
./deletion.sh -n
```

5. If the dry-run looks correct, move files to quarantine interactively (you
   must type YES) or use `-y` to skip the prompt:

```bash
./deletion.sh    # interactive confirmation (type YES)
./deletion.sh -y # move without prompt
```

The script will move duplicate files to a quarantine folder (e.g.,
`<foldername>-quarantined`) in the parent directory, preserving the directory
structure.

**Note**: When using the manual workflow, you'll need to manually run the
`fdupes.sh` and `move_to_master.sh` scripts if you want internal duplicate
detection and file consolidation. The automated `deduplicate.sh` handles all
of this for you.

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
  be moved and exits without moving anything.
- The scripts assume SHA-256 digests; if you need a different digest you
  must adapt the hash generation steps accordingly.
- Paths in CSVs are absolute by design — this avoids ambiguity when
  comparing or moving files.

Safety and auditability suggestions
- Keep copies of `master_hashes.csv` and the produced `*.comparison.csv`
  (they are the audit trail of what was matched and moved).
- Files are moved to quarantine folders rather than permanently deleted,
  making it easy to recover if needed. You can review the quarantine folder
  and permanently delete files later if desired.
- Consider adding file size and modification time into the CSV if you
  want an extra check before moving files.

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
