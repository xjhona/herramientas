@echo off
rem Genera los paquetes para compartir, en dist\ :
rem   DxfKmz.zip        PORTABLE (recomendado, sirve en PCs corporativas): descomprimir y doble clic en
rem                     instalar.bat. Instala en %LOCALAPPDATA%\DxfKmz, sin permisos de administrador.
rem   DxfKmz-Setup.exe  instalador de un archivo hecho con IExpress (viene con Windows). Hace lo mismo que
rem                     instalar.bat, pero Windows puede pedir administrador al abrir un "Setup.exe".
rem Necesita dxfkmz.exe en esta carpeta; si no esta, lo toma de una instalacion existente.
rem Uso: empaquetar.bat [/nopausa]
chcp 65001 >nul
setlocal
set "HERE=%~dp0"
set "PAUSA=1"
if /i "%~1"=="/nopausa" set "PAUSA="
set RC=0

for %%D in ("%LOCALAPPDATA%\DxfKmz" "C:\DxfKmz") do if not exist "%HERE%dxfkmz.exe" if exist "%%~D\dxfkmz.exe" copy /y "%%~D\dxfkmz.exe" "%HERE%" >nul
if not exist "%HERE%dxfkmz.exe" (echo ERROR: falta dxfkmz.exe en %HERE% & set RC=1 & goto fin)

set "PKG=%TEMP%\DxfKmz_pkg"
set "STAGE=%PKG%\DxfKmz"
set "SED=%TEMP%\DxfKmz_pkg.sed"
set "OUT=%HERE%dist\DxfKmz-Setup.exe"
set "TAR=%SystemRoot%\System32\tar.exe"
rd /s /q "%PKG%" 2>nul
mkdir "%STAGE%"
if not exist "%HERE%dist" mkdir "%HERE%dist"
for %%F in (dxfkmz.exe dxfkmz.bat dxfkmz.lsp instalar.bat desinstalar.bat LEEME.txt) do copy /y "%HERE%%%F" "%STAGE%\" >nul

rem ===================== ZIP portable =====================
echo [1/2] DxfKmz.zip (portable)...
del "%HERE%dist\DxfKmz.zip" 2>nul
"%TAR%" -a -c -f "%HERE%dist\DxfKmz.zip" -C "%PKG%" DxfKmz
if errorlevel 1 (echo ERROR creando el ZIP & set RC=1 & goto fin)

rem ===================== Setup.exe (IExpress) =====================
echo [2/2] DxfKmz-Setup.exe...

> "%SED%" echo [Version]
>>"%SED%" echo Class=IEXPRESS
>>"%SED%" echo SEDVersion=3
>>"%SED%" echo [Options]
>>"%SED%" echo PackagePurpose=InstallApp
>>"%SED%" echo ShowInstallProgramWindow=0
>>"%SED%" echo HideExtractAnimation=1
>>"%SED%" echo UseLongFileName=1
>>"%SED%" echo InsideCompressed=0
>>"%SED%" echo CAB_FixedSize=0
>>"%SED%" echo CAB_ResvCodeSigning=0
>>"%SED%" echo RebootMode=N
>>"%SED%" echo InstallPrompt=%%InstallPrompt%%
>>"%SED%" echo DisplayLicense=%%DisplayLicense%%
>>"%SED%" echo FinishMessage=%%FinishMessage%%
>>"%SED%" echo TargetName=%%TargetName%%
>>"%SED%" echo FriendlyName=%%FriendlyName%%
>>"%SED%" echo AppLaunched=%%AppLaunched%%
>>"%SED%" echo PostInstallCmd=%%PostInstallCmd%%
>>"%SED%" echo AdminQuietInstCmd=%%AdminQuietInstCmd%%
>>"%SED%" echo UserQuietInstCmd=%%UserQuietInstCmd%%
>>"%SED%" echo SourceFiles=SourceFiles
>>"%SED%" echo [Strings]
>>"%SED%" echo InstallPrompt=
>>"%SED%" echo DisplayLicense=
>>"%SED%" echo FinishMessage=
>>"%SED%" echo TargetName=%OUT%
>>"%SED%" echo FriendlyName=DXF a KMZ
>>"%SED%" echo AppLaunched=cmd /c instalar.bat
>>"%SED%" echo PostInstallCmd=^<None^>
>>"%SED%" echo AdminQuietInstCmd=
>>"%SED%" echo UserQuietInstCmd=
>>"%SED%" echo FILE0="dxfkmz.exe"
>>"%SED%" echo FILE1="dxfkmz.bat"
>>"%SED%" echo FILE2="dxfkmz.lsp"
>>"%SED%" echo FILE3="instalar.bat"
>>"%SED%" echo FILE4="desinstalar.bat"
>>"%SED%" echo FILE5="LEEME.txt"
>>"%SED%" echo [SourceFiles]
>>"%SED%" echo SourceFiles0=%STAGE%\
>>"%SED%" echo [SourceFiles0]
>>"%SED%" echo %%FILE0%%=
>>"%SED%" echo %%FILE1%%=
>>"%SED%" echo %%FILE2%%=
>>"%SED%" echo %%FILE3%%=
>>"%SED%" echo %%FILE4%%=
>>"%SED%" echo %%FILE5%%=

del "%OUT%" 2>nul
rem Lanzado directamente desde cmd, IExpress vuelve antes de terminar; con Start-Process -Wait si espera
powershell -NoProfile -Command "Start-Process -FilePath ($env:SystemRoot + '\System32\iexpress.exe') -ArgumentList '/N','/Q','%SED%' -Wait"
if not exist "%OUT%" (echo ERROR: IExpress no genero el instalador & set RC=1 & goto fin)
rd /s /q "%PKG%" 2>nul
del "%SED%" 2>nul

echo.
for %%Z in ("%HERE%dist\DxfKmz.zip" "%OUT%") do echo Paquete creado: %%~fZ  (%%~zZ bytes)

:fin
if defined PAUSA pause
exit /b %RC%
