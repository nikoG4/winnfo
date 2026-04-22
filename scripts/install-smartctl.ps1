param(
    [string]$Version = "7.5",
    [string]$InstallDir = "$env:ProgramFiles\smartmontools"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$downloadDir = Join-Path $root "tools\downloads"
New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null

$fileName = "smartmontools-$Version.win32-setup.exe"
$downloadPage = "https://sourceforge.net/projects/smartmontools/files/smartmontools/$Version/$fileName/download"
$installer = Join-Path $downloadDir $fileName

Write-Host "Downloading $fileName..."
Invoke-WebRequest -Uri $downloadPage -OutFile $installer -Headers @{ "User-Agent" = "Mozilla/5.0" } -MaximumRedirection 10

$bytes = [System.IO.File]::ReadAllBytes($installer)
if ($bytes.Length -gt 2 -and [char]$bytes[0] -eq '<')
{
    $html = [System.IO.File]::ReadAllText($installer)
    $match = [regex]::Match($html, 'url=(https://downloads\.sourceforge\.net/project/[^"'']+)')
    if (-not $match.Success) { throw "SourceForge mirror URL was not found." }
    $mirrorUrl = [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value)
    Invoke-WebRequest -Uri $mirrorUrl -OutFile $installer -Headers @{ "User-Agent" = "Mozilla/5.0" } -MaximumRedirection 10
    $bytes = [System.IO.File]::ReadAllBytes($installer)
}

if ($bytes.Length -lt 1024 -or [char]$bytes[0] -ne 'M' -or [char]$bytes[1] -ne 'Z')
{
    throw "Downloaded file does not look like a valid Windows installer."
}

Write-Host "Installing to $InstallDir..."
$process = Start-Process -FilePath $installer -ArgumentList @(
    "/VERYSILENT",
    "/SUPPRESSMSGBOXES",
    "/NORESTART",
    "/DIR=$InstallDir"
) -Wait -PassThru

if ($process.ExitCode -ne 0)
{
    throw "smartmontools installer failed with exit code $($process.ExitCode)."
}

$smartctl = Join-Path $InstallDir "bin\smartctl.exe"
if (-not (Test-Path $smartctl))
{
    $smartctl = Join-Path "$env:ProgramFiles\smartmontools\bin" "smartctl.exe"
}

if (-not (Test-Path $smartctl))
{
    throw "smartctl.exe was not found after installation."
}

Write-Host "Installed smartctl:"
& $smartctl --version
