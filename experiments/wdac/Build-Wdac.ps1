#requires -Version 5.1
<#
.SYNOPSIS
  Build a Windows Defender Application Control (App Control for Business)
  audit and enforcement base policy from a reviewed manifest.
.NOTES
  BUILD-ONLY. Does not deploy or activate anything.
  Uses Microsoft's DefaultWindows_Audit.xml baseline for system compatibility.
  Third-party apps are allowed only by explicitly listed content hashes.
  A Windows baseline is NOT a zero-exception exact-file-only allowlist.
#>
[CmdletBinding()]
param(
  [string]$Manifest = (Join-Path $PSScriptRoot 'allowlist.json'),
  [string]$OutputDirectory = (Join-Path $PSScriptRoot 'output'),
  [string]$BaseTemplate,
  [switch]$IncludeSafetyBootOptions
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module ConfigCI -ErrorAction Stop

function Append-CIRules([System.Collections.ArrayList]$target,[object]$value) {
  if($null -eq $value){return}
  if($value -is [System.Collections.IEnumerable] -and $value -isnot [string] -and
      $value.GetType().FullName -notlike 'Microsoft.SecureBoot.UserConfig.Rule*') {
    foreach($entry in $value){Append-CIRules $target $entry}
  } else {
    [void]$target.Add($value)
  }
}
function Assert-Options([string]$xmlPath,[bool]$wantAudit) {
  [xml]$doc=Get-Content -LiteralPath $xmlPath -Raw
  $opts=@($doc.SelectNodes("//*[local-name()='Rule']/*[local-name()='Option']") | ForEach-Object { [string]$_.InnerText })
  foreach($required in @('Enabled:UMCI','Enabled:Unsigned System Integrity Policy')) {
    if($opts -notcontains $required) { throw "Falta regla obligatoria $required" }
  }
  if($opts -contains 'Disabled:Script Enforcement') { throw 'La politica desactiva control de scripts' }
  if($opts -contains 'Enabled:Intelligent Security Graph Authorization') { throw 'Confianza reputacional ISG no permitida' }
  if($opts -contains 'Enabled:Managed Installer') { throw 'Managed Installer permitiria mas archivos' }
  if(($opts -contains 'Enabled:Audit Mode') -ne $wantAudit) { throw "Audit mode incorrecto: $xmlPath" }
  $allowAll=@($doc.SelectNodes("//*[local-name()='FileRules']/*[local-name()='Allow' and (@FileName='*' or @FilePath='*')]"))
  if($allowAll.Count -gt 0) { throw 'La politica tiene regla Allow All, NO es una allowlist' }
  $policyId=([string]$doc.SelectSingleNode("//*[local-name()='PolicyID']").InnerText).Trim()
  $baseId=([string]$doc.SelectSingleNode("//*[local-name()='BasePolicyID']").InnerText).Trim()
  if($policyId -ne $baseId) { throw "No es directiva BASE: $policyId vs $baseId" }
  return $policyId
}
function Has-Option([string]$xml,[string]$name) {
  [xml]$doc=Get-Content -LiteralPath $xml -Raw
  return @($doc.SelectNodes("//*[local-name()='Rule']/*[local-name()='Option']") |
       Where-Object { $_.InnerText -eq $name }).Count -gt 0
}
function Remove-OptionIfPresent([string]$file,[int]$number,[string]$value) {
  if(Has-Option $file $value) { Set-RuleOption -FilePath $file -Option $number -Delete -ErrorAction Stop }
}
if(-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) { throw "Manifiesto ausente: $Manifest" }
$data=Get-Content -LiteralPath $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json
if($null -eq $data.Files -or $null -eq $data.Packages) { throw 'allowlist.json necesita Files y Packages' }
if(-not $BaseTemplate) {
  $BaseTemplate=Join-Path $env:windir 'schemas\CodeIntegrity\ExamplePolicies\DefaultWindows_Audit.xml'
}
if(-not (Test-Path -LiteralPath $BaseTemplate -PathType Leaf)) { throw "Plantilla Microsoft ausente: $BaseTemplate" }
if(-not (Test-Path -LiteralPath $OutputDirectory)) { New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null }
$auditXml=Join-Path $OutputDirectory 'WDAC-Audit.xml'
$enforceXml=Join-Path $OutputDirectory 'WDAC-Enforce.xml'

$rules=New-Object System.Collections.ArrayList
$inventory=New-Object System.Collections.ArrayList
$unique=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach($file in @($data.Files)) {
  if($file -isnot [string] -or [string]::IsNullOrWhiteSpace($file) -or $file.Contains('*') -or $file.Contains('?')) {
    throw 'Files requiere rutas completas sin comodines'
  }
  if(-not [IO.Path]::IsPathRooted($file)) {throw "Ruta no absoluta: $file"}
  if(-not (Test-Path -LiteralPath $file -PathType Leaf)) {throw "Archivo inexistente: $file"}
  $path=(Resolve-Path -LiteralPath $file).ProviderPath
  if(-not $unique.Add($path)) {continue}
  $ext=[IO.Path]::GetExtension($path).ToLowerInvariant()
  if($ext -notin @('.exe','.com','.dll','.sys','.ocx','.msi','.msp','.mst','.ps1','.psm1','.psd1','.bat','.cmd','.vbs','.js')) {
    throw "Extension no reconocida por este laboratorio WDAC: $ext"
  }
  try {
    $generated=@(New-CIPolicyRule -Level Hash -DriverFilePath $path -ErrorAction Stop)
  } catch {
    throw "WDAC no genero reglas para $path ($ext): $($_.Exception.Message)"
  }
  if($generated.Count -lt 1) { throw "No se genero regla WDAC para $path" }
  $before=$rules.Count
  foreach($r in $generated) { Append-CIRules $rules $r }
  if($rules.Count -le $before){throw "ConfigCI devolvio cero reglas nativas para $path"}
  [void]$inventory.Add([pscustomobject]@{Path=$path;SHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;RuleCount=($rules.Count-$before)})
}
$installed=@(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
foreach($name in @($data.Packages)) {
  if($name -isnot [string] -or [string]::IsNullOrWhiteSpace($name) -or $name.Contains('*')) {
    throw 'Packages requiere nombres exactos instalados'
  }
  $pkg=$installed | Where-Object {$_.Name -eq $name} | Select-Object -First 1
  if(-not $pkg){throw "Paquete no instalado: $name"}
  foreach($r in @(New-CIPolicyRule -Package $pkg -ErrorAction Stop)) {Append-CIRules $rules $r}
}
Copy-Item -LiteralPath $BaseTemplate -Destination $auditXml -Force
if($rules.Count -gt 0) {
  Merge-CIPolicy -PolicyPaths @($auditXml) -OutputFilePath $auditXml -Rules @($rules.ToArray()) -ErrorAction Stop | Out-Null
}
# The imported Microsoft template retains Windows OS signers. NEVER AllowAll.xml.
# Reset Policy ID ONCE, then copy XML so Audit and Enforce use the SAME ID.
Set-CIPolicyIdInfo -FilePath $auditXml -PolicyName 'WDAC Reviewed Allowlist Lab' -ResetPolicyID -ErrorAction Stop | Out-Null
Set-RuleOption -FilePath $auditXml -Option 0 -ErrorAction Stop  # UMCI
Set-RuleOption -FilePath $auditXml -Option 6 -ErrorAction Stop  # unsigned in LAB
Set-RuleOption -FilePath $auditXml -Option 16 -ErrorAction Stop # update no reboot
Set-RuleOption -FilePath $auditXml -Option 3 -ErrorAction Stop  # audit
Remove-OptionIfPresent $auditXml 11 'Disabled:Script Enforcement'
Remove-OptionIfPresent $auditXml 13 'Enabled:Managed Installer'
Remove-OptionIfPresent $auditXml 14 'Enabled:Intelligent Security Graph Authorization'
if($IncludeSafetyBootOptions) {
  Set-RuleOption -FilePath $auditXml -Option 9 -ErrorAction Stop
  Set-RuleOption -FilePath $auditXml -Option 10 -ErrorAction Stop
}
# For packaged apps: don't use a blanket exemption for Store packages.
Set-RuleOption -FilePath $auditXml -Option 12 -ErrorAction Stop

Copy-Item -LiteralPath $auditXml -Destination $enforceXml -Force
Set-RuleOption -FilePath $enforceXml -Option 3 -Delete -ErrorAction Stop
$auditId=Assert-Options $auditXml $true
$enforceId=Assert-Options $enforceXml $false
if($auditId -ne $enforceId) { throw 'PolicyIDs cambiaron entre Audit y Enforce' }
# .CIP name is the full PolicyID GUID in multiple-policy format.
$auditDir=Join-Path $OutputDirectory 'audit'
$enforceDir=Join-Path $OutputDirectory 'enforce'
New-Item -ItemType Directory -Force -Path $auditDir,$enforceDir | Out-Null
$binAudit=Join-Path $auditDir ($auditId+'.cip')
$binEnforce=Join-Path $enforceDir ($enforceId+'.cip')
ConvertFrom-CIPolicy -XmlFilePath $auditXml -BinaryFilePath $binAudit -ErrorAction Stop | Out-Null
ConvertFrom-CIPolicy -XmlFilePath $enforceXml -BinaryFilePath $binEnforce -ErrorAction Stop | Out-Null
if((Get-Item $binAudit).Length -lt 100 -or (Get-Item $binEnforce).Length -lt 100) {throw 'CIP vacio'}
$info=[pscustomobject]@{
  PolicyID=$auditId
  BaseTemplate=$BaseTemplate
  SourceFiles=@($inventory.ToArray())
  Packages=@($data.Packages)
  AuditXml=$auditXml
  EnforceXml=$enforceXml
  AuditBinary=$binAudit
  EnforceBinary=$binEnforce
  Baseline='DefaultWindows: Microsoft OS and essential drivers allowed outside this custom file list'
  Deployment='NOT DEPLOYED: compile only'
}
$info | ConvertTo-Json -Depth 7 | Set-Content (Join-Path $OutputDirectory 'build-report.json') -Encoding UTF8
Write-Host "WDAC compilado; PolicyID=$auditId; archivos autorizados=$($inventory.Count); paquetes=$(@($data.Packages).Count)"
Write-Host 'IMPORTANTE: este proceso NO activo ninguna politica.'
$info
