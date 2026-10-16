[CmdletBinding()]
param([ValidateSet('static','audit','enforce')][string]$Mode='audit')
$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path $PSScriptRoot 'Aplicar-ListaBlanca.original.ps1'
$reportDir = Join-Path $PSScriptRoot 'reports'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$checks = New-Object 'System.Collections.Generic.List[object]'
$fatal = $false

function Check([string]$name, [string]$status, [string]$detail) {
    $script:checks.Add([pscustomobject]@{Name=$name;Status=$status;Detail=$detail})
    Write-Host "[$status] $name :: $detail"
}
function Decision([string]$xmlPath, [string]$file) {
    $d = @(Test-AppLockerPolicy -XmlPolicy $xmlPath -Path @($file) -User Everyone -ErrorAction Stop)
    if ($d.Count -ne 1) { throw "Se esperaban 1 resultado para $file, llegaron $($d.Count)" }
    if ($d[0].PSObject.Properties['PolicyDecision']) { return [string]$d[0].PolicyDecision }
    if ($d[0].PSObject.Properties['Result']) { return [string]$d[0].Result }
    throw "Resultado inesperado: $($d[0] | Out-String)"
}
function LiveProbe([string]$path, [string]$label, [bool]$mustRun) {
    $ran = $false
    $detail = ''
    try {
        $proc = Start-Process -FilePath $path -Wait -PassThru -NoNewWindow -ErrorAction Stop
        $ran = ($proc.ExitCode -eq 0)
        $detail = "ExitCode=$($proc.ExitCode)"
    } catch { $detail = $_.Exception.Message }
    Check "Ejecucion real $label" $(if($ran -eq $mustRun){'PASS'}else{'FAIL'}) "se ejecuto=$ran; esperado=$mustRun; $detail"
}

