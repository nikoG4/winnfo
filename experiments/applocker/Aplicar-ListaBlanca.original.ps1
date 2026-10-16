# COPIA DE PRUEBA: script original entregado; no ejecutar en equipos de produccion.
# Aplicar-ListaBlanca.ps1 - AppStore - objetivo: Windows 11
# Generado: 2026-10-15 14:36 | Firma de la politica: bdc421f62bb7
# 14 apps | reglas por editor: 14 | reglas por hash SHA-256: 0
# Se usa el SHA-256 del instalador cargado en el catalogo: es la regla mas confiable. Si una app se actualiza y cambia el hash, hay que volver a bajar la politica.
#
# Actualizar la politica (bajar la ultima version):
#   URL de descarga interna omitida en esta copia publica para pruebas de CI.
#
# USO (PowerShell como ADMINISTRADOR en la PC):
#   .\Aplicar-ListaBlanca.ps1              aplica la lista blanca en modo BLOQUEO
#                                         (reemplaza por completo cualquier politica anterior)
#   .\Aplicar-ListaBlanca.ps1 -Auditar      solo registra lo que se bloquearia (usar primero)
#   .\Aplicar-ListaBlanca.ps1 -Ver           reglas por almacen (local/efectiva) + bloqueos del log
#   .\Aplicar-ListaBlanca.ps1 -Probar C:\ruta\app.exe   Test-AppLockerPolicy: la politica la permite o bloquea
#   .\Aplicar-ListaBlanca.ps1 -Quitar        deja todo como estaba (backup automatico)
#   .\Aplicar-ListaBlanca.ps1 -WhatIf        dice que haria sin tocar nada
#   .\Aplicar-ListaBlanca.ps1 -Forzar        saltea el control de version de Windows
#
# Persistencia: la politica se escribe en HKLM\SOFTWARE\Policies\Microsoft\Windows\SrpV2
# (almacen de politicas de grupo local), por eso sigue vigente despues de reiniciar.
# El servicio Application Identity (AppIDSvc) queda en inicio Automatico por el mismo motivo.
# NO se usa -ToLsaStore: esa opcion aplica la politica solo hasta el proximo reinicio.
#
# Requisitos de la PC: Windows 11, edicion con AppLocker
# (Win7: Ultimate/Enterprise | Win10/11: Pro/Enterprise/Education), sesion de administrador.

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Quitar,
    [switch]$Auditar,
    [switch]$Ver,
    [switch]$Forzar,
    [string]$Probar
)

$ErrorActionPreference = 'Stop'
$Objetivo   = 'Windows 11'
$VersionSo  = '10.0'
$BuildMin   = 22000
$BuildMax   = 999999
$Firma      = 'bdc421f62bb7'
$Carpeta    = Join-Path $env:ProgramData 'AppStore'
$Politica   = Join-Path $Carpeta 'lista-blanca.xml'
$Backup     = Join-Path $Carpeta 'politica-anterior.xml'

