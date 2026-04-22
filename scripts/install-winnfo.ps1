param(
    [string]$SourceDir = "$PSScriptRoot\..\artifacts\publish\win-x64",
    [string]$InstallDir = "$env:ProgramFiles\Windows Hardware Usage Inspector",
    [switch]$SkipSmartctl
)

$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")

if (-not (Test-Path $SourceDir))
{
    Write-Host "Published output not found. Publishing first..."
    & (Join-Path $root ".dotnet\dotnet.exe") publish (Join-Path $root "src\Inspector.App\Inspector.App.csproj") `
        -c Release `
        -r win-x64 `
        --self-contained true `
        -p:PublishSingleFile=false `
        -p:PublishReadyToRun=true `
        -o $SourceDir
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Copy-Item -Path (Join-Path $SourceDir "*") -Destination $InstallDir -Recurse -Force

$shortcutPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "Windows Hardware Usage Inspector.lnk"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $InstallDir "Inspector.App.exe"
$shortcut.WorkingDirectory = $InstallDir
$shortcut.IconLocation = Join-Path $InstallDir "Inspector.App.exe"
$shortcut.Save()

if (-not $SkipSmartctl)
{
    $smartctl = Join-Path "$env:ProgramFiles\smartmontools\bin" "smartctl.exe"
    if (-not (Test-Path $smartctl))
    {
        Write-Host "smartctl not found. Installing smartmontools..."
        & (Join-Path $root "scripts\install-smartctl.ps1")
    }
    else
    {
        Write-Host "smartctl already installed: $smartctl"
    }
}

Write-Host "Installed Windows Hardware Usage Inspector to $InstallDir"
