# KMZ a DXF + ortofoto + curvas de nivel

Herramienta para Windows que convierte un KMZ/KML de Google Earth a DXF en coordenadas UTM (WGS84) y le agrega de fondo la **imagen satelital** y las **curvas de nivel** del área del proyecto más un margen.

## Instalación

**Con un solo comando** (recomendado): abrir PowerShell, pegar y Enter.

```powershell
irm https://raw.githubusercontent.com/xjhona/herramientas/main/kmz-ortofoto/instalar.ps1 | iex
```

Descarga el paquete completo de la última versión, lo instala en `%LOCALAPPDATA%\KmzOrtofoto` y crea el acceso en *Enviar a*. Para actualizar, volver a ejecutar el mismo comando.

**Sin internet o a mano**: descargar el ZIP (por USB sirve igual), descomprimirlo en cualquier carpeta y doble clic en `instalar.bat`. El instalador copia todo a `%LOCALAPPDATA%\KmzOrtofoto`; después la carpeta descomprimida se puede borrar.

| Paquete | Tamaño | Instalación |
|---|---|---|
| **[KmzOrtofoto.zip](https://github.com/xjhona/herramientas/releases/download/kmz-ortofoto-v1.3/KmzOrtofoto.zip)** (completo) | ~80 MB | Segundos, **sin internet**: trae Python 3.12 y las librerías ya instaladas |
| [KmzOrtofoto-ligero.zip](https://github.com/xjhona/herramientas/releases/download/kmz-ortofoto-v1.3/KmzOrtofoto-ligero.zip) | ~18 MB | 3-5 minutos con internet: descarga Python y las librerías al instalar |

Si Windows muestra "Windows protegió su PC" al abrir `instalar.bat`: *Más información* → *Ejecutar de todas formas*, o antes de descomprimir: clic derecho al ZIP → *Propiedades* → **Desbloquear**.

La herramienta en sí siempre necesita internet al convertir (descarga la imagen y la elevación de la zona).

## Uso

Clic derecho sobre uno o varios `.kmz` / `.kml` → *Mostrar más opciones* → *Enviar a* → **KMZ a DXF + ortofoto**.
Al terminar se abre la carpeta con el resultado seleccionado.

Sobre un `.dxf` ya georreferenciado en UTM solo agrega imagen y curvas (pregunta la zona).

Desde consola:

```
kmzortofoto.bat archivo.kmz [--margen 25] [--epsg 32718] [--zoom 0] [--curvas 1]
```

`--curvas` es el intervalo en metros (maestras cada 5 intervalos, con cota); `--curvas 0` no genera curvas.

## Salida (junto al archivo de entrada)

| Archivo | Contenido |
|---|---|
| `<nombre>.dxf` | Dibujo convertido. Capa = carpeta del KMZ, color = estilo de línea |
| `<nombre>_ortofoto.dxf` | Dibujo + imagen en capa `ORTOFOTO` + curvas en `CURVAS_MENOR` / `CURVAS_MAYOR` (polilíneas con elevación) |
| `<nombre>_ortofoto.jpg` / `.jgw` / `.prj` | Imagen georreferenciada (sirve también en QGIS / Civil 3D) |
| `<nombre>_ortofoto_fuentes.txt` | Reporte: fecha y satélite de cada toma de la imagen, periodo de las tomas del terreno, precisión vertical en la zona y atribución. Un resumen queda también en el DXF (capa `FUENTES`, bajo la imagen) |

## Notas

- La zona UTM se detecta sola desde el KMZ (17S = 32717, 18S = 32718, 19S = 32719).
- El zoom se elige solo: el más alto en que Esri tiene imagen real (en la costa peruana suele ser 17, ~1.2 m/px).
- El DXF referencia la imagen, no la contiene: mantener el `.jpg` en la misma carpeta.
- Curvas: DEM de 30 m, precisión vertical ±2-4 m, alturas sobre el nivel medio del mar (EGM2008). Es un modelo de superficie (incluye árboles y edificaciones); se suaviza ~15 m. Sirve para ver la pendiente general en preventa, no reemplaza un levantamiento topográfico.

## Desarrollo

Requiere [uv](https://docs.astral.sh/uv/) (`winget install astral-sh.uv`); las dependencias de Python están declaradas en `kmzortofoto.py` y sus versiones exactas en `kmzortofoto.py.lock` (uv las respeta solo).

`empaquetar.bat` actualiza el lock y genera en `dist\`:

- `KmzOrtofoto.zip`: Python 3.12 portátil (de uv) con las librerías del lock instaladas, sin Tk ni pruebas. `kmzortofoto.bat` usa ese `python\python.exe` si existe; si no, usa uv.
- `KmzOrtofoto-ligero.zip`: con `uv.exe`, que descarga todo al instalar.

Para publicar: crear un release con tag `kmz-ortofoto-vX.Y` y subir los dos ZIP. `instalar.ps1` toma el release `kmz-ortofoto-*` más reciente que tenga `KmzOrtofoto.zip`.

## Fuentes de datos

- Imagen: Esri World Imagery (Esri, Maxar, Earthstar Geographics y la comunidad de usuarios SIG).
- Elevación: Copernicus DEM GLO-30, © DLR e.V. 2010-2014 y © Airbus Defence and Space GmbH 2014-2018, provisto bajo COPERNICUS por la Unión Europea y la ESA.
- `uv.exe` (incluido en el ZIP ligero): © Astral Software Inc., licencia MIT (`UV-LICENSE.txt`).
- Python (incluido en el ZIP completo): Python Software Foundation License (`python\LICENSE.txt`); cada librería trae su licencia en `python\Lib\site-packages\*.dist-info`.
