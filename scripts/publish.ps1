param(
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$publishDir = Join-Path $root "artifacts\publish\$Runtime"

& (Join-Path $root ".dotnet\dotnet.exe") publish (Join-Path $root "src\Inspector.App\Inspector.App.csproj") `
    -c $Configuration `
    -r $Runtime `
    --self-contained true `
    -p:PublishSingleFile=false `
    -p:PublishReadyToRun=true `
    -o $publishDir

Write-Host "Published to $publishDir"
