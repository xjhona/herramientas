@echo off
rem Quita el acceso "DXF a KMZ" del menu Enviar a. La carpeta %LOCALAPPDATA%\DxfKmz se puede borrar a mano.
powershell -NoProfile -Command "Remove-Item (Join-Path ([Environment]::GetFolderPath('SendTo')) 'DXF a KMZ.lnk') -ErrorAction SilentlyContinue; Write-Host 'Acceso eliminado.'"
echo La carpeta %LOCALAPPDATA%\DxfKmz se puede borrar a mano.
pause
