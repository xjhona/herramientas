@echo off
rem KMZ/KML -> DXF + imagen satelital.  Uso: kmzortofoto.bat [/nopausa] archivo.kmz [...] [--margen 25] [--epsg 32718]
chcp 65001 >nul
setlocal
rem guardar la carpeta antes de SHIFT (shift tambien desplaza %0)
set "HERE=%~dp0"

set "PAUSA=1"
set ARGS=
:args
if "%~1"=="" goto run
if /i "%~1"=="/nopausa" goto nopausa
set ARGS=%ARGS% "%~1"
shift
goto args
:nopausa
set "PAUSA="
shift
goto args

:run
rem uso interactivo (Enviar a): abrir el Explorador con el resultado seleccionado
set "ABRIR="
if defined PAUSA set "ABRIR=--abrir"

rem Paquete completo: Python portatil con las librerias ya instaladas (no usa uv ni descarga nada)
rem -E -s: ignorar PYTHONPATH/PYTHONHOME y paquetes del usuario que pudiera tener la PC
if not exist "%HERE%python\python.exe" goto conuv
"%HERE%python\python.exe" -E -s "%HERE%kmzortofoto.py" %ARGS% %ABRIR%
set RC=%ERRORLEVEL%
goto fin

:conuv
set "UV="
rem 1) uv.exe incluido en la carpeta (paquete ligero)  2) uv del PATH  3) uv instalado con winget
if exist "%HERE%uv.exe" set "UV=%HERE%uv.exe"
if not defined UV for /f "delims=" %%U in ('where uv 2^>nul') do if not defined UV set "UV=%%U"
if not defined UV for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\astral-sh.uv_*") do if exist "%%D\uv.exe" set "UV=%%D\uv.exe"
if not defined UV (
    echo No se encontro uv. Instalarlo con:  winget install astral-sh.uv
    set RC=1
    goto fin
)

rem KMZ_PREPARAR (lo define instalar.bat): mostrar el avance de la descarga de Python y librerias
set "QUIET=--quiet"
if defined KMZ_PREPARAR set "QUIET="
"%UV%" run %QUIET% --script "%HERE%kmzortofoto.py" %ARGS% %ABRIR%
set RC=%ERRORLEVEL%

:fin
if defined PAUSA (
    echo.
    pause
)
exit /b %RC%
