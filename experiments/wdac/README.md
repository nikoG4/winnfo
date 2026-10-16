# Laboratorio WDAC - lista blanca Windows

**Aviso: no instalar en computadoras de trabajo antes de usar una VM con snapshot, auditar aplicaciones y tener un plan de recuperacion.**

Se usa App Control for Business (WDAC), no AppLocker. Es una politica BASE en formato de varias politicas; genera DOS binarios CIP de igual PolicyID (audit/enforce). El generador por defecto NUNCA instala politicas.

## Archivos

- Build-Wdac.ps1: compila XML y CIP de audit y enforce sin modificar Code Integrity.
- allowlist.json: rutas exactas de archivos y nombres de paquetes aprobados (inicialmente vacio).
- Manage-Wdac.ps1: acciones separadas Audit, Enforce, Remove, Status y Events.
- Test-Wdac.ps1: pruebas de ConfigCI y eventos del sistema en GitHub-hosted Windows.

## Uso de PowerShell 5.1 elevado

1. Editar allowlist.json en Windows destino: incluir EXE y DLL de cada software externo permitido, scripts y MSI que ConfigCI soporte, junto con dependencias reales. Ninguna ruta con *.
2. Ejecutar: .\Build-Wdac.ps1
3. Ejecutar: .\Manage-Wdac.ps1 -Action Audit -IUnderstandRisks -Confirm:$false
4. Ver auditoria: .\Manage-Wdac.ps1 -Action Events (3076: habria bloqueado; 8028: script/MSI auditado).
5. DESPUES de validar en VM con snapshot y sin alertas imprevistas: .\Manage-Wdac.ps1 -Action Enforce -IUnderstandRisks -AuditReviewed -Confirm:$false
6. Revisar status y eventos reales 3077. Para restaurar: .\Manage-Wdac.ps1 -Action Remove -Confirm:$false. En algunas versiones es necesario reiniciar para aplicar/remover.

Ejemplo de allowlist.json: Files array con C:\Program Files\7-Zip\7zFM.exe, C:\Program Files\7-Zip\7z.dll, C:\Aprobados\instalador.exe, Packages array vacio. El ejemplo NO se debe copiar como si esos archivos existieran: cada ruta se valida en la maquina.

## Alcance y limites

El template oficial DefaultWindows_Audit.xml permite componentes centrales de Windows, drivers y ciertas aplicaciones empaquetadas; NO cumple el sentido literal 'solo mis 14 archivos'. Se usa para no impedir que Windows arranque. Terceros no reciben permisos amplios por carpeta/editor: se generan reglas de hash ConfigCI individualmente.

El control WDAC de MSI y scripts requiere que el host respete WDAC. Microsoft indica que scripts PowerShell no autorizados pueden ejecutarse bajo Constrained Language Mode y que ciertos hosts no integran el control. No equivale a denegar todas las instrucciones script. Para seguridad fuerte, limitar interpretes, macros, PowerShell, herramientas integradas y privilegios de administrador, y examinar reglas de bloqueo recomendadas de Microsoft.

Un ejecutable MSI aprobado no autoriza automaticamente todos los EXE/DLL que el instalador despliegue. Actualizar archivos obliga revisar/regenerar hashes, distribuir las reglas y repetir auditoria. No usar rutas amplias de instaladores o Program Files.

Las politicas audit y enforce comparten PolicyID, pero binarios ubicados en subcarpetas distintas (audit o enforce) con nombre GUID.cip. Nunca instalar ambos simultaneamente. En Windows 11 22H2+ y Server 2025+ se puede usar CiTool para administrarlas.

## Cambios desde AppLocker

1. Se reemplaza Set-AppLockerPolicy y AppIDSvc por XML SiPolicy, ConvertFrom-CIPolicy y CiTool.
2. UMCI activo y opcion Script Enforcement deshabilitada eliminada.
3. Auditoria opcion 3 separada de bloqueo.
4. Sin AllowAll, sin confianza automatica por reputacion ISG, sin Managed Installer.
5. Confianza esencial del sistema operativo conservada por DefaultWindows en lugar de una carpeta Program Files abierta.
6. Hashes propios de ConfigCI para programas concretos y no hashes del instalador considerados equivalentes a su carga.
7. Generacion que no modifica sistema y despliegue explicito con flags de riesgo y recuperacion por PolicyID.

Referencias oficiales:
- https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/design/example-appcontrol-base-policies
- https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/design/script-enforcement
- https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/design/select-types-of-rules-to-create
- https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/operations/citool-commands
