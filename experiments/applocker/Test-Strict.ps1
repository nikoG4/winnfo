#requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('simulate','audit','enforce')][string]$Phase='simulate')
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$work=Join-Path $env:RUNNER_TEMP 'AppLockerStrictLab'
New-Item -ItemType Directory -Path $work -Force | Out-Null
$results=New-Object 'System.Collections.Generic.List[object]'
function Result([string]$name,[bool]$ok,[string]$info) {
    $status=if($ok){'PASS'}else{'FAIL'}
    $script:results.Add([pscustomobject]@{Name=$name;Status=$status;Info=$info})
    Write-Host "[$status] $name => $info"
}
function CheckDecision([string]$path,[bool]$shouldAllow,[string]$label,[string]$policy) {
    try {
        $decisions=@(Test-AppLockerPolicy -XmlPolicy $policy -Path @($path) -User Everyone -ErrorAction Stop)
        if($decisions.Count -ne 1){throw "Numero de resultados $($decisions.Count)"}
        $p=$decisions[0]
        $decision=if($p.PSObject.Properties['PolicyDecision']){[string]$p.PolicyDecision}else{[string]$p.Result}
        $allowed=($decision -eq 'Allowed' -or $decision -eq 'AllowedByDefault')
        Result $label ($allowed -eq $shouldAllow) "result=$decision expectedAllow=$shouldAllow"
    } catch { Result $label $false $_.Exception.Message }
}
function Probe([string]$path,[bool]$expectRun,[string]$label) {
    try {
        $p=Start-Process -FilePath $path -Wait -NoNewWindow -PassThru -ErrorAction Stop
        $ran=($p.ExitCode -eq 0)
        Result $label ($ran -eq $expectRun) "process completed=$ran exit=$($p.ExitCode)"
    } catch {
        Result $label (-not $expectRun) "process denied: $($_.Exception.Message)"
    }
}

