@echo off
rem Genera dist\KmzOrtofoto.zip para compartir (incluye uv.exe: el destinatario no necesita instalar nada).
chcp 65001 >nul
setlocal
set "HERE=%~dp0"
set "UV="
for /f "delims=" %%U in ('where uv 2^>nul') do if not defined UV set "UV=%%U"
if not defined UV for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\astral-sh.uv_*") do if exist "%%D\uv.exe" set "UV=%%D\uv.exe"
if not defined UV (echo No se encontro uv.exe & pause & exit /b 1)

set "STAGE=%TEMP%\KmzOrtofoto_pkg\KmzOrtofoto"
rd /s /q "%TEMP%\KmzOrtofoto_pkg" 2>nul
mkdir "%STAGE%"
for %%F in (kmzortofoto.py kmzortofoto.bat instalar.bat desinstalar.bat LEEME.txt UV-LICENSE.txt) do copy /y "%HERE%%%F" "%STAGE%\" >nul
copy /y "%UV%" "%STAGE%\uv.exe" >nul

if not exist "%HERE%dist" mkdir "%HERE%dist"
del "%HERE%dist\KmzOrtofoto.zip" 2>nul
powershell -NoProfile -Command "Compress-Archive -Path '%TEMP%\KmzOrtofoto_pkg\KmzOrtofoto' -DestinationPath '%HERE%dist\KmzOrtofoto.zip'"
rd /s /q "%TEMP%\KmzOrtofoto_pkg"
echo Paquete creado: %HERE%dist\KmzOrtofoto.zip
pause
