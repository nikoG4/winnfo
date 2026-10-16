#requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('Build','Audit','Enforce')][string]$Phase='Build')
$ErrorActionPreference='Stop'
$workspace=Join-Path $(if($env:RUNNER_TEMP){$env:RUNNER_TEMP}else{$env:TEMP}) 'WDAC-CI'
$reportDir=Join-Path $PSScriptRoot 'reports'
New-Item -ItemType Directory -Force -Path $workspace,$reportDir | Out-Null
$results=New-Object 'System.Collections.Generic.List[object]'
$deployedId=$null
function Result([string]$name,[bool]$ok,[string]$detail) {
 $status=if($ok){'PASS'}else{'FAIL'}
 $script:results.Add([pscustomobject]@{Name=$name;Status=$status;Detail=$detail})
 Write-Host "[$status] $name : $detail"
}
function LaunchProbe([string]$file,[bool]$shouldWork,[string]$label) {
 $ran=$false;$msg=''
 try {
  $p=Start-Process -FilePath $file -Wait -PassThru -NoNewWindow -ErrorAction Stop
  $ran=($p.ExitCode -eq 0);$msg="exit=$($p.ExitCode)"
 }catch{$msg=$_.Exception.Message}
 Result $label ($ran -eq $shouldWork) "started=$ran expected=$shouldWork $msg"
}
try {
 Import-Module ConfigCI -ErrorAction Stop
 $allowed=Join-Path $workspace 'approved.exe'
 $denied=Join-Path $workspace 'winrar-setup-unapproved.exe'
 $csAllow=@'
using System;
public static class WdacApprovedProbe {
 public static int Main(){Console.WriteLine("APPROVED_WDAC");return 0;}
}
'@
 $csDeny=@'
using System;
public static class WdacDeniedProbe {
 public static int Main(){Console.WriteLine("DENIED_WDAC");return 0;}
}
'@
 Add-Type -TypeDefinition $csAllow -OutputAssembly $allowed -OutputType ConsoleApplication
 Add-Type -TypeDefinition $csDeny -OutputAssembly $denied -OutputType ConsoleApplication
 $approvedScript=Join-Path $workspace 'approved.ps1'
 Set-Content $approvedScript -Value 'Write-Host "APPROVED SCRIPT"' -Encoding ASCII
 $allowedMsi=Join-Path $workspace 'approved-installer.msi'
 try {
   $com=New-Object -ComObject WindowsInstaller.Installer
   $db=$com.OpenDatabase($allowedMsi,3)
   $db.Commit()
   foreach($obj in @($db,$com)) {[void][Runtime.InteropServices.Marshal]::ReleaseComObject($obj)}
   Result 'Crear MSI de laboratorio' (Test-Path $allowedMsi) 'MSI sin payload, no se instala'
 }catch{Result 'Crear MSI de laboratorio' $false $_.Exception.Message}
 $manifest=Join-Path $workspace 'allowlist.json'
 @{PolicyId='{D53A11E4-5FF4-4B69-AFAA-2B0C133AD415}';Files=@($allowed,$approvedScript,$allowedMsi);Packages=@()} | ConvertTo-Json | Set-Content $manifest -Encoding UTF8
 $output=Join-Path $workspace 'output'
 & (Join-Path $PSScriptRoot 'Build-Wdac.ps1') -Manifest $manifest -OutputDirectory $output | Out-Host
 $r=Get-Content (Join-Path $output 'build-report.json') -Raw | ConvertFrom-Json
 [xml]$audit=Get-Content $r.AuditXml -Raw
 [xml]$enforce=Get-Content $r.EnforceXml -Raw
 $auditOptions=@($audit.SelectNodes("//*[local-name()='Rule']/*[local-name()='Option']") | ForEach-Object {$_.InnerText})
 $enfOptions=@($enforce.SelectNodes("//*[local-name()='Rule']/*[local-name()='Option']") | ForEach-Object {$_.InnerText})
 Result 'Modo auditoria' ($auditOptions -contains 'Enabled:Audit Mode') 'Opcion 3 presente'
 Result 'Modo bloqueo' ($enfOptions -notcontains 'Enabled:Audit Mode') 'Opcion 3 ausente'
 Result 'UMCI habilitada' ($enfOptions -contains 'Enabled:UMCI') 'Binarios en modo usuario cubiertos'
 Result 'Script enforcement' ($enfOptions -notcontains 'Disabled:Script Enforcement') 'No se desactiva control de scripts'
 Result 'Sin ISG y Managed Installer' ($enfOptions -notcontains 'Enabled:Intelligent Security Graph Authorization' -and $enfOptions -notcontains 'Enabled:Managed Installer') 'Sin confianza por reputacion/instalador'
 $hashRules=@($audit.SelectNodes("//*[local-name()='FileRules']/*[local-name()='Allow' and @Hash]"))
 Result 'Archivo aprobado por hash WDAC' ($hashRules.Count -ge 1) "hash rules=$($hashRules.Count)"
 Result 'PolicyID igual en audit y enforce' ($audit.SelectSingleNode("//*[local-name()='PolicyID']").InnerText -eq $enforce.SelectSingleNode("//*[local-name()='PolicyID']").InnerText) ([string]$r.PolicyID)
 Result 'CIP valido compilado' ((Get-Item $r.AuditBinary).Length -gt 100 -and (Get-Item $r.EnforceBinary).Length -gt 100) 'Dos binarios'
 foreach($pair in @(@('PS1',$approvedScript),@('MSI',$allowedMsi))) {
  $label=$pair[0];$path=$pair[1]
  if(Test-Path $path) {
   try {
    $generated=@(New-CIPolicyRule -Level Hash -DriverFilePath $path -ErrorAction Stop)
    Result "Hash WDAC para $label" ($generated.Count -gt 0) "rules=$($generated.Count)"
   }catch{Result "Hash WDAC para $label" $false $_.Exception.Message}
  }
 }
 if($Phase -in @('Audit','Enforce')) {
  $binary=if($Phase -eq 'Audit'){$r.AuditBinary}else{$r.EnforceBinary}
  $winrarFile=$null
  if($Phase -eq 'Enforce') {
   $winrarFile=Join-Path $workspace 'winrar-original-desktop-installer.exe'
   Invoke-WebRequest 'https://www.rarlab.com/rar/winrar-x64-723.exe' -OutFile $winrarFile -UseBasicParsing -TimeoutSec 40
   if((Get-Item $winrarFile).Length -lt 2000000){throw 'WinRAR oficial no se pudo descargar correctamente'}
   Result 'WinRAR real descargado' $true 'Installer original de RARLAB en disco antes de aplicar bloqueo'
  }
  if(-not (Get-Command CiTool.exe -ErrorAction SilentlyContinue)){throw 'CiTool no esta disponible'}
  $eventStart=Get-Date
  & CiTool.exe --update-policy $binary | Out-Host
  if($LASTEXITCODE -ne 0){throw "CiTool update exit=$LASTEXITCODE"}
  $deployedId=[string]$r.PolicyID
  & CiTool.exe --refresh | Out-Host
  $policies=(& CiTool.exe --list-policies -json | ConvertFrom-Json).Policies
  $found=@($policies | Where-Object {$_.PolicyID -eq $deployedId -or $_.PolicyID -eq $deployedId.Trim('{}')})
  Result 'Politica registrada por CiTool' ($found.Count -gt 0) "PolicyID=$deployedId"
  LaunchProbe $allowed $true 'Ejecucion EXE permitido'
  LaunchProbe $denied ($Phase -eq 'Audit') 'Ejecucion EXE prohibido'
  if($Phase -eq 'Enforce' -and $winrarFile) {
   $started=$null
   $errorText=''
   $winrarStart=Get-Date
   try {
    $started=Start-Process -FilePath $winrarFile -ArgumentList '/?' -PassThru -ErrorAction Stop
   }catch{$errorText=$_.Exception.Message}
   finally {
    if($started){Stop-Process -Id $started.Id -Force -ErrorAction SilentlyContinue}
   }
   Result 'WinRAR original denegado REALMENTE' ($null -eq $started) "started=$([bool]$started); $errorText"
   $matches=@()
   for($attempt=0;$attempt -lt 10;$attempt++) {
    $we=@(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-CodeIntegrity/Operational';Id=3077;StartTime=$winrarStart.AddSeconds(-2)} -ErrorAction SilentlyContinue)
    $matches=@($we | Where-Object {$_.Message -match 'winrar-original-desktop-installer.exe'})
    if($matches.Count -gt 0){break}
    Start-Sleep -Milliseconds 700
   }
   Result 'Evento WDAC 3077 del instalador WinRAR REAL' ($matches.Count -gt 0) "count=$($matches.Count)"
  }
  $events=@(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-CodeIntegrity/Operational';Id=@(3076,3077);StartTime=$eventStart} -ErrorAction SilentlyContinue)
  $eventID=if($Phase -eq 'Audit'){3076}else{3077}
  $matched=@($events | Where-Object {$_.Id -eq $eventID -and $_.Message -match 'winrar-setup-unapproved'})
  Result "Evento CodeIntegrity $eventID de binario desconocido" ($matched.Count -gt 0) "coincidencias=$($matched.Count)"
 }
}catch{Result 'Excepcion de laboratorio WDAC' $false ($_ | Out-String)}
finally{
 if($deployedId){
  try{
   & CiTool.exe --remove-policy $deployedId | Out-Host
   if($LASTEXITCODE -ne 0){throw "CiTool remove error $LASTEXITCODE"}
   & CiTool.exe --refresh | Out-Host
   Result 'Retirar politica del runner' $true $deployedId
  }catch{Result 'Retirar politica del runner' $false $_.Exception.Message}
 }
 foreach($logName in @('Microsoft-Windows-CodeIntegrity/Operational','Microsoft-Windows-AppLocker/MSI and Script')){
  try {
   $events=@(Get-WinEvent -FilterHashtable @{LogName=$logName;Id=@(3076,3077,3089,8028,8029)} -MaxEvents 80 -ErrorAction SilentlyContinue)
   $log=$logName -replace '[^a-zA-Z0-9]','_'
   ConvertTo-Json -InputObject @($events|Select-Object TimeCreated,Id,Message) -Depth 4 | Set-Content (Join-Path $reportDir ($log+'.json'))
  }catch{Write-Warning $_.Exception.Message}
 }
 $results.ToArray() | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $reportDir 'resultados.json') -Encoding UTF8
 $md=@("# WDAC lab - $([Environment]::OSVersion.VersionString)",'',"Phase: $Phase",'','| Prueba | Estado | Evidencia |','|---|---|---|')
 foreach($t in $results){
  $detail=([string]$t.Detail).Replace('|','/').Replace([char]10,' ').Replace([char]13,' ')
  $md+="| $($t.Name) | $($t.Status) | $detail |"
 }
 $md | Set-Content (Join-Path $reportDir 'resumen.md') -Encoding UTF8
 if($env:GITHUB_STEP_SUMMARY){$md|Add-Content $env:GITHUB_STEP_SUMMARY}
 if(Test-Path (Join-Path $workspace 'output/build-report.json')){Copy-Item (Join-Path $workspace 'output/build-report.json') $reportDir -Force}
}
if(@($results|Where-Object {$_.Status -eq 'FAIL'}).Count -gt 0){exit 1}
