# AppLocker: lista blanca corregida

## Estado de pruebas

Los runners Windows Server 2022 x64, Windows Server 2025 x64 y Windows 11 Enterprise ARM64 superaron la bateria de **simulacion + aplicacion en auditoria** del flujo `AppLocker strict allowlist lab`. La bateria incluye WinRAR 7.23 REAL descargado desde la pagina oficial y colocado en la carpeta `Desktop` virtual: Test-AppLockerPolicy devuelve `DeniedByDefault`. Los resultados del bloqueo efectivo se documentan en el workflow independiente `AppLocker enforcement experiment`.

## Archivos

- `Aplicar-ListaBlanca-Corregida.ps1`: generador/aplicador para Windows con cinco colecciones de AppLocker.
- `lista-blanca.json`: catalogo de archivos y paquetes EXPLICITAMENTE aprobados. Viene vacio a proposito: no se pueden confiar hashes ni nombres de editor inventados para las 14 aplicaciones originales.
- `Test-Strict.ps1`: pruebas automatizadas de positivos, negativos y del instalador real de WinRAR.
- `Aplicar-ListaBlanca.original.ps1`: prueba historica, **NO USAR** en produccion.

## Uso desde PowerShell como administrador (primero en VM con snapshot)

```powershell
# Editar lista-blanca.json: poner cada exe, script, MSI y DLL real que se autoriza.
# Pueden ser rutas bajo Program Files; SE AUTORIZA CADA HASH, NO LA CARPETA.
.\Aplicar-ListaBlanca-Corregida.ps1 -Accion Generar
.\Aplicar-ListaBlanca-Corregida.ps1 -Accion Auditar -Confirm:$false
.\Aplicar-ListaBlanca-Corregida.ps1 -Accion Ver
.\Aplicar-ListaBlanca-Corregida.ps1 -Accion Probar -ArchivoPrueba "$env:USERPROFILE\Desktop\winrar-x64-723.exe"

# Tras probar todas las apps legitimas e instaladores y confirmar que no rompe Windows:
.\Aplicar-ListaBlanca-Corregida.ps1 -Accion Aplicar -Confirm:$false

# Restaurar politica local anterior si existen incidencias:
.\Aplicar-ListaBlanca-Corregida.ps1 -Accion Revertir -Confirm:$false

# Totalmente no mutante; valida/genera en memoria pero NO guarda ni aplica:
.\Aplicar-ListaBlanca-Corregida.ps1 -Accion Auditar -WhatIf
```

Ejemplo de `lista-blanca.json` con entradas que SOLO funcionan si los archivos existen en esa maquina:

```json
{
  "Files": [
    "C:\\Program Files\\7-Zip\\7zFM.exe",
    "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
    "C:\\Approved\\script-firmado-o-revisado.ps1",
    "C:\\Approved\\instalador-aprobado.msi"
  ],
  "PackagedApps": ["Microsoft.WindowsCalculator"]
}
```

Cada archivo aprobado se convierte a una regla FileHashRule por `Get-AppLockerFileInformation` + `New-AppLockerPolicy -RuleType Hash`, **no** a un SHA-256 convencional ni a una regla de carpeta. Actualizar un archivo cambia el hash: hay que editar/reaplicar la politica. Las aplicaciones con multiples EXE/DLL requieren incluir todas las dependencias ejecutables necesarias.

## Cambios concretos respecto al original

1. Eliminados los permisos globales `Program Files` y `Program Files (x86)` de las reglas EXE, MSI y Script.
2. Eliminadas las catorce reglas genericas `PublisherName=<editor>, ProductName=*, BinaryName=*` que permitian software no incluido.
3. Creada lista de aprobacion de archivos reales por hash nativo AppLocker, incluidos instaladores y scripts.
4. Colecciones `Exe`, `Msi`, `Script`, `Appx` y `Dll` con `Enabled` al aplicar, o `AuditOnly` al auditar.
5. Reglas sentinel para evitar la semantica *coleccion sin reglas = permitido todo*.
6. Appx solo por nombre exacto de paquete real y firma del paquete instalado; algunos paquetes esenciales de interfaz Windows se agregan por defecto para no bloquear completamente el escritorio.
7. No existe regla de bypass global para administradores, aunque un administrador local puede alterar o evadir controles al controlar la propia maquina.
8. `-WhatIf` protege TODOS los cambios: backup, escritura de XML, servicio y politica; no borra reglas por anticipado.
9. `Set-AppLockerPolicy -XmlPolicy` sin `-Merge` reemplaza atomicamente el almacen local; no necesita `Clear-AppLockerLocal` ni una ventana vacia.
10. Guarda backup local restaurable y compara IDs y modos de las cinco colecciones con la politica EFECTIVA; verifica `AppIDSvc` en Running antes de declarar el despliegue correcto.
11. Pruebas en tres sistemas Windows de archivos aprobados y no aprobados, WinRAR REAL, MSI, BAT, CMD, PS1, VBS y JS.

## Limites de seguridad IMPORTANTES

- **No es cumplimiento de 'solo se puede ejecutar codigo de una lista' de forma absoluta.** La base `%WINDIR%\*` permite utilidades del sistema (PowerShell, cmd, msiexec, etc.) y algunos directorios escribibles poco habituales podrian requerir exclusiones adicionales segun la imagen.
- Microsoft confirma que un `.ps1` bloqueado por AppLocker **puede ejecutarse en Constrained Language Mode**: `DeniedByDefault` NO implica que el archivo nunca empiece a ejecutarse. `powershell.exe -Command` y otros interpretes/herramientas integradas pueden ejecutar instrucciones aunque un archivo `.ps1` no este autorizado.
- AppLocker no cubre todos los tipos de interpretes, macros, WSL ni toda la carga de codigo dentro de procesos permitidos. Las ACL y quitar privilegios administradores son complementos imprescindibles.
- Habilitar reglas DLL exige incorporar tambien DLL legitimas de software permitido; puede romper aplicaciones. Probar y auditar con usuario **estandar** antes de produccion.
- Una politica de dominio/GPO/CSP puede prevalecer frente a la local; `Set-AppLockerPolicy` no escribe en el CSP de Intune.
- Para una garantia de integridad de codigo mas robusta y una estrategia de bloqueo real de interpretes, evaluar **App Control for Business (WDAC)** junto con restricciones especificas de PowerShell y privilegios. No se afirma que este script de AppLocker equivalga a WDAC.
- No activar directamente en PCs de usuarios: antes probar por etapas, instantanea/backup fuera de linea, cuenta de rescate y dispositivos de referencia.

Documentacion: https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/security-considerations-for-applocker
