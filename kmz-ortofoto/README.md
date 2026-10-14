# KMZ a DXF + ortofoto + curvas de nivel

Herramienta para Windows que convierte un KMZ/KML de Google Earth a DXF en coordenadas UTM (WGS84) y le agrega de fondo la **imagen satelital** y las **curvas de nivel** del área del proyecto más un margen.

## Descarga

**[KmzOrtofoto.zip](https://github.com/xjhona/herramientas/releases/download/kmz-ortofoto-v1.1/KmzOrtofoto.zip)**: incluye todo, no hace falta instalar Python.

1. Clic derecho al ZIP → *Propiedades* → marcar **Desbloquear** (si aparece).
2. Descomprimir en una carpeta fija, por ejemplo `C:\KmzOrtofoto`.
3. Doble clic en `instalar.bat`. La primera vez descarga Python y las librerías (requiere internet).

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

Requiere [uv](https://docs.astral.sh/uv/) (`winget install astral-sh.uv`); las dependencias de Python están declaradas en `kmzortofoto.py` y uv las instala solo. `empaquetar.bat` genera `dist\KmzOrtofoto.zip` con `uv.exe` incluido.

## Fuentes de datos

- Imagen: Esri World Imagery (Esri, Maxar, Earthstar Geographics y la comunidad de usuarios SIG).
- Elevación: Copernicus DEM GLO-30, © DLR e.V. 2010-2014 y © Airbus Defence and Space GmbH 2014-2018, provisto bajo COPERNICUS por la Unión Europea y la ESA.
- `uv.exe` (incluido en el ZIP): © Astral Software Inc., licencia MIT (`UV-LICENSE.txt`).
