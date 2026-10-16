# Laboratorio AppLocker en GitHub Actions

Este laboratorio analiza el script entregado por un tercero, no cambia los archivos de produccion del repositorio.

## Contenido

- Aplicar-ListaBlanca.original.ps1: copia del adjunto, con solo la direccion LAN en un comentario eliminada para no publicarla. La logica de la politica se conserva intacta.
- Test-AppLocker.ps1: comprueba sintaxis y XML, detecta permisos amplios, genera un ejecutable C# sin firma y lo prueba con Test-AppLockerPolicy en rutas TEMP y Program Files.
- reports/: evidencia producida en cada ejecucion, publicada como artifact y resumen de GitHub Actions.

## Modos

Con un push a esta rama el workflow ejecuta **audit** automaticamente en windows-2022, windows-2025 y windows-11-arm.

Despues de integrar el workflow a la rama principal se puede usar Actions > AppLocker Windows VM lab > Run workflow con los siguientes modos:

- static: no modifica politicas. Analiza y simula decisiones AppLocker.
- audit (por defecto): ejecuta el script con -Auditar y comprueba la politica efectiva.
- enforce: requiere seleccion manual, aplica el bloqueo real solo en un runner descartable. Puede bloquear herramientas del mismo runner e impedir recopilar artifacts. No usarlo en computadoras persistentes.

**Limitacion:** las imagenes windows-2022 y windows-2025 son Windows Server x64; windows-11-arm es Windows 11 Enterprise ARM64 real. No es Windows 11 x64: para validar reglas dependientes de arquitecturas x86-64, usar una VM Windows 11 x64 dedicada con instantanea.

Los resultados FAIL son intencionales cuando el script permite binarios fuera del catalogo. Una prueba roja indica una discrepancia de seguridad, no un fallo del programa winnfo.

El laboratorio no descarga scripts de una red privada ni instala software adicional ajeno a Windows.
