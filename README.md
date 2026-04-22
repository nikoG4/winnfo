# Windows Hardware Usage Inspector

Aplicacion WPF en C#/.NET 8 para inspeccionar notebooks/PC usadas, consolidar datos reales de hardware/Windows y estimar nivel de uso, estado general y confianza del diagnostico.

## Estado de esta version

Primera version funcional y compilable. Incluye:

- Solucion modular con `Inspector.Core`, `Inspector.Infrastructure`, `Inspector.App` y `Inspector.Tests`.
- UI WPF por pestanas: Dashboard, Sistema, CPU/RAM/GPU, Almacenamiento, Bateria, Historial, Red/dispositivos y Diagnostico.
- Resaltado visual de filas/celdas que aportan señales de uso, antiguedad, salud o riesgo.
- Interfaz internacionalizada con recursos ES/EN segun cultura del sistema.
- CLI de diagnostico para ejecutar la misma recoleccion sin abrir WPF.
- Icono de aplicacion propio.
- Publicacion self-contained e instalador PowerShell. Incluye script Inno Setup ES/EN.
- Collectors reales con estrategia por capas y fallos no fatales.
- Scoring configurable por JSON.
- Exportacion JSON completa y HTML legible.
- Integracion opcional con `smartctl`.
- Parser inicial de `powercfg /batteryreport`.
- Lectura de sensores via LibreHardwareMonitor cuando el equipo lo permite.

## Arquitectura

```text
/src
  /Inspector.Core
    /Models        Modelos de dominio, valores con fuente y issues
    /Interfaces    Contratos de collectors, orchestrator, scoring y export
    /Services      Orquestacion de inspeccion
    /Scoring       Motor de scoring ponderado
    /Reporting     Exportadores JSON/HTML
  /Inspector.Infrastructure
    /Wmi           Helpers WMI
    /Registry      Lectura de registro Windows
    /EventLogs     Implementado dentro de collectors de uso
    /ExternalTools smartctl y ejecucion de procesos
    /Sensors       LibreHardwareMonitor
    /Parsers       Battery report
  /Inspector.App
    /ViewModels    MVVM ligero
    /Resources     scoring-settings.json
  /Inspector.Cli   Ejecucion headless para depuracion/export JSON
/tests
  /Inspector.Tests
```

La capa Core no depende de WMI, registro, EventLog ni WPF. La infraestructura implementa collectors concretos detras de `IInspectorCollector`. La app usa inyeccion de dependencias con `Microsoft.Extensions.DependencyInjection`.

## Fuentes implementadas

- WMI/CIM: identidad, BIOS, motherboard, Windows, CPU, RAM, GPU, discos, bateria basica, red y dispositivos con error.
- Registro: modo UEFI/Legacy cuando Windows expone `PEFirmwareType`.
- Event Viewer: arranques, apagados, apagados inesperados, suspension y reanudacion en log `System`.
- `powercfg /batteryreport`: genera HTML temporal y parsea fabricante, quimica, capacidades y ciclos si estan disponibles.
- `smartctl`: si existe en `PATH` o en `tools/smartctl.exe`, consulta `/dev/physicaldriveN` con salida JSON.
- LibreHardwareMonitor: temperatura/carga CPU y GPU si los sensores estan expuestos.

## Scoring

El archivo editable esta en:

```text
src/Inspector.App/Resources/scoring-settings.json
```

Senales iniciales:

- Horas de disco encendido.
- Escritura total SSD/NVMe.
- Salud SMART.
- Ciclos de bateria.
- Desgaste de bateria.
- Frecuencia de eventos de sistema.
- Antiguedad de instalacion de Windows como senal debil.

Si una senal falta, el score recalcula con los pesos disponibles. Si no hay bateria, se adapta automaticamente para desktop.

Reglas de inconsistencia incluidas:

- Firmware antiguo con disco de muy pocas horas: posible reemplazo de SSD/HDD.
- Salud SMART baja.
- Desgaste de bateria alto.
- Muchos apagados inesperados.

## Como ejecutar

Este repositorio incluye un SDK .NET 8 portable descargado durante el armado en `.dotnet/` para poder compilar aunque el sistema solo tenga SDK 7. Si ya tenes SDK 8 global, podes usar `dotnet` normal.