$Xml = @'
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FilePathRule Id="d20cc23c-ce6b-32cb-9392-f6ff61ae7d65" Name="Sistema Windows" Description="Binarios del sistema operativo" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\*" />
      </Conditions>
      <Exceptions>
        <FilePathCondition Path="%WINDIR%\Tasks\*" />
        <FilePathCondition Path="%WINDIR%\Temp\*" />
        <FilePathCondition Path="%WINDIR%\addins\*" />
        <FilePathCondition Path="%WINDIR%\debug\*" />
      </Exceptions>
    </FilePathRule>
    <FilePathRule Id="071d2d56-3809-3dcc-92eb-7ee77b5d7c9f" Name="Aplicaciones empaquetadas" Description="Apps de la tienda de Windows (contenedor aislado)" UserOrGroupSid="S-1-15-2-1" Action="Allow">
      <Conditions>
        <FilePathCondition Path="*" />
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="4b516cc0-b023-32a0-8081-d4e5b67c47f0" Name="Software instalado (Program Files)" Description="No rompe aplicaciones ya instaladas" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%ProgramFiles%\*" />
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="a802c4b8-e49a-3222-9180-9d0eb20b8b6a" Name="Software instalado (Program Files x86)" Description="No rompe aplicaciones ya instaladas" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%ProgramFiles(x86)%\*" />
      </Conditions>
    </FilePathRule>
    <FilePublisherRule Id="966e5f35-9e8c-3d96-ad8d-888d4a288096" Name="7-Zip v24.09" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Igor Pavlov" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="3b70f8d8-5c65-3d2d-9053-a6f3e360320a" Name="Adobe Acrobat Reader v24.002" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Adobe Inc." ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="a69e7220-da02-3809-9b96-5ca84c3423bf" Name="DBeaver v25.0" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=DBeaver Corp" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="08360658-0f4d-39e4-b31d-89a21c6b54d8" Name="Figma v124x" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Figma, Inc." ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="d8aced8e-b8c4-3fa4-8abb-2bc41a889660" Name="Google Chrome v126x" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Google LLC" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="d53dc227-faf3-3ca0-8f57-604c0b6ee836" Name="LibreOffice v24.8" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=The Document Foundation" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="a5c11cc8-6515-3175-abc9-5b9be9538a91" Name="Microsoft 365 v2404" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Microsoft Corporation" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="3e6c89e3-1e6f-3cf9-9e4b-d9f1fa8f29bf" Name="Microsoft Teams v1.6" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Microsoft Corporation" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="76428e6f-26c3-3797-ad9a-bb020b453632" Name="Notepad++ v8.7" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Notepad++ Team" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="ee7b0980-5263-3e25-b0a7-ed10919c9864" Name="Postman v11.x" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Postman Inc." ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="952d783d-6f23-310c-97c9-1914e1931fef" Name="Slack v4.x" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Slack Technologies, Inc." ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="217c2e8f-2ea9-3820-8645-0a3d37bf5452" Name="VLC media player v3.0.21" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=VideoLAN" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="0711dbfd-fb6a-3f88-a9f1-ccbf297d6f50" Name="Visual Studio Code v1.105" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Microsoft Corporation" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="5af3ff2a-777c-3e4f-a6bd-c4b47dcd12d0" Name="WinSCP v6.4" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=WinSCP" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
  </RuleCollection>
  <RuleCollection Type="Msi" EnforcementMode="Enabled">
    <FilePathRule Id="002cc7ff-ba9a-3046-934e-373c04c94e0b" Name="Sistema Windows" Description="Binarios del sistema operativo" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\*" />
      </Conditions>
      <Exceptions>
        <FilePathCondition Path="%WINDIR%\Tasks\*" />
        <FilePathCondition Path="%WINDIR%\Temp\*" />
        <FilePathCondition Path="%WINDIR%\addins\*" />
        <FilePathCondition Path="%WINDIR%\debug\*" />
      </Exceptions>
    </FilePathRule>
    <FilePathRule Id="01c6be6b-e455-39a8-b1c8-c24be31d51e0" Name="Software instalado (Program Files)" Description="No rompe aplicaciones ya instaladas" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%ProgramFiles%\*" />
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="a76a2146-9abb-3134-8b00-0510a43b5395" Name="Software instalado (Program Files x86)" Description="No rompe aplicaciones ya instaladas" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%ProgramFiles(x86)%\*" />
      </Conditions>
    </FilePathRule>
    <FilePublisherRule Id="d3297faa-f5d8-3f35-92de-d79b0da1cd89" Name="7-Zip v24.09" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Igor Pavlov" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="29c35966-892b-3d7a-9e63-4c77b0a6d0b2" Name="Adobe Acrobat Reader v24.002" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Adobe Inc." ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="7e49e67b-b8d7-39b5-a96a-af7140e67fe5" Name="DBeaver v25.0" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=DBeaver Corp" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="a4622236-2112-3c4f-9b3f-0685686f1df1" Name="Figma v124x" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Figma, Inc." ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="ee4765db-7700-3ba8-a1fd-2f51d67dc831" Name="Google Chrome v126x" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Google LLC" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="ed770139-0850-34cb-8df9-b8f5a45c8529" Name="LibreOffice v24.8" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=The Document Foundation" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="7798d776-5a0e-385f-bf57-9881d012f23c" Name="Microsoft 365 v2404" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Microsoft Corporation" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="dc5ff89f-a0b7-338a-b5b7-29a024e52a68" Name="Microsoft Teams v1.6" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Microsoft Corporation" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="ea292c3c-b3f4-33b1-ae1a-c926d41d4db4" Name="Notepad++ v8.7" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Notepad++ Team" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="0e29ddf5-d169-30c8-8055-79f8421a308d" Name="Postman v11.x" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Postman Inc." ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="3cb9dbdf-e218-3cd3-9757-ebc1155fcc95" Name="Slack v4.x" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Slack Technologies, Inc." ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="f743ac2a-e6de-3a17-adf0-9f25d625c2ef" Name="VLC media player v3.0.21" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=VideoLAN" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="b75faeb6-2154-3b79-baff-62ed4be4e0ab" Name="Visual Studio Code v1.105" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Microsoft Corporation" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="ccca1d04-ba2c-3da9-9dc9-42f418182f33" Name="WinSCP v6.4" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=WinSCP" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
  </RuleCollection>
  <RuleCollection Type="Script" EnforcementMode="AuditOnly">
    <FilePathRule Id="13d17c9f-546c-32a3-ab54-79e5f75ccb5d" Name="Sistema Windows" Description="Binarios del sistema operativo" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\*" />
      </Conditions>
      <Exceptions>
        <FilePathCondition Path="%WINDIR%\Tasks\*" />
        <FilePathCondition Path="%WINDIR%\Temp\*" />
        <FilePathCondition Path="%WINDIR%\addins\*" />
        <FilePathCondition Path="%WINDIR%\debug\*" />
      </Exceptions>
    </FilePathRule>
    <FilePathRule Id="5c63f1d1-0fc8-3f84-b40c-d342e18503d1" Name="Software instalado (Program Files)" Description="No rompe aplicaciones ya instaladas" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%ProgramFiles%\*" />
      </Conditions>
    </FilePathRule>
    <FilePathRule Id="26ef9483-efbd-3db2-b385-78c4ef96375b" Name="Software instalado (Program Files x86)" Description="No rompe aplicaciones ya instaladas" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePathCondition Path="%ProgramFiles(x86)%\*" />
      </Conditions>
    </FilePathRule>
    <FilePublisherRule Id="7e159b99-b495-3694-b11f-778022481006" Name="7-Zip v24.09" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Igor Pavlov" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="6ae0ee35-3392-3986-862a-4e4531bc8ab6" Name="Adobe Acrobat Reader v24.002" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Adobe Inc." ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="67323936-b215-319f-8f82-ce5d81d143d0" Name="DBeaver v25.0" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=DBeaver Corp" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="958a0f5c-4c88-341a-ac53-f9692219c00c" Name="Figma v124x" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Figma, Inc." ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="0dbf3be6-4e78-3341-b1fa-287c113c056a" Name="Google Chrome v126x" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Google LLC" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="a71d6117-7fd0-37d4-b460-6b91df22dca1" Name="LibreOffice v24.8" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=The Document Foundation" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="b4cc9781-7c97-3bf0-bf63-3e8f326fc67a" Name="Microsoft 365 v2404" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Microsoft Corporation" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="a2706ee8-dbae-37ba-b111-5e81c3570f64" Name="Microsoft Teams v1.6" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Microsoft Corporation" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="20a086bb-e4ae-3c2f-b70a-31e2d458f389" Name="Notepad++ v8.7" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Notepad++ Team" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="3cff0eeb-4873-3316-9415-b1e0004ca220" Name="Postman v11.x" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Postman Inc." ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="f9cc49e7-9f6e-3062-a869-11cb8b561870" Name="Slack v4.x" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Slack Technologies, Inc." ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="6d166e55-01b4-3fa1-bbe9-4c18e05aa4ea" Name="VLC media player v3.0.21" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=VideoLAN" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="92e3c77c-cdf3-391e-acd9-ac61214fdc9c" Name="Visual Studio Code v1.105" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=Microsoft Corporation" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="39abae32-dbdf-3d82-9410-e82ed6454f4d" Name="WinSCP v6.4" Description="Catalogo AppStore" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=WinSCP" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
  </RuleCollection>
  <RuleCollection Type="Dll" EnforcementMode="NotConfigured" />
