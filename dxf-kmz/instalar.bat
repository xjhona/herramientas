@echo off
rem Instala "DXF a KMZ" SIN permisos de administrador: copia los archivos a %LOCALAPPDATA%\DxfKmz
rem (carpeta del usuario) y crea el acceso en el menu Enviar a. Si se ejecuta desde esa carpeta solo crea el acceso.
chcp 65001 >nul
setlocal
set "DEST=%LOCALAPPDATA%\DxfKmz\"

if /i not "%~dp0"=="%DEST%" (
    echo Copiando archivos a %DEST% ...
    if not exist "%DEST%" mkdir "%DEST%"
    for %%F in (dxfkmz.exe dxfkmz.bat dxfkmz.lsp dxfkmz.py instalar.bat desinstalar.bat LEEME.txt UV-LICENSE.txt uv.exe) do (
        if exist "%~dp0%%F" copy /y "%~dp0%%F" "%DEST%" >nul
    )
)
if not exist "%DEST%dxfkmz.bat" (
    echo ERROR: no se pudieron copiar los archivos a %DEST%
    pause
    exit /b 1
)

rem Quitar la marca "descargado de internet" para que Windows no bloquee dxfkmz.exe; crear el acceso en Enviar a
powershell -NoProfile -Command ^
  "Get-ChildItem -LiteralPath '%DEST%' | Unblock-File -ErrorAction SilentlyContinue;" ^
  "$lnk = Join-Path ([Environment]::GetFolderPath('SendTo')) 'DXF a KMZ.lnk';" ^
  "$s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk);" ^
  "$s.TargetPath = '%DEST%dxfkmz.bat';" ^
  "$s.WorkingDirectory = '%DEST%';" ^
  "$s.IconLocation = '%SystemRoot%\System32\imageres.dll,186';" ^
  "$s.Save(); Write-Host ('Acceso creado: ' + $lnk)"

if not exist "%DEST%dxfkmz.exe" (
    echo Preparando Python y dependencias ^(solo la primera vez, requiere internet^)...
    call "%DEST%dxfkmz.bat" /nopausa --help >nul
    if errorlevel 1 echo ERROR preparando dependencias. Revisar la conexion a internet y que uv este instalado.
)

echo.
echo Listo. Instalado en %DEST%
echo  - Archivo suelto: clic derecho sobre un .dxf - Mostrar mas opciones - Enviar a - DXF a KMZ
echo  - BricsCAD / AutoCAD: APPLOAD, cargar "%DEST%dxfkmz.lsp" y escribir el comando DXFKMZ
echo.
if /i not "%~1"=="/nopausa" pause
