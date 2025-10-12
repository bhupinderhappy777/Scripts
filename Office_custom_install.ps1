<#
.SYNOPSIS
Installs Microsoft 365 (64-bit) including Word, Excel, PowerPoint, and OneDrive only.
This version uses robust error handling and the correct Product ID for University licenses.

.NOTES
*** CRITICAL CHANGE ***: Set to use 'O365ProPlusRetail' which is correct for most university licenses.
If this fails, change the Product ID to 'O365ClientRetail' in the XMLContent block and try again.
#>

# --- Configuration Variables ---
$InstallDir           = "$env:ProgramData\Office-WXP-OneDrive-Install"
$ODT_DownloadURL      = "https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_19231-20072.exe"
$ODT_FileName         = "officedeploymenttool.exe" 
$ODT_FilePath         = "$InstallDir\$ODT_FileName"
$SetupExePath         = "$InstallDir\setup.exe"
$XML_FileName         = "configuration-custom.xml"
$XML_FilePath         = "$InstallDir\$XML_FileName"

# The XML configuration excludes all unnecessary apps but keeps Word, Excel, PowerPoint, and OneDrive.
$XMLContent = @"
<Configuration>
    <Add OfficeClientEdition="64" Channel="Current">
        <Product ID="O365ProPlusRetail">  <Language ID="en-us" />
            
            <ExcludeApp ID="Access" />
            <ExcludeApp ID="Groove" />      
            <ExcludeApp ID="Lync" />        
            <ExcludeApp ID="OneNote" />
            <ExcludeApp ID="Outlook" />
            <ExcludeApp ID="Publisher" />
            <ExcludeApp ID="Teams" />       
        </Product>
    </Add>
    
    <Property Name="AUTOACTIVATE" Value="1" />
    <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
    <Display Level="None" AcceptEULA="TRUE" /> </Configuration>
"@

# --- Script Logic ---
function Write-Log {
    param([string]$Message)
    Write-Host "$(Get-Date -Format 'HH:mm:ss') :: $Message" -ForegroundColor Cyan
}

# 1. Check for Admin Rights
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "`nERROR: This script must be run with Administrator privileges." -ForegroundColor Red
    exit 1
}

# 2. Setup Directory
Write-Log "Creating installation directory: $InstallDir"
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

# 4. Extract ODT Files (Setup.exe) - Robust Check
Write-Log "Extracting ODT files (Setup.exe)..."
try {
    $ExtractProcess = Start-Process -FilePath $ODT_FilePath -ArgumentList "/extract:$InstallDir /quiet" -Wait -PassThru
    
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

# 5. Create Custom Configuration XML File
Write-Log "Creating custom XML configuration file: $XML_FileName"
$XMLContent | Out-File $XML_FilePath -Encoding UTF8

if (-not (Test-Path $XML_FilePath)) {
    Write-Host "`nERROR: The custom XML configuration file could not be created." -ForegroundColor Red
    exit 1
}

# 6. Start the Silent Installation
Write-Log "Starting Microsoft 365 custom installation (Word, Excel, PowerPoint, OneDrive only)."
Write-Log "Installation is silent. Please wait 10-30 minutes."

try {
    # Execute setup.exe with the full, explicit path
    Start-Process -FilePath $SetupExePath -ArgumentList "/configure ""$XML_FilePath""" -Wait -NoNewWindow 
    Write-Log "Installation command executed successfully."

}
catch {
    Write-Host "`nFATAL ERROR: Installation process failed to execute setup.exe." -ForegroundColor Red
    exit 1
}

# 7. Cleanup and Final Message
Write-Log "Cleaning up temporary files..."
Remove-Item -Path $InstallDir -Recurse -Force 

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host "CUSTOM INSTALLATION COMPLETE (or running in background)." -ForegroundColor Green
Write-Host "Please check your Start Menu for Word, Excel, PowerPoint, and OneDrive." -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Green