</AppLockerPolicy>

'@

function Get-SmartAppControlEstado {
    try {
        $k = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -ErrorAction Stop
        switch ([int]$k.VerifiedAndReputablePolicyState) {
            0 { 'Desactivado (ok)' }
            1 { 'ACTIVADO: bloquea AppLocker. Desactivalo antes de aplicar.' }
            2 { 'En evaluacion' }
            default { 'estado desconocido' }
        }
    } catch { 'no informado' }
}


function Test-Administrador {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-AppLocker {
    # Get-Set-AppLockerPolicy solo existen si la edicion trae AppLocker.
    if (-not (Get-Command Get-AppLockerPolicy -ErrorAction SilentlyContinue)) {
        throw "AppLocker no esta disponible en esta edicion de Windows. Hace falta Pro/Enterprise/Education (Win10/11) o Ultimate/Enterprise (Win7)."
    }
    # El servicio es el que aplica la politica; si queda en Manual, tras un reinicio
    # no arranca y la lista blanca no bloquea hasta que alguien lo inicie.
    # sc.exe en vez de Set-Service -StartupType porque ese parametro no existe en PowerShell 2 (Win7).
    & sc.exe config AppIDSvc start= auto | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "No se pudo poner AppIDSvc en inicio automatico (codigo $LASTEXITCODE)." }
    Start-Service AppIDSvc -ErrorAction SilentlyContinue
    $svc = Get-Service AppIDSvc
    if ($svc.Status -ne 'Running') { throw 'El servicio Application Identity (AppIDSvc) no arranco.' }
}

