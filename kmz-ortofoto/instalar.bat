@echo off
rem Crea el acceso "KMZ a DXF + ortofoto" en el menu Enviar a y prepara las dependencias de Python.
chcp 65001 >nul
setlocal

powershell -NoProfile -Command ^
  "$lnk = Join-Path ([Environment]::GetFolderPath('SendTo')) 'KMZ a DXF + ortofoto.lnk';" ^
  "$s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk);" ^
  "$s.TargetPath = '%~dp0kmzortofoto.bat';" ^
  "$s.WorkingDirectory = '%~dp0';" ^
  "$s.IconLocation = '%SystemRoot%\System32\imageres.dll,186';" ^
  "$s.Save(); Write-Host ('Acceso creado: ' + $lnk)"

echo Preparando Python y dependencias (solo la primera vez, puede tardar unos minutos)...
call "%~dp0kmzortofoto.bat" /nopausa --help >nul
if errorlevel 1 (echo ERROR preparando dependencias. Revisar la conexion a internet.) else (
    echo Listo. Uso: clic derecho sobre un .kmz - Mostrar mas opciones - Enviar a - KMZ a DXF + ortofoto
)
echo.
if exist "%~dp0kmzortofoto.lsp" echo Para BricsCAD/AutoCAD: cargar "%~dp0kmzortofoto.lsp" con APPLOAD y usar el comando KMZORTO.
pause
