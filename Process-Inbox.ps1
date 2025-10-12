# <#
# .SYNOPSIS
# Processes files from a central Inbox folder, sorting them into default user folders based on file type.
# Moves unclassified files to a 'Misc_Documents' folder.
# If a file with the same name already exists in the destination, the Inbox original is moved to an 'Inbox\Duplicates' folder for review.
#
# .DESCRIPTION
# This script is designed to be run on a schedule (e.g., via Task Scheduler) to automatically organize files
# that arrive in the Inbox from various devices.
#
# .NOTES
# Author: Your Name/Obsidian Copilot
# Date: 2025-10-12
# Version: 1.2
#
# Ensure all paths are correct and the script has necessary permissions to read/write/move files.
#>

# Acquire global mutex to prevent concurrent runs
$mutexName = 'Global\ProcessInboxMutex'
$mutex = New-Object System.Threading.Mutex($false, $mutexName, [ref]$createdNew)
$haveLock = $false
try {
    # Try to acquire immediately; if another instance holds it, exit
    $haveLock = $mutex.WaitOne(0)
    if (-not $haveLock) {
        Write-Host "Another Process-Inbox instance is already running. Exiting.";
        exit 0
    }

# --- Configuration ---

# Define the root path for your Central Inbox
$InboxPath = "C:\Users\bhupi\Inbox_Folder"

# Define your Default User Folders (adjust paths if necessary)
$PicturesPath = "C:\Users\bhupi\OneDrive - University of the Fraser Valley\Pictures"
$MusicPath = "C:\Users\bhupi\OneDrive - University of the Fraser Valley\Music"
$VideosPath = "C:\Users\bhupi\OneDrive - University of the Fraser Valley\Videos"
$DocumentsPath = "C:\Users\bhupi\OneDrive - University of the Fraser Valley\Documents"

# Define specific subfolders within your default folders
$MiscDocumentsPath = Join-Path $DocumentsPath "Misc_Documents" # For unclassified files
$InboxDuplicatesPath = Join-Path $InboxPath "Duplicates"     # For files moved from Inbox due to destination duplicates

# --- Basic validations ---
if (-not (Test-Path $InboxPath)) {
    Write-Error "Inbox path '$InboxPath' does not exist. Create it or adjust the script configuration."
    exit 1
}

# --- Ensure Destination Folders Exist ---
$FoldersToCreate = @(
    $PicturesPath,
    $MusicPath,
    $VideosPath,
    $DocumentsPath,
    $MiscDocumentsPath,
    $InboxDuplicatesPath
)

foreach ($Folder in $FoldersToCreate) {
    if (-not (Test-Path $Folder)) {
        try {
            New-Item -ItemType Directory -Path $Folder -Force -ErrorAction Stop | Out-Null
            Write-Host "Created directory: $Folder"
        } catch {
            Write-Error "Failed to create directory '$Folder': $($_.Exception.Message)"
            # Exit script if critical folders cannot be created
            exit 1
        }
    }
}

# --- Define File Type Mappings ---
# Maps file extensions (lowercase) to their target destination folders.
$Mappings = @{
    # Photos
    ".jpg" = $PicturesPath; ".jpeg" = $PicturesPath; ".png" = $PicturesPath; ".heic" = $PicturesPath; ".gif" = $PicturesPath;
    # Music
    ".mp3" = $MusicPath; ".m4a" = $MusicPath; ".wav" = $MusicPath; ".aac" = $MusicPath; ".ogg" = $MusicPath;
    # Videos
    ".mp4" = $VideosPath; ".mkv" = $VideosPath; ".avi" = $VideosPath; ".mov" = $VideosPath; ".wmv" = $VideosPath;
    # Documents
    ".pdf" = $DocumentsPath; ".docx" = $DocumentsPath; ".doc" = $DocumentsPath; ".xlsx" = $DocumentsPath; ".xls" = $DocumentsPath;
    ".pptx" = $DocumentsPath; ".ppt" = $DocumentsPath; ".txt" = $DocumentsPath; ".rtf" = $DocumentsPath; ".odt" = $DocumentsPath;
    # Add more mappings as needed
}

# --- Processing Logic ---
Write-Host "Starting Inbox Processing at $(Get-Date)"

# Helper: compute SHA256 hash of a file
function Get-FileHashString {
    param([string]$Path)
    try {
        return (Get-FileHash -Algorithm SHA256 -Path $Path -ErrorAction Stop).Hash
    } catch {
        Write-Error "  Failed to compute hash for '$Path': $($_.Exception.Message)"
        return $null
    }
}

# Helper: preserve timestamps and attributes from source to destination
function Preserve-FileAttributes {
    param(
        [string]$DestPath,
        [datetime]$CreationTime,
        [datetime]$LastWriteTime,
        [datetime]$LastAccessTime,
        [System.IO.FileAttributes]$Attributes
    )
    try {
        $dst = Get-Item -LiteralPath $DestPath -ErrorAction Stop

        # Preserve times
        $dst.CreationTime = $CreationTime
        $dst.LastWriteTime = $LastWriteTime
        $dst.LastAccessTime = $LastAccessTime

        # Preserve attributes (readonly, hidden, archive, system, etc.)
        $dst.Attributes = $Attributes
    } catch {
        Write-Error "  Failed to preserve attributes on '$DestPath': $($_.Exception.Message)"
    }
}

# Helper: generate unique filename with counter if needed
function Get-UniqueFilePath {
    param(
        [string]$TargetFolder,
        [string]$FileName
    )
    $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $ext = [System.IO.Path]::GetExtension($FileName)
    $candidate = Join-Path $TargetFolder $FileName
    $i = 1
    while (Test-Path $candidate -PathType Leaf) {
        $candidateName = "{0} ({1}){2}" -f $base, $i, $ext
        $candidate = Join-Path $TargetFolder $candidateName
        $i++
        if ($i -gt 1000) { throw "Exceeded max rename attempts for file '$FileName' in '$TargetFolder'" }
    }
    return $candidate
}

# Get all files in the Inbox, excluding the Duplicates folder and its subfolders to prevent reprocessing
# Use @() to force an array so .Count is safe even when no files are returned
$FilesToProcess = @(Get-ChildItem -Path $InboxPath -Recurse -File | Where-Object { -not ($_.DirectoryName -like "${InboxDuplicatesPath}*") })

if ($FilesToProcess.Count -eq 0) {
    Write-Host "No new files found in Inbox to process."
} else {
    Write-Host "Found $($FilesToProcess.Count) files to process."

    foreach ($File in $FilesToProcess) {
        $TargetFolder = $null
        $Extension = $File.Extension.ToLower() # Ensure case-insensitive comparison

        # Determine the target folder based on the file extension
        if ($Mappings.ContainsKey($Extension)) {
            $TargetFolder = $Mappings[$Extension]
            Write-Host "Processing '$($File.Name)' (Type: $Extension) -> Target: $TargetFolder"
        } else {
            # If extension is not mapped, assign to Misc Documents
            $TargetFolder = $MiscDocumentsPath
            Write-Host "Unmapped extension '$Extension' for file '$($File.Name)'. Assigning to Misc Documents: $TargetFolder"
        }

        $DestinationFilePath = Join-Path $TargetFolder $File.Name

        # Save original timestamps/attributes so we can preserve them after moving
        $origCreation = $File.CreationTime
        $origLastWrite = $File.LastWriteTime
        $origLastAccess = $File.LastAccessTime
        $origAttributes = $File.Attributes

        if (Test-Path $DestinationFilePath) {
            Write-Host "  Name collision: '$($File.Name)' already exists in '$TargetFolder'. Computing hashes to compare contents..."

            $srcHash = Get-FileHashString -Path $File.FullName
            $dstHash = Get-FileHashString -Path $DestinationFilePath

            if ($null -eq $srcHash -or $null -eq $dstHash) {
                Write-Error "  Skipping file '$($File.Name)' due to hash error. Moving to Duplicates for manual review."
                try {
                    Move-Item -LiteralPath $File.FullName -Destination $InboxDuplicatesPath -Force -ErrorAction Stop
                    $movedDupPath = Join-Path $InboxDuplicatesPath $File.Name
                    Preserve-FileAttributes -DestPath $movedDupPath -CreationTime $origCreation -LastWriteTime $origLastWrite -LastAccessTime $origLastAccess -Attributes $origAttributes
                } catch {
                    Write-Error "  Failed to move '$($File.Name)' to '$InboxDuplicatesPath': $($_.Exception.Message)"
                }
                continue
            }

            if ($srcHash -eq $dstHash) {
                Write-Host "  File contents match (hash equal). Moving incoming file to Duplicates for review."
                try {
                    Move-Item -LiteralPath $File.FullName -Destination $InboxDuplicatesPath -Force -ErrorAction Stop
                    # Preserve attributes on moved file in duplicates folder
                    $movedPath = Join-Path $InboxDuplicatesPath $File.Name
                    Preserve-FileAttributes -DestPath $movedPath -CreationTime $origCreation -LastWriteTime $origLastWrite -LastAccessTime $origLastAccess -Attributes $origAttributes
                    Write-Host "  Successfully moved duplicate to '$InboxDuplicatesPath'."
                } catch {
                    Write-Error "  Failed to move duplicate '$($File.Name)' from Inbox to '$InboxDuplicatesPath': $($_.Exception.Message)"
                }
            } else {
                Write-Host "  Same name but different contents. Renaming incoming file and moving to destination."
                try {
                    $uniqueDest = Get-UniqueFilePath -TargetFolder $TargetFolder -FileName $File.Name
                    Move-Item -LiteralPath $File.FullName -Destination $uniqueDest -Force -ErrorAction Stop
                    # After moving, preserve timestamps/attributes
                    Preserve-FileAttributes -DestPath $uniqueDest -CreationTime $origCreation -LastWriteTime $origLastWrite -LastAccessTime $origLastAccess -Attributes $origAttributes
                    Write-Host "  Successfully moved and renamed to '$(Split-Path -Leaf $uniqueDest)'."
                } catch {
                    Write-Error "  Failed to move and rename '$($File.Name)' to '$TargetFolder': $($_.Exception.Message)"
                    Write-Host "  Moving failed file '$($File.Name)' to '$InboxDuplicatesPath' as a fallback."
                    try {
                        Move-Item -LiteralPath $File.FullName -Destination $InboxDuplicatesPath -Force -ErrorAction Stop
                        $movedFallback = Join-Path $InboxDuplicatesPath $File.Name
                        Preserve-FileAttributes -DestPath $movedFallback -CreationTime $origCreation -LastWriteTime $origLastWrite -LastAccessTime $origLastAccess -Attributes $origAttributes
                    } catch {
                        Write-Error "  CRITICAL: Failed to move '$($File.Name)' to '$InboxDuplicatesPath' after initial move failure. Manual intervention required."
                    }
                }
            }
        } else {
            # No name collision; move file and preserve timestamps/attributes
            try {
                $destPath = Join-Path $TargetFolder $File.Name
                Move-Item -LiteralPath $File.FullName -Destination $destPath -Force -ErrorAction Stop
                Preserve-FileAttributes -DestPath $destPath -CreationTime $origCreation -LastWriteTime $origLastWrite -LastAccessTime $origLastAccess -Attributes $origAttributes
                Write-Host "  Successfully moved '$($File.Name)' to '$TargetFolder'."
            } catch {
                Write-Error "  Failed to move '$($File.Name)' to '$TargetFolder': $($_.Exception.Message)"
                Write-Host "  Moving failed file '$($File.Name)' to '$InboxDuplicatesPath' as a fallback."
                try {
                    Move-Item -LiteralPath $File.FullName -Destination $InboxDuplicatesPath -Force -ErrorAction Stop
                    $movedFallback2 = Join-Path $InboxDuplicatesPath $File.Name
                    Preserve-FileAttributes -DestPath $movedFallback2 -CreationTime $origCreation -LastWriteTime $origLastWrite -LastAccessTime $origLastAccess -Attributes $origAttributes
                } catch {
                    Write-Error "  CRITICAL: Failed to move '$($File.Name)' to '$InboxDuplicatesPath' after initial move failure. Manual intervention required."
                }
            }
        }
    } # End foreach file
} # End if files found

Write-Host "Inbox Processing Complete at $(Get-Date)"

} finally {
    if ($haveLock) {
        try { $mutex.ReleaseMutex() } catch {}
    }
    if ($mutex) { $mutex.Dispose() }
}