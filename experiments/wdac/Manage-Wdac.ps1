#requires -Version 5.1
<#
.SYNOPSIS
 Install/remove generated WDAC policies with CiTool (Windows 11 22H2+ / Server 2025+).
.DESCRIPTION
 This is a separate, explicit mutating command. Build-Wdac.ps1 is ALWAYS read-only
 with respect to local App Control state. A reboot may be needed to apply removals
 or changes on older supported Windows versions.
#>
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
 [ValidateSet('Status','Audit','Enforce','Remove','Events')]
 [string]$Action='Status',
 [string]$BuildReport=(Join-Path $PSScriptRoot 'output\build-report.json'),
 [switch]$IUnderstandRisks,
 [switch]$AuditReviewed
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=New-Object Security.Principal.WindowsPrincipal($identity)
$admin=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if($Action -in @('Audit','Enforce','Remove') -and -not $admin){throw 'Abrir PowerShell como administrador'}
if($Action -in @('Audit','Enforce','Remove') -and -not (Get-Command CiTool.exe -ErrorAction SilentlyContinue)){
 throw 'CiTool no esta disponible. Esta herramienta admite despliegue mediante CiTool en Windows 11 22H2+ y Server 2025+.'
}
if($Action -eq 'Events'){
 foreach($log in @('Microsoft-Windows-CodeIntegrity/Operational','Microsoft-Windows-AppLocker/MSI and Script')){
   Write-Host "===== $log ====="
   Get-WinEvent -FilterHashtable @{LogName=$log;Id=@(3076,3077,8028,8029)} -MaxEvents 40 -ErrorAction SilentlyContinue |
     Select-Object TimeCreated,Id,Message | Format-List
 }
 return
}
if($Action -eq 'Status'){
 if(Get-Command CiTool.exe -ErrorAction SilentlyContinue) {
  & CiTool.exe --list-policies -json
 } else {Write-Warning 'CiTool no disponible en este Windows'}
 return
}
if(-not (Test-Path -LiteralPath $BuildReport -PathType Leaf)) {throw "Archivo de compilacion ausente: $BuildReport"}
$report=Get-Content -LiteralPath $BuildReport -Raw | ConvertFrom-Json
$id=[string]$report.PolicyID
if($id -notmatch '^\{[0-9a-fA-F-]{36}\}$') {throw "PolicyID invalido: $id"}
if($Action -eq 'Enforce'){
 if(-not $IUnderstandRisks -or -not $AuditReviewed){
  throw 'Enforce requiere AMBOS -IUnderstandRisks y -AuditReviewed tras pruebas reales en VM con snapshot. Riesgo de bloqueo del sistema.'
 }
}
if($Action -eq 'Audit' -and -not $IUnderstandRisks){
 throw 'Audit requiere -IUnderstandRisks (incluso modo audit puede cambiar comportamiento de hosts de scripts)'
}
$binary=if($Action -eq 'Audit'){$report.AuditBinary}else{$report.EnforceBinary}
if($Action -ne 'Remove'){
 if(-not (Test-Path -LiteralPath $binary -PathType Leaf)){throw "Falta politica CIP: $binary"}
 $baseName=[IO.Path]::GetFileNameWithoutExtension($binary)
 if($baseName -ne $id){throw "El CIP debe llamarse $id.cip. Obtenido: $baseName"}
}
if($PSCmdlet.ShouldProcess("WDAC Policy $id",$Action)) {
 if($Action -eq 'Remove'){
  & CiTool.exe --remove-policy $id
 } else {
  & CiTool.exe --update-policy $binary
 }
 if($LASTEXITCODE -ne 0){throw "CiTool devolvio exit code $LASTEXITCODE"}
 & CiTool.exe --refresh
 if($LASTEXITCODE -ne 0){Write-Warning 'Refresh no completo, puede requerir reinicio'}
 Write-Host "Accion $Action solicitada sobre policy ID $id"
 Write-Host 'IMPORTANTE: verificar CiTool --list-policies, 3076/3077 y ejecucion real. No asumir bloqueo solo por un exit code 0.'
 & CiTool.exe --list-policies -json
}
