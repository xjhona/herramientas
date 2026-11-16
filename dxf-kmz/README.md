# DXF a KMZ (Google Earth)

Herramienta para Windows que convierte un DXF en coordenadas UTM (metros) a un KMZ para Google Earth. Es la inversa de [KmzOrtofoto](../kmz-ortofoto/).

## Instalación

No necesita Python, internet ni **permisos de administrador**: se instala en la carpeta del usuario (`%LOCALAPPDATA%\DxfKmz`), así que funciona en laptops corporativas.

| Paquete | Tamaño | Instalación |
|---|---|---|
| **[DxfKmz.zip](https://github.com/xjhona/herramientas/releases/download/dxf-kmz-v1.0/DxfKmz.zip)** (portable, recomendado) | ~40 MB | Descomprimir en cualquier carpeta y doble clic en `instalar.bat`. Segundos |
| [DxfKmz-Setup.exe](https://github.com/xjhona/herramientas/releases/download/dxf-kmz-v1.0/DxfKmz-Setup.exe) | ~40 MB | Doble clic. En PCs corporativas Windows puede pedir administrador al abrir un "Setup.exe": en ese caso usar el ZIP |

**Con un solo comando** (PowerShell, descarga el ZIP de la última versión e instala):

```powershell
irm https://raw.githubusercontent.com/xjhona/herramientas/main/dxf-kmz/instalar.ps1 | iex
```

Si Windows muestra "Windows protegió su PC": *Más información* → *Ejecutar de todas formas*, o antes de descomprimir: clic derecho al ZIP → *Propiedades* → **Desbloquear**. El instalador además desbloquea los archivos copiados.

Para quitarlo: `desinstalar.bat` (borra el acceso de *Enviar a*) y borrar la carpeta `%LOCALAPPDATA%\DxfKmz`.

## Uso

**Archivo suelto**: clic derecho sobre uno o varios `.dxf` → *Mostrar más opciones* → *Enviar a* → **DXF a KMZ**. Pregunta la zona UTM (17, 18, 19 sur; 18N norte; o código EPSG) y recuerda la última usada.

**BricsCAD / AutoCAD**: `APPLOAD` → cargar `%LOCALAPPDATA%\DxfKmz\dxfkmz.lsp` → comando `DXFKMZ` → seleccionar objetos (Enter = todo el dibujo) → zona. El KMZ queda junto al DWG como `<dibujo>_GE.kmz`. Solo exporta lo visible: capas apagadas o congeladas no salen. El `.lsp` busca la herramienta en `%LOCALAPPDATA%\DxfKmz` y, si no está, en `C:\DxfKmz` (instalaciones antiguas).

**Consola**:

```
dxfkmz.bat archivo.dxf [--epsg 18] [--excluir CAPA ...] [--relleno] [-o salida.kmz]
```

## Qué se convierte

- `LINE`, `LWPOLYLINE`, `POLYLINE`, `ARC`, `CIRCLE`, `ELLIPSE`, `SPLINE` → líneas (cerradas = polígonos sin relleno)
- `POINT` e `INSERT` (bloques) → punto con el nombre del bloque
- `TEXT`, `MTEXT` → etiqueta
- Una carpeta de Google Earth por capa; color = color del objeto (o de su capa).
- No se convierten `HATCH`, cotas ni imágenes (se informa cuántos se omitieron). La capa `FUENTES` de KmzOrtofoto no se exporta.

## Empaquetar y publicar

`empaquetar.bat` genera en `dist\` el `DxfKmz.zip` y el `DxfKmz-Setup.exe` (con IExpress, que viene con Windows). Necesita `dxfkmz.exe` en esta carpeta; si no está, lo toma de una instalación existente. `dxfkmz.exe` y `dist\` no se suben al repo: se publican como release.

Para publicar: crear un release con tag `dxf-kmz-vX.Y` y subir los dos archivos. `instalar.ps1` toma el release `dxf-kmz-*` más reciente que tenga `DxfKmz.zip`.

> El código fuente de `dxfkmz.exe` (`dxfkmz.py`) no está en este repo todavía; `dxfkmz.bat` lo usa con uv si no encuentra el `.exe`.