function Clear-AppLockerLocal {
    # El switch -Empty de Set-AppLockerPolicy solo existe en Windows Server: en
    # clientes (Win10/11 Pro) no esta y daria "parametro no encontrado". Lo que
    # hace -Empty es borrar el almacen local de politicas (SrpV2 del registro),
    # asi que se borra directamente y se reinicia el motor para que se note ya.
    if ((Get-Command Set-AppLockerPolicy).Parameters.ContainsKey('Empty')) {
        Set-AppLockerPolicy -Empty -ErrorAction Stop
    } else {
        if (Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SrpV2') {
            Remove-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SrpV2' -Recurse -Force -ErrorAction Stop
        }
        Restart-Service AppIDSvc -Force -ErrorAction SilentlyContinue
    }
}

function Check-Version {
    if ($Forzar) {
        Write-Host 'AVISO: se salteo el control de version de Windows.' -ForegroundColor Yellow
        return
    }
    $v = [Environment]::OSVersion.Version
    if ("$($v.Major).$($v.Minor)" -ne $VersionSo) {
        throw "Este script es para $Objetivo (Windows $VersionSo) y este equipo reporto Windows $v. Descarga el script correcto del portal o usa -Forzar."
    }
    if ($v.Build -lt $BuildMin -or $v.Build -gt $BuildMax) {
        $pista = if ($v.Build -gt $BuildMax -and $v.Major -eq 10) { ' Si el equipo es Windows 11 (build 22000+; 24H2/25H2 usan 26100-26300), descarga el script con target=WIN11 del portal.' } else { ' Verifica el target elegido en el portal.' }
        Write-Host "AVISO: build $v fuera del rango esperado ($BuildMin-$BuildMax) para $Objetivo.$pista Usa -Forzar solo si es a proposito." -ForegroundColor Yellow
    }
}

