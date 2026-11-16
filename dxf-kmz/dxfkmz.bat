@echo off
rem DXF -> KMZ (Google Earth).  Uso: dxfkmz.bat [/nopausa] archivo.dxf [...] [--epsg 18] [--excluir CAPA ...] [--relleno]
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
set "ABRIR="
if defined PAUSA set "ABRIR=--abrir"
rem version compilada (dxfkmz.exe): no necesita Python ni uv
if exist "%HERE%dxfkmz.exe" (
    "%HERE%dxfkmz.exe" %ARGS% %ABRIR%
    set RC=%ERRORLEVEL%
    goto fin
)

set "UV="
rem 1) uv.exe incluido en la carpeta  2) uv del PATH  3) uv instalado con winget
if exist "%HERE%uv.exe" set "UV=%HERE%uv.exe"
if not defined UV for /f "delims=" %%U in ('where uv 2^>nul') do if not defined UV set "UV=%%U"
if not defined UV for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\astral-sh.uv_*") do if exist "%%D\uv.exe" set "UV=%%D\uv.exe"
if not defined UV (
    echo No se encontro uv. Instalarlo con:  winget install astral-sh.uv
    set RC=1
    goto fin
)

"%UV%" run --quiet --script "%HERE%dxfkmz.py" %ARGS% %ABRIR%
set RC=%ERRORLEVEL%

:fin
if defined PAUSA (
    echo.
    pause
)
exit /b %RC%
