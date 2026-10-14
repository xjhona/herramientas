@echo off
rem Quita el acceso del menu Enviar a. Luego se puede borrar la carpeta.
del "%APPDATA%\Microsoft\Windows\SendTo\KMZ a DXF + ortofoto.lnk" 2>nul
echo Acceso "KMZ a DXF + ortofoto" eliminado del menu Enviar a.
echo Ya se puede borrar esta carpeta.
pause
