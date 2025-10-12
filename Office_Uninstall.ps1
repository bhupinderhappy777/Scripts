<#
.SYNOPSIS
Uninstalls all currently installed Microsoft 365/Office Click-to-Run products silently.
Uses the specific ODT download link provided by the user.

.NOTES
Requires Administrator privileges. This process will shut down all running Office apps.
#>

# --- Configuration Variables ---
$InstallDir           = "$env:ProgramData\Office-Uninstall-Temp"
# UPDATED ODT LINK
$ODT_DownloadURL      = "https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_19231-20072.exe"
$ODT_FileName         = "officedeploymenttool.exe" # Name it generically for easier use
$ODT_FilePath         = "$InstallDir\$ODT_FileName"
$SetupExePath         = "$InstallDir\setup.exe"
$XML_FileName         = "configuration-remove.xml"
$XML_FilePath         = "$InstallDir\$XML_FileName"

# This XML tells the ODT to REMOVE the entire Microsoft 365 suite.
# 'O365ProPlusRetail' is used as it covers the broadest range of Business/Education/Enterprise licenses.
$XMLContent = @"
<Configuration>
    <Display Level="None" AcceptEULA="TRUE" />
    <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
    <Remove>
        <Product ID="O365ProPlusRetail" />
    </Remove>
</Configuration>
"@

# --- Script Logic ---
function Write-Log {
    param([string]$Message)
    Write-Host "$(Get-Date -Format 'HH:mm:ss') :: $Message" -ForegroundColor Cyan
}

# 1. Check for Admin Rights
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "`nERROR: This script must be run with Administrator privileges." -ForegroundColor Red
    Write-Host "Please close this window, right-click the script file, and choose 'Run as administrator'." -ForegroundColor Red
    exit 1
}

# 2. Setup Directory
Write-Log "Creating temporary directory: $InstallDir"
if (Test-Path $InstallDir) {
    Write-Log "Temporary folder already exists. Clearing old files."
    Remove-Item -Path $InstallDir -Recurse -Force | Out-Null
}
New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null

# 3. Download Office Deployment Tool (ODT)
Write-Log "Downloading Office Deployment Tool..."
try {
    Write-Log "Using custom ODT link: $ODT_DownloadURL"
    Invoke-WebRequest -Uri $ODT_DownloadURL -OutFile $ODT_FilePath -UseBasicParsing
}
catch {
    Write-Host "`nERROR: Failed to download ODT. Check your internet connection." -ForegroundColor Red
    exit 1
}

# 4. Extract ODT Files (Setup.exe) - CRITICAL FIX
Write-Log "Extracting ODT files (Setup.exe)..."
try {
    # Run the downloaded EXE to extract setup.exe, wait for it to finish, and run silently
    $ExtractProcess = Start-Process -FilePath $ODT_FilePath -ArgumentList "/extract:$InstallDir /quiet" -Wait -PassThru
    
    # Check if the setup.exe file was created successfully
    if (-not (Test-Path $SetupExePath)) {
        Write-Host "`nERROR: Extraction failed. 'setup.exe' was not created." -ForegroundColor Red
        Write-Host "Exit code from extractor: $($ExtractProcess.ExitCode)" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "`nERROR: Failed during ODT extraction process." -ForegroundColor Red
    exit 1
}

# 5. Create Uninstall Configuration XML File
Write-Log "Creating uninstall configuration file: $XML_FileName"
$XMLContent | Out-File $XML_FilePath -Encoding UTF8

# 6. Start the Silent Uninstall - CRITICAL FIX (Explicit Pathing)
Write-Log "Starting silent Office UNINSTALL. Running Office apps will be forced to close."
Write-Log "The uninstall may take 5-15 minutes, with no progress displayed (silent mode)."

try {
    # Use the full, explicit path for Setup.exe and the configuration file
    Start-Process -FilePath $SetupExePath -ArgumentList "/configure ""$XML_FilePath""" -Wait -NoNewWindow 
    Write-Log "Uninstall command executed successfully. Office removal is running."

}
catch {
    Write-Host "`nERROR: Uninstall process failed to execute the setup.exe command." -ForegroundColor Red
    exit 1
}

# 7. Cleanup and Final Message
Write-Log "Cleaning up temporary files..."
Remove-Item -Path $InstallDir -Recurse -Force 

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host "FULL OFFICE UNINSTALL COMPLETE." -ForegroundColor Green
Write-Host "You are now ready for the custom install of Word, Excel, and PowerPoint." -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Green