try {
    # Nunca ejecutar el script para extraer su XML.
    $src = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8
    $tokens = $null; $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput($src,[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count -gt 0) { throw "Error de sintaxis PowerShell: $($parseErrors | Out-String)" }
    Check 'Sintaxis del PowerShell' 'PASS' 'Parseado sin ejecucion'

    $match = [regex]::Match($src,'(?ms)^\$Xml\s*=\s*@''\r?\n(?<xml>.*?)\r?\n''@\s*$')
    if (-not $match.Success) { throw 'No se encontro el here-string $Xml' }
    $xmlPath = Join-Path $reportDir 'politica-original.xml'
    [IO.File]::WriteAllText($xmlPath,$match.Groups['xml'].Value,(New-Object System.Text.UTF8Encoding($false)))
    [xml]$xml = Get-Content -LiteralPath $xmlPath -Raw
    $exe = $xml.SelectSingleNode("/AppLockerPolicy/RuleCollection[@Type='Exe']")
    $scripts = $xml.SelectSingleNode("/AppLockerPolicy/RuleCollection[@Type='Script']")
    $appx = $xml.SelectSingleNode("/AppLockerPolicy/RuleCollection[@Type='Appx']")
    if (-not $exe) { throw 'No existe RuleCollection Exe' }
    Check 'XML AppLocker' 'PASS' 'XML valido a nivel de parser; validacion de esquema por cmdlet mas adelante'

    $paths = @($exe.SelectNodes('./FilePathRule[@Action="Allow"]/Conditions/FilePathCondition'))
    $permissive = @($paths | Where-Object { $_.Path -like '%ProgramFiles%*' -or $_.Path -like '%ProgramFiles(x86)%*' })
    Check 'Program Files no abierto a todo' $(if($permissive.Count -eq 0){'PASS'}else{'FAIL'}) "$($permissive.Count) reglas generales"
    Check 'Bloqueo de scripts' $(if($scripts -and $scripts.EnforcementMode -eq 'Enabled'){'PASS'}else{'FAIL'}) "Mode: $(if($scripts){$scripts.EnforcementMode}else{'ausente'})"
    Check 'Reglas de aplicaciones Appx' $(if($appx){'PASS'}else{'FAIL'}) 'Coleccion Appx, no una regla Exe con SID'
    $wild = @($exe.SelectNodes('./FilePublisherRule/Conditions/FilePublisherCondition[@ProductName="*" and @BinaryName="*"]'))
    Check 'Editores limitados por producto' $(if($wild.Count -eq 0){'PASS'}else{'FAIL'}) "$($wild.Count) autorizaciones de TODOS los binarios del editor"

    $i = $src.IndexOf('# Cada corrida reemplaza',[StringComparison]::Ordinal)
    if ($i -lt 0) { throw 'No se encuentra la etapa de reemplazo' }
    $tail = $src.Substring($i)
    $clear = $tail.IndexOf('    Clear-AppLockerLocal',[StringComparison]::Ordinal)
    $guard = $tail.IndexOf('$PSCmdlet.ShouldProcess',[StringComparison]::Ordinal)
    $whatIfSafe = ($guard -ge 0 -and ($clear -lt 0 -or $guard -lt $clear))
    Check 'WhatIf sin borrar antes de ShouldProcess' $(if($whatIfSafe){'PASS'}else{'FAIL'}) "Clear antes del guard=$(-not $whatIfSafe)"

    $command = Get-Command Test-AppLockerPolicy -ErrorAction Stop
    Check 'AppLocker disponible en runner' 'PASS' "$($command.Name), $([Environment]::OSVersion.Version)"

    # Unsigned program built locally, so publisher wildcard cannot mistakenly allow it.
    $probeDir = Join-Path $env:RUNNER_TEMP 'AppLocker-CI-Probe'
    New-Item -ItemType Directory -Path $probeDir -Force | Out-Null
    $tempExe = Join-Path $probeDir 'probe-no-autorizado.exe'
    $cs = @'
using System;
public static class CIAppLockerProbe {
 public static int Main() { Console.WriteLine("APPLOCKER_CI_PROBE"); return 0; }
}
'@
    Add-Type -TypeDefinition $cs -OutputAssembly $tempExe -OutputType ConsoleApplication
    $pfDir = Join-Path $env:ProgramFiles 'AppLocker-CI-Probe'
    New-Item -ItemType Directory -Path $pfDir -Force | Out-Null
    $pfExe = Join-Path $pfDir 'probe-no-autorizado.exe'
    Copy-Item -LiteralPath $tempExe -Destination $pfExe -Force

    $tempDecision = Decision $xmlPath $tempExe
    $pfDecision = Decision $xmlPath $pfExe
    Check 'Simulacion: EXE en temporal denegado' $(if($tempDecision -match '^Denied'){'PASS'}else{'FAIL'}) $tempDecision
    Check 'Simulacion: EXE en Program Files denegado' $(if($pfDecision -match '^Denied'){'PASS'}else{'FAIL'}) $pfDecision
    "TEMP: $tempDecision" | Set-Content (Join-Path $reportDir 'decisiones.txt')
    "PROGRAM_FILES: $pfDecision" | Add-Content (Join-Path $reportDir 'decisiones.txt')

    if ($Mode -ne 'static') {
        # Host runner is disposable. Windows Server, not a Windows 11 client.
        $auditLog = Join-Path $reportDir 'aplicar-auditoria.txt'
        try {
            & $sourcePath -Auditar *>&1 | Out-File -FilePath $auditLog -Encoding utf8
            Check 'Aplicar script -Auditar' 'PASS' 'El script termino sin error'
        } catch {
            Check 'Aplicar script -Auditar' 'FAIL' $_.Exception.Message
            $_ | Out-String | Add-Content $auditLog
            $fatal = $true
        }
        if (-not $fatal) {
            try {
                $effective = Get-AppLockerPolicy -Effective -Xml -ErrorAction Stop
                $effective | Set-Content (Join-Path $reportDir 'politica-efectiva.xml')
                [xml]$eff = $effective
                $exeEff = $eff.SelectSingleNode("/AppLockerPolicy/RuleCollection[@Type='Exe']")
                $effectiveMode = if($exeEff){[string]$exeEff.EnforcementMode}else{'ausente'}
                Check 'Politica efectiva en auditoria' $(if($effectiveMode -eq 'AuditOnly'){'PASS'}else{'FAIL'}) "EXE=$effectiveMode"
            } catch {
                Check 'Leer politica efectiva' 'FAIL' $_.Exception.Message
                $fatal = $true
            }
        }
        if ($Mode -eq 'enforce' -and -not $fatal) {
            # Explicit opt-in only. May prevent Actions tooling from running.
            $enforceLog = Join-Path $reportDir 'aplicar-bloqueo.txt'
            try {
                & $sourcePath *>&1 | Out-File -FilePath $enforceLog -Encoding utf8
                Check 'Aplicar script en bloqueo' 'PASS' 'Set-AppLockerPolicy termino'
                LiveProbe $tempExe 'no listado en TEMP' $false
                LiveProbe $pfExe 'no listado en Program Files' $false
            } catch {
                Check 'Aplicar script en bloqueo' 'FAIL' $_.Exception.Message
                $_ | Out-String | Add-Content $enforceLog
                $fatal = $true
            }
        }
    }
} catch {
    Check 'Error inesperado' 'ERROR' $_.Exception.Message
    $fatal = $true
} finally {
    foreach($logName in @('Microsoft-Windows-AppLocker/EXE and DLL','Microsoft-Windows-AppLocker/MSI and Script')) {
        try {
            $events = @(Get-WinEvent -FilterHashtable @{LogName=$logName;Id=@(8003,8004,8006,8007)} -MaxEvents 50 -ErrorAction SilentlyContinue)
            $events | Select-Object TimeCreated,Id,Message |
                ConvertTo-Json -Depth 3 | Set-Content (Join-Path $reportDir (($logName -replace '[^A-Za-z0-9]','_')+'.json'))
        } catch { Write-Warning $_.Exception.Message }
    }
    @($checks.ToArray()) | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $reportDir 'resultados.json') -Encoding utf8
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add("# Diagnostico AppLocker - $([Environment]::OSVersion.Version)")
    $lines.Add("Modo: **$Mode**. GitHub-hosted Windows Server, no Windows 11.")
    $lines.Add('')
    $lines.Add('| Prueba | Estado | Evidencia |')
    $lines.Add('|---|---|---|')
    foreach($r in $checks) {
        $detail = ([string]$r.Detail).Replace('|','/').Replace([char]13,' ').Replace([char]10,' ')
        $lines.Add("| $($r.Name) | $($r.Status) | $detail |")
    }
    $lines | Set-Content (Join-Path $reportDir 'resumen.md') -Encoding utf8
    if ($env:GITHUB_STEP_SUMMARY) { $lines | Add-Content $env:GITHUB_STEP_SUMMARY -Encoding utf8 }
}
if ($fatal -or @($checks | Where-Object {$_.Status -in @('FAIL','ERROR')}).Count -gt 0) { exit 1 }
