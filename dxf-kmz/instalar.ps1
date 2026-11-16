# Instala o actualiza "DXF a KMZ" con un solo comando (pegar en PowerShell):
#
#   irm https://raw.githubusercontent.com/xjhona/herramientas/main/dxf-kmz/instalar.ps1 | iex
#
# Descarga el paquete portable de la ultima version publicada (no necesita Python ni administrador),
# lo instala en %LOCALAPPDATA%\DxfKmz y crea el acceso en el menu Enviar a.
# Archivo solo en ASCII: PowerShell 5.1 puede leer mal los acentos al usar irm | iex.

& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'   # la barra de progreso hace muy lenta la descarga en PowerShell 5.1
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $repo = 'xjhona/herramientas'
    $zipName = 'DxfKmz.zip'

    Write-Host 'Buscando la ultima version de DXF a KMZ...'
    $releases = Invoke-RestMethod "https://api.github.com/repos/$repo/releases?per_page=50" -UseBasicParsing
    $rel = $releases |
        Where-Object { $_.tag_name -like 'dxf-kmz-*' -and -not $_.draft -and -not $_.prerelease -and ($_.assets.name -contains $zipName) } |
        Select-Object -First 1
    if (-not $rel) { throw "No se encontro ningun release dxf-kmz con $zipName en github.com/$repo" }
    $asset = $rel.assets | Where-Object { $_.name -eq $zipName } | Select-Object -First 1

    $tmp = Join-Path $env:TEMP ('DxfKmz_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $zip = Join-Path $tmp $zipName
        Write-Host ('Descargando {0} ({1:N0} MB)...' -f $rel.tag_name, ($asset.size / 1MB))
        Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing

        Write-Host 'Descomprimiendo...'
        $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
        if (Test-Path $tar) {
            & $tar -x -f $zip -C $tmp
            if ($LASTEXITCODE -ne 0) { throw 'Error descomprimiendo el paquete' }
        } else {
            Expand-Archive -Path $zip -DestinationPath $tmp -Force
        }

        $instalador = Join-Path $tmp 'DxfKmz\instalar.bat'
        if (-not (Test-Path $instalador)) { throw 'El paquete descargado no trae instalar.bat' }
        & cmd.exe /c "`"$instalador`" /nopausa"
        if ($LASTEXITCODE -ne 0) { throw 'La instalacion termino con errores (ver mensajes arriba)' }
    }
    finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