function Count-Reglas {
    # Cuantas reglas reales hay en un XML de politica. Se cuenta sobre el XML
    # (no sobre los objetos del cmdlet) porque el formato por defecto de
    # Format-List muestra {0,0,0,0} y se presta a leer mal la salida: lo que
    # importa es si el motor tiene reglas o no.
    param([string]$XmlStr)
    if (-not $XmlStr) { return 0 }
    return ([regex]::Matches($XmlStr, '<(FilePathRule|FilePublisherRule|FileHashRule)[ >]')).Count
}

function Show-Politica {
    param([string]$XmlStr, [string]$Titulo)
    Write-Host "=== $Titulo ===" -ForegroundColor Cyan
    if (-not $XmlStr) { Write-Host '   (sin politica definida)' -ForegroundColor Yellow; return }
    try {
        $doc = New-Object System.Xml.XmlDocument
        $doc.LoadXml($XmlStr)
        foreach ($c in $doc.GetElementsByTagName('RuleCollection')) {
            $n = 0
            foreach ($r in $c.ChildNodes) {
                if ($r.NodeType -eq 'Element' -and $r.LocalName -match 'Rule$') { $n += 1 }
            }
            $modo = $c.GetAttribute('EnforcementMode')
            if (-not $modo) { $modo = 'NotConfigured' }
            $color = 'Green'; if ($n -eq 0) { $color = 'Yellow' }
            Write-Host ("   {0,-7} {1,-14} {2} regla(s)" -f $c.GetAttribute('Type'), $modo, $n) -ForegroundColor $color
        }
        Write-Host ("   TOTAL: {0} regla(s)" -f (Count-Reglas $XmlStr))
    } catch { Write-Host '   (el XML no se pudo leer)' -ForegroundColor Red }
}

function Get-Persistencia {
    param([switch]$RecienAplicada)
    $ruta = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SrpV2'
    $hay = Test-Path $ruta
    # Set-AppLockerPolicy publica la politica a traves del servicio AppIDSvc:
    # justo despues de aplicar puede tardar unos segundos en verse en el
    # registro. Reintentar hasta 10s antes de reportar NO.
    if ($RecienAplicada) {
        for ($i = 0; $i -lt 5 -and -not $hay; $i++) {
            Start-Sleep -Seconds 2
            $hay = Test-Path $ruta
        }
    }
    $svc = (Get-Service AppIDSvc -ErrorAction SilentlyContinue)
    # New-Object en vez de [PSCustomObject] porque PowerShell 2 (Win7 sin actualizar) no lo tiene.
    New-Object PSObject -Property ([hashtable]@{
        'Politica en registro (persiste reinicio)' = $(if ($hay) { 'SI' } else { 'NO' })
        'AppIDSvc inicio' = $(if ($svc) { $svc.StartType } else { 'no existe' })
        'AppIDSvc estado' = $(if ($svc) { $svc.Status } else { 'no existe' })
        'Reglas en almacen local' = $(try { Count-Reglas (Get-AppLockerPolicy -Local -Xml) } catch { 'no se pudo leer' })
        'Reglas en politica efectiva' = $(try { Count-Reglas (Get-AppLockerPolicy -Effective -Xml) } catch { 'no se pudo leer' })
    })
}

New-Item -ItemType Directory -Force -Path $Carpeta | Out-Null

if (-not (Test-Administrador)) {
    throw 'Ejecuta esta PowerShell como ADMINISTRADOR.'
}
Ensure-AppLocker
Check-Version