```powershell
.\.dotnet\dotnet.exe build WindowsHardwareUsageInspector.sln
.\.dotnet\dotnet.exe test WindowsHardwareUsageInspector.sln
.\.dotnet\dotnet.exe run --project .\src\Inspector.App\Inspector.App.csproj
.\.dotnet\dotnet.exe run --project .\src\Inspector.Cli\Inspector.Cli.csproj -- .\debug-report.json
.\scripts\publish.ps1
.\scripts\install-winnfo.ps1
```

Con SDK 8 global:

```powershell
dotnet build WindowsHardwareUsageInspector.sln
dotnet test WindowsHardwareUsageInspector.sln
dotnet run --project .\src\Inspector.App\Inspector.App.csproj
dotnet run --project .\src\Inspector.Cli\Inspector.Cli.csproj -- .\debug-report.json
```

## Instalador

Instalacion directa con PowerShell:

```powershell
.\scripts\publish.ps1
.\scripts\install-winnfo.ps1
```

El instalador copia la app self-contained a `Program Files`, crea acceso directo en el escritorio e instala `smartctl` si no existe.

Tambien se incluye un script de Inno Setup internacionalizado:

```text
installer/winnfo.iss
```

Para generar el instalador `.exe`, instalar Inno Setup y ejecutar:

```powershell
ISCC.exe .\installer\winnfo.iss
```

En este entorno `ISCC.exe` no estaba disponible, por eso se valido el publish self-contained y el instalador PowerShell.

## smartctl

Para SMART/NVMe detallado instalar smartmontools y dejar `smartctl.exe` en el `PATH`, o copiarlo a:

```text
src/Inspector.App/bin/Debug/net8.0-windows/tools/smartctl.exe
```

Sin `smartctl`, la app sigue funcionando y marca SMART como no disponible.

Tambien se incluye un instalador asistido:

```powershell
.\scripts\install-smartctl.ps1
```

La aplicacion busca `smartctl.exe` en `PATH`, en carpetas `tools` de la app y en `C:\Program Files\smartmontools\bin`.

En algunos equipos Windows puede exponer tipo/bus/salud general con `Get-PhysicalDisk`, pero negar horas de uso con `Get-StorageReliabilityCounter` si la sesion no tiene permisos o el driver no publica esos contadores. En ese caso la app muestra el disco, bus, media y unidades, pero deja `PowerOnHours` como `N/D` con una nota explicita.

## Permisos y limitaciones

- Algunas lecturas de SMART, sensores, TPM o Secure Boot pueden requerir permisos elevados o depender del fabricante.
- WMI puede ocultar seriales o datos de RAM segun BIOS/OEM.
- El `batteryreport` no siempre incluye cycle count.
- La fecha de instalacion de Windows es una senal debil porque se reinicia con reinstalaciones.
- LibreHardwareMonitor puede no exponer sensores si el hardware/driver no lo permite.

## Ejemplo de salida esperada

Dashboard:

```text
Uso estimado: 24.8 - Low
Estado general: 91.5 - Excellent
Confianza: Medium
Resumen: Uso estimado Low con estado general Excellent.
```

Fragmento JSON:

```json
{
  "identity": {
    "manufacturer": { "value": "LENOVO", "source": "WMI Win32_ComputerSystem" },
    "model": { "value": "20XWCTO1WW", "source": "WMI Win32_ComputerSystem" }
  },
  "storageDevices": [
    {
      "model": "NVMe SSD",
      "smart": {
        "available": true,
        "source": "smartctl",
        "powerOnHours": 420,
        "powerCycles": 190,
        "healthPercent": 99
      }
    }
  ],
  "diagnostic": {
    "usageLevel": "Low",
    "conditionLevel": "Excellent",
    "confidence": "Medium"
  }
}
```

## Roadmap

- Mejorar correlacion disco-particion-volumen con MSFT_Disk/MSFT_PhysicalDisk.
- Parser mas robusto de battery report para historiales por periodo.
- Exportacion PDF.
- Firma de binarios y modo portable empaquetado.
- Mas reglas de consistencia por edad de CPU, BIOS y modelo comercial.
- Opcion CLI para generar reportes sin abrir UI.