try {
    $cs=@'
using System;
public static class AllowedProbe {
    public static int Main() { Console.WriteLine("CI-ALLOWED"); return 0; }
}
'@
    $approved=Join-Path $work 'approved.exe'
    Add-Type -TypeDefinition $cs -OutputAssembly $approved -OutputType ConsoleApplication -ErrorAction Stop
    $unapproved=Join-Path $work 'WinRAR-installer-unlisted.exe'
    Copy-Item $env:WINDIR\System32\notepad.exe $unapproved
    # A Windows-signed executable on Desktop tests denial even when its publisher is trusted.
    $desktop=Join-Path $work 'Desktop'
    New-Item -ItemType Directory -Path $desktop -Force | Out-Null
    $desktopExe=Join-Path $desktop 'WinRAR-setup-unsigned.exe'
    Copy-Item -LiteralPath $approved -Destination $desktopExe
    $pf=Join-Path $env:ProgramFiles 'AppLocker-Strict-Probe'
    New-Item -ItemType Directory -Path $pf -Force | Out-Null
    $pfExe=Join-Path $pf 'WinRAR-installer-not-listed.exe'
    Copy-Item -LiteralPath $approved -Destination $pfExe
    $bat=Join-Path $work 'unlisted.bat'
    $cmd=Join-Path $work 'unlisted.cmd'
    $ps1=Join-Path $work 'unlisted.ps1'
    $vbs=Join-Path $work 'unlisted.vbs'
    $js=Join-Path $work 'unlisted.js'
    Set-Content $bat '@echo off & echo unlisted-bat'
    Set-Content $cmd '@echo off & echo unlisted-cmd'
    Set-Content $ps1 'Write-Output "this is a deliberately unapproved script"'
    Set-Content $vbs 'WScript.Echo "unapproved"'
    Set-Content $js 'WScript.Echo("unapproved");'
    $approvedScript=Join-Path $work 'approved.bat'
    Set-Content $approvedScript '@echo off'

    $msi=Join-Path $work 'WinRAR-unlisted.msi'
    try {
        $installer=New-Object -ComObject WindowsInstaller.Installer
        $db=$installer.OpenDatabase($msi,3)
        $view=$db.OpenView('CREATE TABLE `Property` (`Property` CHAR(72) NOT NULL, `Value` CHAR(0) NOT NULL PRIMARY KEY `Property`)')
        $view.Execute()
        $db.Commit()
        $view.Close()
        [Runtime.InteropServices.Marshal]::ReleaseComObject($view) | Out-Null
        [Runtime.InteropServices.Marshal]::ReleaseComObject($db) | Out-Null
        [Runtime.InteropServices.Marshal]::ReleaseComObject($installer) | Out-Null
        Result 'MSI de laboratorio creado' $true "$msi"
    } catch { Result 'MSI de laboratorio creado' $false $_.Exception.Message }

    $config=Join-Path $work 'approved.json'
    @{Files=@($approved,$approvedScript); PackagedApps=@()} |
        ConvertTo-Json -Depth 5 | Set-Content -Path $config -Encoding UTF8
    $xmlPath=Join-Path $work 'strict-policy.xml'
    $script=Join-Path $here 'Aplicar-ListaBlanca-Corregida.ps1'
    & $script -Accion Generar -GenerarBloqueo -Manifest $config -Salida $xmlPath -Confirm:$false
    if(-not (Test-Path $xmlPath)){throw 'No se genero XML de la politica'}
    [xml]$xml=Get-Content $xmlPath -Raw
    $types=@('Exe','Msi','Script','Appx','Dll')
    foreach($type in $types) {
        $col=$xml.SelectSingleNode("/AppLockerPolicy/RuleCollection[@Type='$type']")
        Result "Coleccion $type activa" ([bool]$col -and $col.EnforcementMode -eq 'Enabled') "rules=$(@($col.ChildNodes).Count)"
    }
    $broad=@($xml.SelectNodes('//FilePathCondition[@Path="%ProgramFiles%\*" or @Path="%ProgramFiles(x86)%\*"]'))
    Result 'Sin permisos globales de Program Files' ($broad.Count -eq 0) "$($broad.Count) reglas abiertas"
    $pubBroad=@($xml.SelectNodes('//FilePublisherCondition[@ProductName="*" and @BinaryName="*"]'))
    Result 'Sin editores completamente abiertos' ($pubBroad.Count -eq 0) "$($pubBroad.Count) reglas abiertas"
    $hashes=@($xml.SelectNodes('//FileHashRule'))
    Result 'Hashes nativos AppLocker para archivos exactos' ($hashes.Count -eq 2) "$($hashes.Count) hashes"

    CheckDecision $approved $true 'EXE aprobado por hash' $xmlPath
    CheckDecision $approvedScript $true 'BAT aprobado por hash' $xmlPath
    CheckDecision $desktopExe $true 'Identico hash, distinta carpeta (comportamiento esperado)' $xmlPath
    CheckDecision $unapproved $false 'EXE firmado de Windows movido a TEMP' $xmlPath
    CheckDecision $pfExe $true 'Mismo hash aprobado copiado a Program Files' $xmlPath

    # Un EXE de contenido NUEVO en Program Files se debe denegar.
    $different=Join-Path $pf 'unlisted2.exe'
    Copy-Item $env:WINDIR\System32\notepad.exe $different
    CheckDecision $different $false 'EXE desconocido en Program Files' $xmlPath
    foreach($p in @($bat,$cmd,$ps1,$vbs,$js)) {
        CheckDecision $p $false ("Script no aprobado: "+[IO.Path]::GetExtension($p)) $xmlPath
    }
    if(Test-Path $msi) { CheckDecision $msi $false 'MSI no aprobado' $xmlPath }

    # Descarga oficial WinRAR: no ejecutamos jamas el instalador durante la prueba.
    $winrar=Join-Path $desktop 'winrar-x64-723.exe'
    try {
        Invoke-WebRequest 'https://www.rarlab.com/rar/winrar-x64-723.exe' -OutFile $winrar -UseBasicParsing -TimeoutSec 25
        if((Get-Item $winrar).Length -lt 2000000){throw 'Descarga no parece WinRAR'}
        CheckDecision $winrar $false 'Instalador REAL WinRAR 7.23 en escritorio' $xmlPath
    } catch {
        Write-Warning "WinRAR oficial no se pudo descargar/probar: $($_.Exception.Message)"
        Result 'Instalador real WinRAR disponible para prueba' $false $_.Exception.Message
    }

    if($Phase -in @('audit','enforce')) {
        & $script -Accion Auditar -Manifest $config -Salida $xmlPath -Confirm:$false
        [xml]$effective=Get-AppLockerPolicy -Effective -Xml
        $effectiveExe=$effective.SelectSingleNode("/AppLockerPolicy/RuleCollection[@Type='Exe']")
        Result 'Aplicado modo Auditoria' ($effectiveExe.EnforcementMode -eq 'AuditOnly') "EXE=$($effectiveExe.EnforcementMode)"
    }
    if($Phase -eq 'enforce') {
        # En runners descartables GitHub solamente. Puede matar el propio runner.
        & $script -Accion Aplicar -Manifest $config -Salida $xmlPath -Confirm:$false
        [xml]$effective=Get-AppLockerPolicy -Effective -Xml
        $effectiveExe=$effective.SelectSingleNode("/AppLockerPolicy/RuleCollection[@Type='Exe']")
        Result 'Aplicado bloqueo efectivo' ($effectiveExe.EnforcementMode -eq 'Enabled') "EXE=$($effectiveExe.EnforcementMode)"
        Probe $approved $true 'Ejecucion real EXE permitido'
        Probe $different $false 'Ejecucion real EXE en Program Files rechazado'
        Probe $desktopExe $true 'Ejecucion real de EXE permitido por hash'
        # No ejecutamos WinRAR en caso de fallo para evitar instalar sin permiso.
    }
} catch {
    Result 'Error de infraestructura/generacion' $false $_.Exception.Message
} finally {
    $summary=@('# Pruebas de lista blanca AppLocker corregida','','SO: '+[Environment]::OSVersion.VersionString,'Phase: '+$Phase,'','| Prueba | Estado | Detalle |','|---|---|---|')
    foreach($r in $results) {
        $summary+=('| '+$r.Name+' | '+$r.Status+' | '+($r.Info -replace '[|]','/')+' |')
    }
    $summary | Set-Content (Join-Path $work 'report.md') -Encoding UTF8
    $results.ToArray() | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $work 'report.json')
    if($env:GITHUB_STEP_SUMMARY) {$summary | Add-Content $env:GITHUB_STEP_SUMMARY}
    if($env:GITHUB_WORKSPACE) {
        $out=Join-Path $env:GITHUB_WORKSPACE 'experiments/applocker/strict-reports'
        New-Item -ItemType Directory -Path $out -Force | Out-Null
        Copy-Item -Path (Join-Path $work 'report.*') -Destination $out -Force
        if(Test-Path $xmlPath){Copy-Item $xmlPath (Join-Path $out 'generated-policy.xml') -Force}
    }
}
if(@($results | Where-Object {$_.Status -eq 'FAIL'}).Count -gt 0){exit 1}