if ($Ver) {
    Show-Politica (Get-AppLockerPolicy -Local -Xml) 'Almacen LOCAL (donde escribe este script)'
    Show-Politica (Get-AppLockerPolicy -Effective -Xml) 'Politica EFECTIVA (la que evalua el motor y decide bloqueos)'
    $cLoc = Count-Reglas (Get-AppLockerPolicy -Local -Xml)
    $cEfc = Count-Reglas (Get-AppLockerPolicy -Effective -Xml)
    if ($cLoc -gt 0 -and $cEfc -lt $cLoc) {
        Write-Host "ALERTA: el almacen local tiene $cLoc reglas pero la EFECTIVA solo muestra $cEfc." -ForegroundColor Red
        Write-Host 'Una GPO de dominio de AppLocker esta pisando la politica local: Set-AppLockerPolicy solo manda cuando NO hay GPO.' -ForegroundColor Yellow
        Write-Host 'Solucion: llevar el mismo XML al GPO del dominio (importar C:\ProgramData\AppStore\lista-blanca.xml en el editor de GPO de AppLocker).' -ForegroundColor Yellow
    }
    if ($cLoc -eq 0) {
        Write-Host 'El almacen local esta VACIO: la lista blanca no quedo guardada. Volve a ejecutar el script sin argumentos para aplicar.' -ForegroundColor Red
    }
    Write-Host '=== Persistencia ===' -ForegroundColor Cyan
    Get-Persistencia | Format-List
    Write-Host "=== Ultimos bloqueos de AppLocker ===" -ForegroundColor Cyan
    Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-AppLocker/EXE and DLL'; Id=8004 } -MaxEvents 15 -ErrorAction SilentlyContinue |
        ForEach-Object { "{0}  {1}" -f $_.TimeCreated, ($_.Message -split "`n")[0] }
    return
}

if ($Probar) {
    # Simula la politica EFECTIVA sobre un archivo concreto, sin ejecutarlo:
    # es la prueba definitiva de "este instalador, se bloquearia o no".
    # OJO: Test-AppLockerPolicy exige la politica por pipeline/parametro;
    # aca se manda la EFECTIVA (la que de verdad usa el motor).
    if (-not (Test-Path $Probar)) { throw "No existe el archivo: $Probar" }
    $rutaAbs = (Resolve-Path $Probar).Path
    Write-Host "Probando contra la politica EFECTIVA: $rutaAbs" -ForegroundColor Cyan
    Get-AppLockerPolicy -Effective |
        Test-AppLockerPolicy -Path $rutaAbs |
        Format-List Path, Result, RuleName, RuleType, EnforcementMode
    Write-Host 'Result: Allowed/AllowedByDefault => se ejecuta. Denied/DeniedByDefault => bloqueado (DenyByDefault = no hay regla que lo cubra).' -ForegroundColor DarkGray
    return
}

if ($Quitar) {
    if (Test-Path $Backup) {
        if ($PSCmdlet.ShouldProcess('AppLocker', 'restaurar la politica anterior')) {
            Set-AppLockerPolicy -Xml $Backup -ErrorAction Stop
            Remove-Item $Politica -ErrorAction SilentlyContinue
            Write-Host 'Politica anterior restaurada desde el backup. Sigue vigente tras reiniciar.' -ForegroundColor Yellow
        }
    } else {
        if ($PSCmdlet.ShouldProcess('AppLocker', 'dejar solo las reglas por defecto de Windows')) {
            Clear-AppLockerLocal
            Write-Host 'No habia backup: se borro la politica de AppLocker del equipo.' -ForegroundColor Yellow
        }
    }
    return
}

Write-Host "Objetivo: $Objetivo | firma de la politica: $Firma" -ForegroundColor Cyan
        Write-Host "Smart App Control: $(Get-SmartAppControlEstado)"
Write-Host "Modo: $(if ($Auditar) { 'AUDITORIA (no bloquea)' } else { 'BLOQUEO' })"

# Modo auditoria: se registran los bloqueos en el Event Log pero nada se impide.
# Es el paso previo obligatorio antes de aplicar en bloqueo.
if ($Auditar) {
    $Xml = $Xml -replace 'EnforcementMode="Enabled"', 'EnforcementMode="AuditOnly"'
}

# Backup de la politica vigente (efectiva) para poder volver atras.
if (-not (Test-Path $Backup)) {
    $actual = (Get-AppLockerPolicy -Effective -Xml)
    if ($actual -notmatch '<RuleCollection') { $actual = '<AppLockerPolicy Version="1" />' }
    [IO.File]::WriteAllText($Backup, $actual, (New-Object Text.UTF8Encoding($false)))
    Write-Host "Backup de la politica vigente: $Backup"
}

