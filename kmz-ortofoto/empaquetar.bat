@echo off
rem Genera los dos paquetes para compartir, en dist\ :
rem   KmzOrtofoto.zip         COMPLETO: trae Python y las librerias ya instaladas.
rem                           Se instala en segundos y sin internet (recomendado).
rem   KmzOrtofoto-ligero.zip  trae solo uv.exe: descarga Python y librerias al instalar (unos minutos).
rem Uso: empaquetar.bat [/nopausa]
chcp 65001 >nul
setlocal
set "HERE=%~dp0"
set "PAUSA=1"
if /i "%~1"=="/nopausa" set "PAUSA="
set "PYVER=3.12"
rem tar de Windows (crea .zip); el tar de Git que pueda estar en el PATH no sirve
set "TAR=%SystemRoot%\System32\tar.exe"
set RC=0

set "UV="
if exist "%HERE%uv.exe" set "UV=%HERE%uv.exe"
if not defined UV for /f "delims=" %%U in ('where uv 2^>nul') do if not defined UV set "UV=%%U"
if not defined UV for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\astral-sh.uv_*") do if exist "%%D\uv.exe" set "UV=%%D\uv.exe"
if not defined UV (echo No se encontro uv.exe. Instalarlo con:  winget install astral-sh.uv & set RC=1 & goto fin)

if not exist "%HERE%dist" mkdir "%HERE%dist"
set "PKG=%TEMP%\KmzOrtofoto_pkg"
set "STAGE=%PKG%\KmzOrtofoto"

rem Fijar las versiones de las librerias (kmzortofoto.py.lock) para que todas las PC instalen lo mismo
"%UV%" lock --script "%HERE%kmzortofoto.py" --quiet
if errorlevel 1 (echo ERROR actualizando kmzortofoto.py.lock & set RC=1 & goto fin)

rem ===================== paquete COMPLETO (sin internet al instalar) =====================
echo [1/2] Paquete completo: Python %PYVER% portatil + librerias...
rd /s /q "%PKG%" 2>nul
mkdir "%STAGE%"
for %%F in (kmzortofoto.py kmzortofoto.bat instalar.bat desinstalar.bat LEEME.txt) do copy /y "%HERE%%%F" "%STAGE%\" >nul

"%UV%" python install %PYVER% --install-dir "%PKG%\_py" --no-bin --quiet
if errorlevel 1 (echo ERROR descargando Python %PYVER% & set RC=1 & goto fin)
rem uv crea cpython-3.12.N-... (carpeta real) y cpython-3.12-... (enlace): mover solo la real
for /d %%D in ("%PKG%\_py\cpython-%PYVER%.*-windows-x86_64-none") do move "%%D" "%STAGE%\python" >nul
rd /s /q "%PKG%\_py" 2>nul
if not exist "%STAGE%\python\python.exe" (echo ERROR: no se encontro el Python descargado & set RC=1 & goto fin)

"%UV%" export --script "%HERE%kmzortofoto.py" --format requirements-txt --no-hashes --quiet -o "%PKG%\requisitos.txt"
if errorlevel 1 (echo ERROR exportando las versiones de las librerias & set RC=1 & goto fin)
"%UV%" pip install --quiet --python "%STAGE%\python\python.exe" --break-system-packages -r "%PKG%\requisitos.txt"
if errorlevel 1 (echo ERROR instalando las librerias & set RC=1 & goto fin)

rem Quitar lo que la herramienta no usa (interfaz Tk, cabeceras de compilacion, pruebas)
for %%D in (tcl include libs Lib\idlelib Lib\tkinter Lib\turtledemo Lib\ensurepip Lib\test Lib\site-packages\pip) do if exist "%STAGE%\python\%%D" rd /s /q "%STAGE%\python\%%D"
for %%F in (_tkinter.pyd tcl86t.dll tk86t.dll) do if exist "%STAGE%\python\DLLs\%%F" del /q "%STAGE%\python\DLLs\%%F"
for /d /r "%STAGE%\python\Lib\site-packages" %%D in (tests) do if exist "%%D" rd /s /q "%%D"

rem Comprobar que el paquete funciona solo (sin uv ni internet)
"%STAGE%\python\python.exe" -E -s "%STAGE%\kmzortofoto.py" --help >nul
if errorlevel 1 (echo ERROR: el Python del paquete no arranca & set RC=1 & goto fin)

del "%HERE%dist\KmzOrtofoto.zip" 2>nul
"%TAR%" -a -c -f "%HERE%dist\KmzOrtofoto.zip" -C "%PKG%" KmzOrtofoto
if errorlevel 1 (echo ERROR creando el ZIP & set RC=1 & goto fin)

rem ===================== paquete LIGERO (descarga al instalar) =====================
echo [2/2] Paquete ligero: solo uv.exe...
rd /s /q "%PKG%" 2>nul
mkdir "%STAGE%"
for %%F in (kmzortofoto.py kmzortofoto.py.lock kmzortofoto.bat instalar.bat desinstalar.bat LEEME.txt UV-LICENSE.txt) do copy /y "%HERE%%%F" "%STAGE%\" >nul
copy /y "%UV%" "%STAGE%\uv.exe" >nul
del "%HERE%dist\KmzOrtofoto-ligero.zip" 2>nul
"%TAR%" -a -c -f "%HERE%dist\KmzOrtofoto-ligero.zip" -C "%PKG%" KmzOrtofoto
if errorlevel 1 (echo ERROR creando el ZIP ligero & set RC=1 & goto fin)
rd /s /q "%PKG%"

echo.
for %%Z in ("%HERE%dist\KmzOrtofoto.zip" "%HERE%dist\KmzOrtofoto-ligero.zip") do echo Paquete creado: %%~fZ  (%%~zZ bytes)

:fin
if defined PAUSA pause
exit /b %RC%
