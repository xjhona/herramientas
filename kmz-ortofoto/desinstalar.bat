@echo off
rem Quita el acceso del menu Enviar a y, si se confirma, borra la carpeta instalada.
chcp 65001 >nul
setlocal
set "DEST=%LOCALAPPDATA%\KmzOrtofoto"
del "%APPDATA%\Microsoft\Windows\SendTo\KMZ a DXF + ortofoto.lnk" 2>nul
echo Acceso "KMZ a DXF + ortofoto" eliminado del menu Enviar a.
if not exist "%DEST%\kmzortofoto.py" goto fin
choice /c SN /m "Borrar tambien la carpeta %DEST%"
if errorlevel 2 goto fin
rem todo en una linea: este .bat esta dentro de la carpeta que se borra
cd /d "%TEMP%" & rd /s /q "%DEST%" & echo Carpeta borrada. & pause & exit /b 0

:fin
pause