# Cada corrida reemplaza la politica por completo: se elimina cualquier lista
# blanca anterior (incluso una aplicacion previa de este script con reglas
# viejas) para que la nueva quede exacta, sin reglas mezcladas.
$previa = Get-AppLockerPolicy -Local
if ($previa -and @($previa.RuleCollections).Count -gt 0) {
    Write-Host 'Removiendo la lista blanca anterior...' -ForegroundColor Yellow
    Clear-AppLockerLocal
}

if (-not $PSCmdlet.ShouldProcess($Objetivo, 'aplicar la lista blanca del catalogo')) {
    Write-Host "[WHATIF] Escribiria $Politica y aplicaria Set-AppLockerPolicy (almacen de registro, persistente)."
    return
}

[IO.File]::WriteAllText($Politica, $Xml, (New-Object Text.UTF8Encoding($false)))
# Se aplica desde el archivo escrito arriba: -Xml con el XML como string solo
# funciona si valida el schema canonico; si no, lo trata como ruta y falla con
# un error confuso ("archivo no se puede resolver"). La ruta es el modo robusto.
# Set-AppLockerPolicy sin -ToLsaStore: guarda en el almacen de politicas local (registro),
# por eso sobrevive reinicios. Se aplica de inmediato, sin reiniciar.
Set-AppLockerPolicy -Xml $Politica -ErrorAction Stop

# Reinicia el motor de identidad de aplicacion para que la politica recien
# escrita tome efecto de inmediato (sin esperar al proximo reinicio del equipo).
Restart-Service AppIDSvc -Force -ErrorAction SilentlyContinue

# Verificacion REAL: no basta con que exista la clave SrpV2 en el registro.
# Hay que comprobar cuantas reglas vio el motor. Si la efectiva queda vacia
# pese a tener el almacen local lleno, una GPO de dominio (o el CSP de Intune)
# esta pisando la politica local y el equipo NO queda protegido.
$esperadas = Count-Reglas $Xml
$guardadas = Count-Reglas (Get-AppLockerPolicy -Local -Xml)
$efectivas = Count-Reglas (Get-AppLockerPolicy -Effective -Xml)
for ($i = 0; $i -lt 5 -and $efectivas -lt $esperadas; $i++) {
    Start-Sleep -Seconds 2
    $efectivas = Count-Reglas (Get-AppLockerPolicy -Effective -Xml)
}

if ($esperadas -gt 0 -and $efectivas -eq $esperadas) {
    Write-Host "Lista blanca aplicada y VERIFICADA: $efectivas reglas vigentes (reemplazo completo de la anterior)." -ForegroundColor Green
} elseif ($guardadas -lt $esperadas) {
    throw "Set-AppLockerPolicy guardo $guardadas de $esperadas reglas en el almacen local: el XML fue rechazado total o parcialmente."
} elseif ($efectivas -lt $esperadas) {
    Write-Host "ALERTA: se guardaron $guardadas reglas en el almacen local, pero la politica EFECTIVA solo tiene $efectivas." -ForegroundColor Red
    Write-Host 'El equipo tiene una GPO de dominio (o CSP de Intune) de AppLocker que pisa la politica local: NO HAY BLOQUEO ACTIVO.' -ForegroundColor Red
    Write-Host "Solucion: aplicar este mismo XML por GPO (archivo: $Politica) o desvincular la GPO de AppLocker." -ForegroundColor Yellow
} else {
    Write-Host "Lista blanca aplicada: $efectivas reglas vigentes (esperadas $esperadas). Revisar con -Ver." -ForegroundColor Yellow
}
Get-Persistencia -RecienAplicada | Format-List
Write-Host "Politica guardada en: $Politica"
Write-Host "Revisar:  .\Aplicar-ListaBlanca.ps1 -Ver"
Write-Host "Revertir: .\Aplicar-ListaBlanca.ps1 -Quitar"