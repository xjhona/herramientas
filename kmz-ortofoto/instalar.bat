@echo off
rem Instala (o actualiza) "KMZ a DXF + ortofoto":
rem   1) copia esta carpeta a %LOCALAPPDATA%\KmzOrtofoto (asi no importa donde se descomprimio el ZIP)
rem   2) crea el acceso en el menu Enviar a
rem   3) comprueba Python y librerias (paquete completo: segundos; paquete ligero: los descarga)
rem Uso: instalar.bat [/nopausa]
chcp 65001 >nul
setlocal
set "SRC=%~dp0"
set "DEST=%LOCALAPPDATA%\KmzOrtofoto\"
set "PAUSA=1"
if /i "%~1"=="/nopausa" set "PAUSA="
set RC=0

if not exist "%SRC%kmzortofoto.py" (
    echo ERROR: falta kmzortofoto.py junto a este instalador.
    echo Primero descomprimir el ZIP completo en una carpeta y ejecutar instalar.bat desde ahi.
    set RC=1
    goto fin
)

rem ---- 1) copiar a la carpeta fija ----
if /i "%SRC%"=="%DEST%" goto acceso
echo Copiando a %DEST% ...
rem al actualizar, quitar el Python anterior para no mezclar versiones de librerias
if exist "%DEST%python" rd /s /q "%DEST%python"
robocopy "%SRC%." "%DEST%." /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 (
    echo ERROR copiando los archivos a %DEST%
    set RC=1
    goto fin
)

:acceso
rem ---- 2) acceso en Enviar a ----
powershell -NoProfile -Command ^
  "$lnk = Join-Path ([Environment]::GetFolderPath('SendTo')) 'KMZ a DXF + ortofoto.lnk';" ^
  "$s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk);" ^
  "$s.TargetPath = '%DEST%kmzortofoto.bat';" ^
  "$s.WorkingDirectory = '%DEST%';" ^
  "$s.IconLocation = '%SystemRoot%\System32\imageres.dll,186';" ^
  "$s.Save(); Write-Host ('Acceso creado: ' + $lnk)"

rem ---- 3) Python y librerias ----
if exist "%DEST%python\python.exe" (
    echo Comprobando Python y librerias incluidas...
) else (
    echo Descargando Python y librerias. Solo la primera vez: puede tardar 3 a 5 minutos.
    echo NO cerrar esta ventana aunque parezca detenida.
)
set "KMZ_PREPARAR=1"
call "%DEST%kmzortofoto.bat" /nopausa --help >nul
if errorlevel 1 (
    echo ERROR preparando Python y librerias. Revisar la conexion a internet y volver a ejecutar instalar.bat.
    set RC=1
    goto fin
)

echo.
echo Listo. Instalado en %DEST%
echo Uso: clic derecho sobre un .kmz - Mostrar mas opciones - Enviar a - KMZ a DXF + ortofoto
if /i not "%SRC%"=="%DEST%" echo La carpeta descomprimida ya no hace falta: se puede borrar.

:fin
echo.
if defined PAUSA pause
exit /b %RC%
