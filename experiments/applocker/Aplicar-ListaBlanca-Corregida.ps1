#requires -Version 5.1
<#
.SYNOPSIS
  Generador y aplicador de lista blanca AppLocker, Windows 10/11.
.DESCRIPTION
  Reglas de HASH Authenticode generadas desde los archivos reales aprobados.
  Deniega de forma predeterminada EXE, MSI, scripts, Appx y DLL.
  El sistema operativo tiene excepcion por directorio %WINDIR% con subdirectorios
  tipicamente modificables por usuarios excluidos. NO es una politica WDAC.
  Ejecutar primero -Accion Generar y -Accion Auditar en VM con snapshot.
  Ninguna cuenta con privilegios admin locales debe considerarse restringida.
.EXAMPLE
  .\Aplicar-ListaBlanca-Corregida.ps1 -Accion Generar
  .\Aplicar-ListaBlanca-Corregida.ps1 -Accion Auditar
  .\Aplicar-ListaBlanca-Corregida.ps1 -Accion Aplicar -Confirm:$false
  .\Aplicar-ListaBlanca-Corregida.ps1 -Accion Revertir -Confirm:$false
#>
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
    [ValidateSet('Generar','Auditar','Aplicar','Ver','Probar','Revertir')]
    [string]$Accion = 'Generar',
    [string]$Manifest = (Join-Path $PSScriptRoot 'lista-blanca.json'),
    [string]$Salida = (Join-Path $env:ProgramData 'AppLockerListaBlanca\politica.xml'),
    [string]$ArchivoPrueba,
    [switch]$GenerarBloqueo
)
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:ProgramData 'AppLockerListaBlanca'
$backup = Join-Path $root 'anterior-local.xml'
$everyone = 'S-1-1-0'

function Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Attr([System.Xml.XmlElement]$element,[string]$key,[string]$value) {
    $element.SetAttribute($key,$value)
}
function Node([System.Xml.XmlElement]$parent,[string]$name) {
    $node = $parent.OwnerDocument.CreateElement($name)
    [void]$parent.AppendChild($node)
    return $node
}
function PathRule([System.Xml.XmlElement]$collection,[string]$path,[string]$name,[string[]]$exceptions=@()) {
    $r = Node $collection 'FilePathRule'
    Attr $r 'Id' ([Guid]::NewGuid().ToString())
    Attr $r 'Name' $name
    Attr $r 'Description' 'Regla revisada del sistema / sentinel'
    Attr $r 'UserOrGroupSid' $everyone
    Attr $r 'Action' 'Allow'
    $conditions = Node $r 'Conditions'
    $condition = Node $conditions 'FilePathCondition'
    Attr $condition 'Path' $path
    if ($exceptions.Count -gt 0) {
        $except = Node $r 'Exceptions'
        foreach($e in $exceptions) {
            $item = Node $except 'FilePathCondition'
            Attr $item 'Path' $e
        }
    }
}
function PackageRule([System.Xml.XmlElement]$collection,[string]$publisher,[string]$product) {
    $r = Node $collection 'FilePublisherRule'
    Attr $r 'Id' ([Guid]::NewGuid().ToString())
    Attr $r 'Name' "Paquete especifico $product"
    Attr $r 'Description' 'Nombre de paquete exacto, no todos los editores'
    Attr $r 'UserOrGroupSid' $everyone
    Attr $r 'Action' 'Allow'
    $conditions = Node $r 'Conditions'
    $condition = Node $conditions 'FilePublisherCondition'
    Attr $condition 'PublisherName' $publisher
    Attr $condition 'ProductName' $product
    Attr $condition 'BinaryName' '*'
    $range = Node $condition 'BinaryVersionRange'
    Attr $range 'LowSection' '0.0.0.0'
    Attr $range 'HighSection' '*'
}
function Read-Manifest {
    if(-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) { throw "Falta manifiesto: $Manifest" }
    $data = Get-Content -LiteralPath $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $data.Files -or $null -eq $data.PackagedApps) {
        throw 'El manifiesto debe contener Files y PackagedApps (arrays, pueden ser vacios).'
    }
    return $data
}
function Create-Policy([string]$enforcement) {
    $data = Read-Manifest
    $xml = New-Object System.Xml.XmlDocument
    [void]$xml.LoadXml('<AppLockerPolicy Version="1"/>')
    $collections = @{}
    foreach($type in @('Exe','Msi','Script','Appx','Dll')) {
        $col = Node $xml.DocumentElement 'RuleCollection'
        Attr $col 'Type' $type
        Attr $col 'EnforcementMode' $enforcement
        $collections[$type] = $col
    }

    # Una coleccion SIN reglas deja pasar TODO. Cada coleccion tiene un sentinel
    # que un usuario estandar no puede fabricar bajo Windows\System32.
    foreach($type in @('Exe','Msi','Script','Dll')) {
        PathRule $collections[$type] '%WINDIR%\System32\__APPLCK_SENTINEL_NO_CREAR_5C7B35__\*' "Sentinel deny-by-default $type"
    }

    # Windows requiere una base para funcionar. NUNCA autorizar Program Files entero.
    # AVISO: cualquier carpeta adicional escribible por Users en Windows necesita
    # excepcion. Auditar ACLs reales antes de produccion.
    $excluded = @(
        '%WINDIR%\Temp\*',
        '%WINDIR%\Tasks\*',
        '%WINDIR%\debug\*',
        '%WINDIR%\addins\*',
        '%WINDIR%\tracing\*',
        '%WINDIR%\System32\spool\drivers\color\*',
        '%WINDIR%\Registration\*'
    )
    foreach($type in @('Exe','Script','Dll')) {
        PathRule $collections[$type] '%WINDIR%\*' "Base protegida Windows para $type" $excluded
    }

    $approved = @($data.Files)
    $dupes = @{}
    foreach($entry in $approved) {
        if($entry -isnot [string] -or [string]::IsNullOrWhiteSpace($entry)) {
            throw 'Files solo puede contener rutas completas de archivos, no carpetas ni patrones.'
        }
        if($entry.IndexOf('*') -ge 0 -or $entry.IndexOf('?') -ge 0) {
            throw "No se permiten comodines: $entry"
        }
        if(-not [IO.Path]::IsPathRooted($entry) -or -not (Test-Path -LiteralPath $entry -PathType Leaf)) {
            throw "Archivo permitido ausente: $entry"
        }
        $canonical = (Resolve-Path -LiteralPath $entry).ProviderPath
        $extension = [IO.Path]::GetExtension($canonical).ToLowerInvariant()
        $type = switch($extension) {
            '.exe' {'Exe'} '.com' {'Exe'}
            '.msi' {'Msi'} '.msp' {'Msi'} '.mst' {'Msi'}
            '.ps1' {'Script'} '.bat' {'Script'} '.cmd' {'Script'}
            '.vbs' {'Script'} '.js' {'Script'}
            '.dll' {'Dll'} '.ocx' {'Dll'}
            default { throw "Extension fuera de las colecciones de AppLocker: $canonical" }
        }
        if($dupes.ContainsKey($canonical.ToLowerInvariant())) { continue }
        $dupes[$canonical.ToLowerInvariant()] = $true
        $fileInfo = @(Get-AppLockerFileInformation -Path $canonical -ErrorAction Stop)
        if($fileInfo.Count -eq 0) { throw "No se pudo leer AppLockerFileInformation: $canonical" }
        # SHA256 del instalador descargado NO es el FileHash de AppLocker:
        # el cmdlet crea hashes compatibles con AppLocker a partir del archivo real.
        [xml]$built = New-AppLockerPolicy -FileInformation $fileInfo -RuleType Hash -User Everyone -Xml -ErrorAction Stop
        $generated = $built.SelectSingleNode("/AppLockerPolicy/RuleCollection[@Type='$type']")
        if(-not $generated) { throw "No se genero coleccion $type para $canonical" }
        $hashes = @($generated.SelectNodes('./FileHashRule'))
        if($hashes.Count -ne 1) { throw "Se esperaba 1 regla hash para $canonical, hay $($hashes.Count)" }
        [void]$collections[$type].AppendChild($xml.ImportNode($hashes[0],$true))
    }

    # Solo paquetes declarados por nombre EXACTO. No hay wildcard de editor.
    # Se preservan algunos paquetes esenciales de la interfaz de Windows.
    $packageNames = @(
        'windows.immersivecontrolpanel',
        'Microsoft.Windows.ShellExperienceHost',
        'Microsoft.Windows.StartMenuExperienceHost',
        'MicrosoftWindows.Client.CBS',
        'MicrosoftWindows.Client.Core',
        'Microsoft.SecHealthUI'
    ) + @($data.PackagedApps)
    $seen = @{}
    $packages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    foreach($name in $packageNames) {
        if([string]::IsNullOrWhiteSpace($name) -or $name.IndexOf('*') -ge 0) {
            throw "Nombre de paquete no valido: $name"
        }
        $pkg = $packages | Where-Object {$_.Name -eq $name} | Select-Object -First 1
        if(-not $pkg) { continue }
        $key = "$($pkg.Publisher)|$($pkg.Name)"
        if(-not $seen.ContainsKey($key)) {
            PackageRule $collections['Appx'] ([string]$pkg.Publisher) ([string]$pkg.Name)
            $seen[$key] = $true
        }
    }
    # Appx sin ninguna regla tambien se deja ejecutar. Crear regla deliberadamente
    # inalcanzable para denegar todos los paquetes no enumerados.
    PackageRule $collections['Appx'] 'CN=APPLOCKER-NO-EXISTE-5C7B35' 'AppLockerNoExiste5C7B35'

    if($collections['Exe'].SelectNodes('./FilePathRule[Conditions/FilePathCondition[@Path="%ProgramFiles%\*"]]').Count -gt 0) {
        throw 'Regla Program Files global prohibida'
    }
    return $xml
}
function Service-Identity {
    $s = Get-Service AppIDSvc -ErrorAction Stop
    if($s.Status -ne 'Running') {
        # AppIDSvc protegido: si Windows niega configurar el inicio, fallar.
        & sc.exe config AppIDSvc start= auto | Out-Host
        if($LASTEXITCODE -ne 0) { throw "No se pudo habilitar AppIDSvc (sc.exe exit $LASTEXITCODE)" }
        Start-Service -Name AppIDSvc -ErrorAction Stop
    }
    if((Get-Service AppIDSvc).Status -ne 'Running') {
        throw 'AppIDSvc no esta Running: no hay garantia de aplicacion'
    }
}
function Assert-Effective([System.Xml.XmlDocument]$expected) {
    $lastError = ''
    # Get-AppLockerPolicy -Effective puede actualizarse de forma diferida luego
    # de Set-AppLockerPolicy (especialmente AuditOnly -> Enabled). No asumir
    # exito sin comprobar todas las colecciones y todas las reglas.
    for($attempt=0;$attempt -lt 20;$attempt++) {
        $lastError = ''
        [xml]$effective = Get-AppLockerPolicy -Effective -Xml -ErrorAction Stop
        foreach($type in @('Exe','Msi','Script','Appx','Dll')) {
            $e = $expected.SelectSingleNode("/AppLockerPolicy/RuleCollection[@Type='$type']")
            $a = $effective.SelectSingleNode("/AppLockerPolicy/RuleCollection[@Type='$type']")
            if(-not $a -or $a.EnforcementMode -ne $e.EnforcementMode) {
                $realMode = if($a){$a.EnforcementMode}else{'ausente'}
                $lastError = "Enforcement $type esperado=$($e.EnforcementMode), efectivo=$realMode"
                break
            }
            foreach($rule in @($e.SelectNodes('./*'))) {
                $id = $rule.GetAttribute('Id')
                if(-not $a.SelectSingleNode("./*[@Id='$id']")) {
                    $lastError = "Falta regla $id de $type en politica efectiva"
                    break
                }
            }
            if($lastError){break}
        }
        if(-not $lastError) {
            Write-Host "OK: politica efectiva coincide ($($attempt+1) lectura/s)"
            return
        }
        Start-Sleep -Seconds 1
    }
    [xml]$local = Get-AppLockerPolicy -Local -Xml -ErrorAction Stop
    $localExe = $local.SelectSingleNode("/AppLockerPolicy/RuleCollection[@Type='Exe']")
    throw "Politica EFECTIVA no coincide tras 20s. $lastError; EXE local=$($localExe.EnforcementMode). Revisar GPO/CSP."
}
function Probe([string]$file) {
    if(-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "No existe $file" }
    $decision = @(Get-AppLockerPolicy -Effective | Test-AppLockerPolicy -Path @($file) -User Everyone)
    $decision | Format-List *
}
function Write-Xml([xml]$doc,[string]$dest) {
    $parent = Split-Path -Path $dest -Parent
    if(-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $doc.Save($dest)
}

Import-Module AppLocker -ErrorAction Stop
if($Accion -eq 'Ver') {
    Write-Host "AppIDSvc: $((Get-Service AppIDSvc).Status)"
    [xml]$current = Get-AppLockerPolicy -Effective -Xml
    foreach($col in $current.AppLockerPolicy.RuleCollection) {
        Write-Host "$($col.Type): $($col.EnforcementMode)"
    }
    return
}
if($Accion -eq 'Probar') {
    if(-not $ArchivoPrueba) { throw 'Usar -ArchivoPrueba C:\ruta\programa.exe' }
    Probe $ArchivoPrueba
    return
}
if($Accion -eq 'Revertir') {
    if(-not (Admin)) { throw 'Se requiere Administrador para restaurar politica.' }
    if(-not (Test-Path -LiteralPath $backup)) { throw "No existe copia anterior: $backup" }
    if($PSCmdlet.ShouldProcess('AppLocker','restaurar politica local anterior')) {
        Set-AppLockerPolicy -XmlPolicy $backup -ErrorAction Stop
        Write-Host "Politica local restaurada desde: $backup"
    }
    return
}
$mode = if($Accion -eq 'Aplicar' -or $GenerarBloqueo) {'Enabled'} else {'AuditOnly'}
$doc = Create-Policy $mode
Write-Host "Politica generada: Exe, Msi, Script, Appx y Dll en $mode"
if($Accion -eq 'Generar') {
    if($PSCmdlet.ShouldProcess($Salida,'guardar XML sin aplicar')) {
        Write-Xml $doc $Salida
        Write-Host "XML guardado: $Salida"
    }
    return
}
if(-not (Admin)) { throw 'Se requiere PowerShell como Administrador para aplicar politica.' }
if($PSCmdlet.ShouldProcess('AppLocker','guardar backup, reemplazar politica local y activar AppIDSvc')) {
    if(-not (Test-Path -LiteralPath $backup)) {
        if(-not (Test-Path $root)) { New-Item -ItemType Directory -Force -Path $root | Out-Null }
        $previous = Get-AppLockerPolicy -Local -Xml -ErrorAction Stop
        [IO.File]::WriteAllText($backup,$previous,(New-Object System.Text.UTF8Encoding($false)))
        Write-Host "Backup local en: $backup"
    }
    Write-Xml $doc $Salida
    # Sin -Merge: reemplaza en lugar de sumar reglas permisivas anteriores.
    # No hay borrado previo que deje una ventana sin politica.
    Set-AppLockerPolicy -XmlPolicy $Salida -ErrorAction Stop
    Service-Identity
    Assert-Effective $doc
    Write-Host 'ATENCION: validar ejecucion real como usuario NO ADMINISTRADOR y eventos AppLocker.'
    Write-Host 'Una politica AppLocker no impide PowerShell -Command ni el CLM de .ps1 bloqueados.'
}
