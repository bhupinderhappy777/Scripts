import os
import re
from collections import defaultdict
import sys

# --- Configuration ---
# The regular expression pattern to match your old file format.
# Captures: Year(1), Month(2), Day(3), Hour(4), Minute(5), Second(6), and the Extension(7).
# Files like: 2022-01-14-14-33-00_photo_12.683_MB.jpg
PATTERN = re.compile(r'(\d{4})-(\d{2})-(\d{2})-(\d{2})-(\d{2})-(\d{2})_photo_[\d\.]+_MB(\.jpg)$', re.IGNORECASE)

# --- Script Logic ---
def rename_files_with_deduplication(dry_run=True):
    """
    Scans the current directory, generates a rename plan, and executes it.
    """
    
    # 1. Get all files in the current directory
    files = os.listdir('.')
    
    # Filter and store only the files that match our expected pattern
    matching_files = [f for f in files if PATTERN.match(f)]
    
    if not matching_files:
        print("No files found that matched the pattern. Check the directory or the PATTERN variable.")
        return

    print(f"Found {len(matching_files)} files matching the format to process.")

    # 2. Group files by their desired new timestamp (before duplicate numbering)
    # Key: 'YYYYMMDD_HHMMSS_photo'
    timestamp_groups = defaultdict(list)
    
    for original_name in matching_files:
        match = PATTERN.match(original_name)
        if match:
            # Extract captured groups
            year, month, day, hour, minute, second, extension = match.groups()

            # Create the new base name: YYYYMMDD_HHMMSS_photo
            new_base_name = f"{year}{month}{day}_{hour}{minute}{second}_photo"
            
            # Group the original filename under the new base name
            timestamp_groups[new_base_name].append(original_name)
        else:
            # This should ideally not happen if matching_files filtering is correct
            print(f"Warning: Skipping file {original_name} - failed second pattern match.")

    # 3. Process groups to apply the duplicate numbering and build the rename plan
    rename_plan = {}
    for new_base_name, originals in timestamp_groups.items():
        # Sort files to ensure consistent _1, _2, _3 numbering if the script is run repeatedly.
        originals.sort() 
        
        if len(originals) == 1:
            # No duplicates for this timestamp
            original_name = originals[0]
            extension = PATTERN.match(original_name).group(7)
            new_name = f"{new_base_name}{extension}"
            rename_plan[original_name] = new_name
        else:
            # Duplicates found, apply _1, _2, _3, etc.
            for i, original_name in enumerate(originals, 1):
                # We need to re-match here to safely extract the extension
                match = PATTERN.match(original_name)
                if match:
                    extension = match.group(7)
                    # New name is YYYYMMDD_HHMMSS_photo_X.jpg
                    new_name = f"{new_base_name}_{i}{extension}" 
                    rename_plan[original_name] = new_name
                else:
                    print(f"Critical error: Failed to get extension for {original_name}. Skipping.")

    # 4. Execute the renaming
    mode = "DRY RUN" if dry_run else "LIVE RENAME"
    print(f"\n--- Starting {mode} ---")
    
    for original, new in rename_plan.items():
        # Check if the target name already exists (prevents accidental overwrites)
        if original == new:
             print(f"Skipping: {original} -> Filename is already correct.")
             continue

        if os.path.exists(new) and new != original:
            print(f"Conflict: Target file {new} already exists! Cannot rename {original}.")
            continue

        print(f"Renaming: {original} -> {new}")
        if not dry_run:
            try:
                os.rename(original, new)
            except OSError as e:
                print(f"Failed to rename {original} to {new}: {e}")
                
    print(f"\n--- {mode} Completed! {len(rename_plan)} files were processed. ---")


if __name__ == "__main__":
    # The script will run as a DRY RUN by default to show you the changes first.
    # To run the live rename, pass 'execute' as a command line argument:
    # python3 rename.py execute

    is_dry_run = True
    if len(sys.argv) > 1 and sys.argv[1].lower() == 'execute':
        is_dry_run = False
        print("\n*** LIVE RENAME MODE ACTIVATED ***\n")
        
    rename_files_with_deduplication(dry_run=is_dry_run)
