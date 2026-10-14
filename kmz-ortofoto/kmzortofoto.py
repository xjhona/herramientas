# /// script
# requires-python = ">=3.10"
# dependencies = ["ezdxf", "pyproj", "rasterio", "pillow", "requests", "numpy", "contourpy"]
# ///
"""KMZ/KML -> DXF en UTM con imagen satelital (Esri World Imagery) de fondo y curvas de nivel
(Copernicus DEM GLO-30).

uso:
  uv run --script kmzortofoto.py archivo.kmz [otro.kml ...] [--epsg 32718] [--margen 25] [--zoom 0] [--curvas 1]
  uv run --script kmzortofoto.py plano.dxf --epsg 32717      (solo agrega imagen y curvas a un DXF existente)

Salida (junto al archivo de entrada):
  <nombre>.dxf               dibujo convertido (solo KMZ/KML)
  <nombre>_ortofoto.dxf      dibujo + imagen (capa ORTOFOTO, al fondo) + curvas (CURVAS_MENOR / CURVAS_MAYOR)
  <nombre>_ortofoto.jpg/.jgw/.prj
"""
import argparse
import hashlib
import io
import math
import os
import re
import sys
import xml.etree.ElementTree as ET
import zipfile
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

import ezdxf
import numpy as np
import pyproj
import rasterio
import requests
from contourpy import LineType, contour_generator
from ezdxf import bbox, colors
from PIL import Image
from pyproj import Transformer
from rasterio.crs import CRS
from rasterio.errors import RasterioIOError
from rasterio.transform import from_origin
from rasterio.warp import Resampling, reproject
from rasterio.windows import Window

TILE_URL = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
DEM_URL = "/vsicurl/https://copernicus-dem-30m.s3.amazonaws.com/{n}/{n}.tif"
R = 20037508.342789244  # semi-extensión Web Mercator
SESSION = requests.Session()
SESSION.headers["User-Agent"] = "KmzOrtofoto/1.0"


# =============================================================================
# KMZ/KML -> DXF
# =============================================================================
def _coords(el):
    out = []
    for tok in (el.findtext("coordinates") or "").split():
        p = [float(v) for v in tok.split(",")]
        out.append((p[0], p[1]))
    return out


def kml_root(path):
    if path.lower().endswith(".kmz"):
        with zipfile.ZipFile(path) as z:
            name = next(n for n in z.namelist() if n.lower().endswith(".kml"))
            root = ET.fromstring(z.read(name))
    else:
        root = ET.parse(path).getroot()
    for el in root.iter():  # quitar namespaces
        el.tag = el.tag.split("}", 1)[-1]
    return root


def kml_styles(root):
    """id de estilo -> (r, g, b) a partir de LineStyle/PolyStyle (KML usa aabbggrr)."""
    styles = {}
    for st in root.iter("Style"):
        c = st.findtext("LineStyle/color") or st.findtext("PolyStyle/color")
        if st.get("id") and c and len(c) == 8:
            styles["#" + st.get("id")] = (int(c[6:8], 16), int(c[4:6], 16), int(c[2:4], 16))
    for sm in root.iter("StyleMap"):
        for pair in sm.findall("Pair"):
            if pair.findtext("key") == "normal" and pair.findtext("styleUrl") in styles:
                styles["#" + sm.get("id")] = styles[pair.findtext("styleUrl")]
    return styles


def placemarks(el, folder):
    for ch in el:
        if ch.tag in ("Folder", "Document"):
            yield from placemarks(ch, ch.findtext("name") or folder)
        elif ch.tag == "Placemark":
            yield folder, ch


def utm_epsg(lon, lat):
    return (32700 if lat < 0 else 32600) + int((lon + 180) // 6) + 1


def kml_to_dxf(path, epsg=None):
    root = kml_root(path)
    styles = kml_styles(root)
    items = list(placemarks(root, "KML"))
    allc = [c for _, pm in items for g in pm.iter() if g.find("coordinates") is not None for c in _coords(g)]
    if not allc:
        raise ValueError("el KML no tiene geometrías")
    lon_c = sum(c[0] for c in allc) / len(allc)
    lat_c = sum(c[1] for c in allc) / len(allc)
    auto = utm_epsg(lon_c, lat_c)
    epsg = epsg or auto
    print(f"  Centro lon {lon_c:.5f} lat {lat_c:.5f} -> EPSG:{epsg}" + ("" if epsg == auto else f" (la zona real sería {auto})"))
    tf = Transformer.from_crs(4326, epsg, always_xy=True)

    doc = ezdxf.new("R2010", setup=True)
    doc.units = ezdxf.units.M
    msp = doc.modelspace()

    def layer(name):
        n = re.sub(r'[<>/\\":;?*|=`,]', "_", name).strip() or "KML"
        if n not in doc.layers:
            doc.layers.add(n)
        return n

    xy_all = [tf.transform(*c) for c in allc]
    span = max(max(p[0] for p in xy_all) - min(p[0] for p in xy_all),
               max(p[1] for p in xy_all) - min(p[1] for p in xy_all))
    txt_h = max(round(span / 250, 1), 0.5)

    stats = Counter()
    for folder, pm in items:
        attrs = {"layer": layer(folder)}
        rgb = styles.get(pm.findtext("styleUrl"))
        if rgb:
            attrs["true_color"] = colors.rgb2int(rgb)
        name = (pm.findtext("name") or "").strip()
        for g in pm.iter():
            if g.tag == "Point":
                for x, y in (tf.transform(*c) for c in _coords(g)):
                    msp.add_point((x, y), dxfattribs=attrs)
                    if name:
                        msp.add_text(name, height=txt_h, dxfattribs=attrs).set_placement((x + txt_h / 2, y + txt_h / 2))
                    stats["puntos"] += 1
            elif g.tag == "LineString":
                xy = [tf.transform(*c) for c in _coords(g)]
                if len(xy) >= 2:
                    msp.add_lwpolyline(xy, dxfattribs=attrs)
                    stats["líneas"] += 1
            elif g.tag == "LinearRing":
                xy = [tf.transform(*c) for c in _coords(g)]
                if len(xy) >= 3:
                    if xy[0] == xy[-1]:
                        xy = xy[:-1]
                    msp.add_lwpolyline(xy, close=True, dxfattribs=attrs)
                    stats["polígonos"] += 1

    out = os.path.splitext(path)[0] + ".dxf"
    doc.saveas(out)
    print(f"  {dict(stats)}  -> {os.path.basename(out)}")
    return out, epsg


# =============================================================================
# Imagen satelital
# =============================================================================
def tile_xy(lon, lat, z):
    n = 2**z
    return int((lon + 180) / 360 * n), int((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n)


def max_zoom(lon, lat):
    """Zoom más alto (19..15) cuyos tiles no son el relleno 'Map data not yet available'."""
    for z in range(19, 14, -1):
        x, y = tile_xy(lon, lat, z)
        hashes = {hashlib.md5(SESSION.get(TILE_URL.format(z=z, x=x + d, y=y + d), timeout=30).content).hexdigest()
                  for d in range(-1, 2)}
        if len(hashes) > 1:
            return z
    return 15


def fetch(zxy):
    z, x, y = zxy
    for _ in range(4):
        try:
            r = SESSION.get(TILE_URL.format(z=z, x=x, y=y), timeout=30)
            if r.status_code == 200:
                return zxy, r.content
        except requests.RequestException:
            pass
    return zxy, None


META_URL = "https://services.arcgisonline.com/arcgis/rest/services/World_Imagery/MapServer/{layer}/query"
SENSORS = {"WV01": "WorldView-1", "WV02": "WorldView-2", "WV03": "WorldView-3", "WV04": "WorldView-4",
           "GE01": "GeoEye-1", "QB02": "QuickBird-2", "IK02": "IKONOS",
           **{f"LG{i:02d}": f"WorldView Legion-{i}" for i in range(1, 7)}}


def ddmmyyyy(iso):
    """'2025-01-27' o '20250127' -> '27/01/2025'."""
    d = iso.replace("-", "")
    return f"{d[6:8]}/{d[4:6]}/{d[:4]}" if len(d) == 8 else "s/f"


def imagery_metadata(z, lon0, lat0, lon1, lat1):
    """Tomas (fecha, satélite, resolución, precisión) que forman la imagen Esri al zoom z en el área.
    Las capas de metadatos del servicio van por resolución: capa 11 = 1.2 m = zoom 17, etc."""
    try:
        r = SESSION.get(META_URL.format(layer=28 - z), timeout=30, params={
            "geometry": f"{lon0},{lat0},{lon1},{lat1}", "geometryType": "esriGeometryEnvelope", "inSR": 4326,
            "spatialRel": "esriSpatialRelIntersects", "returnGeometry": "false", "f": "json",
            "outFields": "SRC_DATE,SRC_DESC,SRC_RES,SRC_ACC,NICE_DESC,ReleaseName"})
        feats = [f["attributes"] for f in r.json().get("features", [])]
    except (requests.RequestException, ValueError, KeyError):
        return [], ""
    tomas = {}
    for a in feats:
        d = str(a.get("SRC_DATE") or "")
        sensor = SENSORS.get(a.get("SRC_DESC"), a.get("SRC_DESC") or "")
        tomas[(d, sensor)] = {"fecha": ddmmyyyy(d), "satelite": f"{a.get('NICE_DESC') or ''} {sensor}".strip(),
                              "res": a.get("SRC_RES"), "acc": a.get("SRC_ACC")}
    return [tomas[k] for k in sorted(tomas)], (feats[0].get("ReleaseName") or "" if feats else "")


# =============================================================================
# Curvas de nivel (Copernicus DEM GLO-30, alturas sobre el geoide EGM2008)
# =============================================================================
def dem_tile_name(lat, lon):
    """Nombre del tile de 1° cuya esquina SO es (floor(lat), floor(lon))."""
    la, lo = math.floor(lat), math.floor(lon)
    return (f"Copernicus_DSM_COG_10_{'N' if la >= 0 else 'S'}{abs(la):02d}_00_"
            f"{'E' if lo >= 0 else 'W'}{abs(lo):03d}_00_DEM")


def dem_metadata(tiles):
    """Periodo de las tomas TanDEM-X, edición y precisión vertical LE90 (del XML de cada tile)."""
    ini, fin, ed, le90 = [], [], [], []
    for name in tiles:
        xml_name = name.replace("_COG", "").removesuffix("_DEM") + ".xml"
        try:
            xml = SESSION.get(f"https://copernicus-dem-30m.s3.amazonaws.com/{name}/{xml_name}", timeout=30).text
        except requests.RequestException:
            continue
        ini += re.findall(r"<tsxx:tsxx_startTime>(\d{4}-\d\d-\d\d)", xml)
        fin += re.findall(r"<tsxx:tsxx_stopTime>(\d{4}-\d\d-\d\d)", xml)
        ed += re.findall(r"<gmd:editionDate>\s*<gco:Date>(\d{4}-\d\d-\d\d)", xml)
        le90 += [float(v) for v in re.findall(r"absolutePositionalAccuracyLE90[^>]*>([\d.]+)<", xml)]
    return {"desde": ddmmyyyy(min(ini)) if ini else "s/f", "hasta": ddmmyyyy(max(fin)) if fin else "s/f",
            "edicion": ddmmyyyy(max(ed)) if ed else "s/f", "le90": max(le90) if le90 else None}


def get_dem(epsg, xmin, ymin, xmax, ymax, res):
    """Grilla de elevaciones en UTM (origen xmin, ymax; paso res), NaN donde no hay datos,
    y lista de tiles Copernicus usados."""
    lons, lats = Transformer.from_crs(epsg, 4326, always_xy=True).transform(
        [xmin, xmax, xmin, xmax], [ymin, ymin, ymax, ymax])
    lo0, lo1 = min(lons) - 0.002, max(lons) + 0.002
    la0, la1 = min(lats) - 0.002, max(lats) + 0.002
    ncols, nrows = math.ceil((xmax - xmin) / res), math.ceil((ymax - ymin) / res)
    dem = np.full((nrows, ncols), np.nan, dtype=np.float32)
    tiles = []
    with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR"):
        for la in range(math.floor(la0), math.floor(la1) + 1):
            for lo in range(math.floor(lo0), math.floor(lo1) + 1):
                try:
                    src = rasterio.open(DEM_URL.format(n=dem_tile_name(la, lo)))
                except RasterioIOError:  # tile inexistente (mar)
                    continue
                tiles.append(dem_tile_name(la, lo))
                with src:
                    t = src.transform
                    c0 = max(int((lo0 - t.c) / t.a), 0)
                    c1 = min(int(math.ceil((lo1 - t.c) / t.a)), src.width)
                    r0 = max(int((la1 - t.f) / t.e), 0)
                    r1 = min(int(math.ceil((la0 - t.f) / t.e)), src.height)
                    if c1 <= c0 or r1 <= r0:
                        continue
                    win = Window(c0, r0, c1 - c0, r1 - r0)
                    tmp = np.full_like(dem, np.nan)
                    reproject(src.read(1, window=win), tmp, src_transform=src.window_transform(win),
                              src_crs=src.crs, dst_transform=from_origin(xmin, ymax, res, res),
                              dst_crs=CRS.from_epsg(epsg), resampling=Resampling.cubic, dst_nodata=np.nan)
                    dem = np.where(np.isnan(dem), tmp, dem)
    return dem, tiles


def smooth(z, sigma):
    """Suavizado gaussiano separable que ignora NaN (sigma en celdas)."""
    k = np.exp(-0.5 * (np.arange(-3 * sigma, 3 * sigma + 1) / sigma) ** 2)
    k /= k.sum()
    valid = ~np.isnan(z)
    num, den = np.where(valid, z, 0.0), valid.astype(float)
    for axis in (0, 1):
        num = np.apply_along_axis(np.convolve, axis, num, k, mode="same")
        den = np.apply_along_axis(np.convolve, axis, den, k, mode="same")
    with np.errstate(invalid="ignore"):
        return np.where(valid, num / den, np.nan)


def add_contours(doc, epsg, xmin, ymin, xmax, ymax, interval, major_every=5, res=5.0):
    """Agrega las curvas al DXF; devuelve un dict con datos para el reporte (None si no hay DEM)."""
    dem, tiles = get_dem(epsg, xmin, ymin, xmax, ymax, res)
    if np.isnan(dem).all():
        print("  AVISO: no hay datos de elevación para esta zona")
        return None
    # el DEM es de superficie (incluye árboles y casas): suavizar ~15 m quita ese ruido
    dem = smooth(dem, sigma=3)
    min_loop = 20 * res  # descartar curvas cerradas de menos de ~100 m de perímetro
    zmin, zmax = float(np.nanmin(dem)), float(np.nanmax(dem))
    xs = xmin + (np.arange(dem.shape[1]) + 0.5) * res
    ys = ymax - (np.arange(dem.shape[0]) + 0.5) * res
    gen = contour_generator(xs, ys[::-1], np.ma.masked_invalid(dem[::-1]), line_type=LineType.Separate)

    for name, color in (("CURVAS_MENOR", 33), ("CURVAS_MAYOR", 30)):
        if name not in doc.layers:
            doc.layers.add(name, color=color)
    msp = doc.modelspace()
    txt_h = max(round(max(xmax - xmin, ymax - ymin) / 400, 1), 0.5)
    n = 0
    for lvl in np.arange(math.ceil(zmin / interval) * interval, zmax, interval):
        lvl = round(float(lvl), 3)
        major = abs(lvl / (interval * major_every) - round(lvl / (interval * major_every))) < 1e-6
        layer = "CURVAS_MAYOR" if major else "CURVAS_MENOR"
        for line in gen.lines(lvl):
            if len(line) < 3:
                continue
            closed = bool(np.allclose(line[0], line[-1]))
            if closed and np.hypot(*np.diff(line, axis=0).T).sum() < min_loop:
                continue
            pts = line[:-1] if closed else line
            msp.add_lwpolyline(pts.tolist(), close=closed, dxfattribs={"layer": layer, "elevation": lvl})
            n += 1
            if major and len(pts) > 20:  # rótulo con la cota al medio de la curva
                i = len(pts) // 2
                (x0, y0), (x1, y1) = pts[i - 1], pts[i + 1]
                ang = math.degrees(math.atan2(y1 - y0, x1 - x0))
                if ang > 90 or ang < -90:
                    ang += 180
                msp.add_text(f"{lvl:g}", height=txt_h, rotation=ang, dxfattribs={"layer": layer}).set_placement(
                    tuple(pts[i]), align=ezdxf.enums.TextEntityAlignment.MIDDLE_CENTER)
    print(f"  Curvas cada {interval:g} m (maestras cada {interval*major_every:g} m): "
          f"{n} polilíneas, cotas {zmin:.0f}-{zmax:.0f} m")
    return {"intervalo": interval, "mayor": interval * major_every, "n": n, "zmin": zmin, "zmax": zmax,
            **dem_metadata(tiles)}


def fuentes_texto(nombre, epsg, xmin, ymin, xmax, ymax, z, px, tomas, release, curv):
    """Reporte de fuentes (txt) y nota corta para el plano."""
    L = [f"REPORTE DE FUENTES - {nombre}",
         f"Generado el {datetime.now():%d/%m/%Y %H:%M} con KmzOrtofoto",
         f"Área: E {xmin:.0f}-{xmax:.0f}  N {ymin:.0f}-{ymax:.0f}  ({pyproj.CRS.from_epsg(epsg).name}, EPSG:{epsg})",
         "",
         "IMAGEN SATELITAL",
         f"  Fuente:      Esri World Imagery{f' (edición {release})' if release else ''}",
         f"  Resolución:  {px} m/píxel (zoom {z})"]
    if tomas:
        L.append("  Tomas que forman la imagen:")
        for t in tomas:
            det = ", ".join(s for s in (f"res. original {t['res']:.2f} m" if t["res"] else "",
                                        f"precisión ±{t['acc']:g} m" if t["acc"] else "") if s)
            L.append(f"    - {t['fecha']}  {t['satelite']}" + (f"  ({det})" if det else ""))
    else:
        L.append("  Fecha de la imagen: no disponible (no se pudo consultar el servicio de metadatos)")
    nota = ["IMAGEN: Esri World Imagery" + (" - " + "; ".join(f"{t['satelite']} {t['fecha']}" for t in tomas) if tomas else "")]
    if curv:
        le90 = f"±{curv['le90']:.1f} m (LE90)" if curv["le90"] else "aprox. ±2-4 m"
        L += ["",
              "CURVAS DE NIVEL",
              "  Fuente:      Copernicus DEM GLO-30 (ESA / Airbus, misión TanDEM-X)",
              f"  Fecha del terreno: tomas del {curv['desde']} al {curv['hasta']}",
              f"  Edición del modelo: {curv['edicion']}",
              f"  Precisión vertical en la zona: {le90}",
              "  Alturas ortométricas sobre el geoide EGM2008 (aprox. nivel medio del mar)",
              f"  Curvas cada {curv['intervalo']:g} m, maestras cada {curv['mayor']:g} m; "
              f"cotas {curv['zmin']:.0f}-{curv['zmax']:.0f} m; DEM de 30 m suavizado ~15 m",
              "  Modelo de superficie (incluye árboles y edificaciones). No refleja movimientos de tierra",
              f"  posteriores a {curv['hasta'][-4:]}. No reemplaza un levantamiento topográfico."]
        nota.append(f"CURVAS: Copernicus DEM GLO-30 (TanDEM-X {curv['desde'][-4:]}-{curv['hasta'][-4:]}), "
                    f"precisión vertical {le90}, cada {curv['intervalo']:g} m")
    L += ["",
          "ATRIBUCIÓN",
          "  Imagen: Esri, Vantor (Maxar), Earthstar Geographics y la comunidad de usuarios SIG.",
          "  Elevación: produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence",
          "  and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved."]
    return "\n".join(L) + "\n", nota


def add_orthophoto(dxf_path, epsg, margin=0.25, zoom=0, curvas=1.0):
    doc = ezdxf.readfile(dxf_path)
    msp = doc.modelspace()
    ext = bbox.extents(e for e in msp if e.dxftype() != "IMAGE")
    if not ext.has_data:
        raise ValueError("el DXF está vacío")
    w, h = ext.size.x, ext.size.y
    xmin, ymin = ext.extmin.x - margin * w, ext.extmin.y - margin * h
    xmax, ymax = ext.extmax.x + margin * w, ext.extmax.y + margin * h

    lon, lat = Transformer.from_crs(epsg, 4326, always_xy=True).transform((xmin + xmax) / 2, (ymin + ymax) / 2)
    if not (-180 <= lon <= 180 and -85 <= lat <= 85):
        raise ValueError(f"las coordenadas no parecen estar en EPSG:{epsg}")
    z = zoom or max_zoom(lon, lat)
    px = round(2 * R / 256 / 2**z * math.cos(math.radians(lat)), 2)
    xmin, ymin = math.floor(xmin / px) * px, math.floor(ymin / px) * px
    ncols, nrows = math.ceil((xmax - xmin) / px), math.ceil((ymax - ymin) / px)
    xmax, ymax = xmin + ncols * px, ymin + nrows * px

    # bbox en Web Mercator (bordes densificados) -> rango de tiles
    t = np.linspace(0, 1, 50)
    ex = np.concatenate([xmin + t * (xmax - xmin), np.full(50, xmax), xmax - t * (xmax - xmin), np.full(50, xmin)])
    ey = np.concatenate([np.full(50, ymin), ymin + t * (ymax - ymin), np.full(50, ymax), ymax - t * (ymax - ymin)])
    mx, my = Transformer.from_crs(epsg, 3857, always_xy=True).transform(ex, ey)
    tsize = 2 * R / 2**z
    tx0, tx1 = int((min(mx) + R) // tsize), int((max(mx) + R) // tsize)
    ty0, ty1 = int((R - max(my)) // tsize), int((R - min(my)) // tsize)
    ntx, nty = tx1 - tx0 + 1, ty1 - ty0 + 1
    print(f"  Área {xmax-xmin:.0f} x {ymax-ymin:.0f} m, zoom {z} ({px} m/px), {ntx*nty} tiles...", flush=True)

    mosaic = np.zeros((nty * 256, ntx * 256, 3), dtype=np.uint8)
    missing = 0
    with ThreadPoolExecutor(8) as pool:
        for (_, x, y), data in pool.map(fetch, [(z, x, y) for y in range(ty0, ty1 + 1) for x in range(tx0, tx1 + 1)]):
            if data is None:
                missing += 1
                continue
            tile = np.asarray(Image.open(io.BytesIO(data)).convert("RGB").resize((256, 256)))
            mosaic[(y - ty0) * 256:(y - ty0 + 1) * 256, (x - tx0) * 256:(x - tx0 + 1) * 256] = tile
    if missing:
        print(f"  AVISO: {missing} tiles no se pudieron descargar (quedan en negro)")

    out = np.zeros((3, nrows, ncols), dtype=np.uint8)
    for b in range(3):
        reproject(mosaic[:, :, b], out[b],
                  src_transform=from_origin(-R + tx0 * tsize, R - ty0 * tsize, tsize / 256, tsize / 256),
                  src_crs=CRS.from_epsg(3857), dst_transform=from_origin(xmin, ymax, px, px),
                  dst_crs=CRS.from_epsg(epsg), resampling=Resampling.cubic)

    base = os.path.splitext(dxf_path)[0] + "_ortofoto"
    jpg = base + ".jpg"
    Image.fromarray(out.transpose(1, 2, 0)).save(jpg, quality=90)
    with open(base + ".jgw", "w") as f:  # world file (centro del píxel)
        f.write(f"{px}\n0\n0\n{-px}\n{xmin + px/2:.4f}\n{ymax - px/2:.4f}\n")
    with open(base + ".prj", "w") as f:
        f.write(CRS.from_epsg(epsg).to_wkt(version="WKT1_ESRI"))

    curv = add_contours(doc, epsg, xmin, ymin, xmax, ymax, curvas) if curvas > 0 else None

    # fuentes y fechas: reporte .txt + nota en el plano (capa FUENTES, bajo la imagen)
    lons, lats = Transformer.from_crs(epsg, 4326, always_xy=True).transform([xmin, xmax], [ymin, ymax])
    tomas, release = imagery_metadata(z, min(lons), min(lats), max(lons), max(lats))
    reporte, nota = fuentes_texto(os.path.basename(base), epsg, xmin, ymin, xmax, ymax, z, px, tomas, release, curv)
    with open(base + "_fuentes.txt", "w", encoding="utf-8-sig") as f:
        f.write(reporte)
    print("  Imagen: " + ("; ".join(f"{t['fecha']} {t['satelite']}" for t in tomas) if tomas else "fecha no disponible"))
    if curv:
        print(f"  Terreno (curvas): tomas {curv['desde']} - {curv['hasta']}, edición {curv['edicion']}")
    if "FUENTES" not in doc.layers:
        doc.layers.add("FUENTES", color=7)
    note_h = max(round(max(xmax - xmin, ymax - ymin) / 300, 1), 0.5)
    msp.add_mtext("\\P".join(nota), dxfattribs={"layer": "FUENTES", "char_height": note_h,
                                                 "width": xmax - xmin}).set_location(
        (xmin, ymin - note_h), attachment_point=ezdxf.enums.MTextEntityAlignment.TOP_LEFT)

    if "ORTOFOTO" not in doc.layers:
        doc.layers.add("ORTOFOTO", color=8)
    # ruta absoluta: el CAD la busca también en la carpeta del dibujo si no la encuentra
    idef = doc.add_image_def(filename=os.path.abspath(jpg), size_in_pixel=(ncols, nrows),
                             name=os.path.basename(base))
    image = msp.add_image(idef, insert=(xmin, ymin), size_in_units=(ncols * px, nrows * px),
                          dxfattribs={"layer": "ORTOFOTO"})
    order = {e.dxf.handle: e.dxf.handle for e in msp}
    order[image.dxf.handle] = "1"  # imagen al fondo
    msp.set_redraw_order(order)
    doc.saveas(base + ".dxf")
    print(f"  -> {os.path.basename(base)}.dxf + .jpg ({os.path.getsize(jpg)/1e6:.1f} MB) + _fuentes.txt")
    return base + ".dxf"


# =============================================================================
def ask_epsg(path):
    if not sys.stdin or not sys.stdin.isatty():
        raise ValueError("para un DXF hay que indicar --epsg")
    resp = input(f"  Zona UTM sur de {os.path.basename(path)} (17/18/19 o EPSG) [17]: ").strip() or "17"
    n = int(resp)
    return n if n > 1000 else 32700 + n


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("archivos", nargs="+", help=".kmz, .kml o .dxf")
    ap.add_argument("--epsg", type=int, help="EPSG de salida (por defecto: zona UTM automática para KMZ/KML)")
    ap.add_argument("--margen", type=float, default=25, help="margen alrededor del proyecto en %% (defecto 25)")
    ap.add_argument("--zoom", type=int, default=0, help="zoom de la imagen; 0 = el más alto disponible (defecto)")
    ap.add_argument("--curvas", type=float, default=1, help="intervalo de curvas de nivel en m; 0 = sin curvas (defecto 1)")
    ap.add_argument("--abrir", action="store_true", help="al terminar, mostrar el resultado en el Explorador")
    a = ap.parse_args()

    errores = 0
    hechos = []
    for path in a.archivos:
        print(f"\n{os.path.basename(path)}")
        try:
            ext = os.path.splitext(path)[1].lower()
            if ext in (".kmz", ".kml"):
                dxf, epsg = kml_to_dxf(path, a.epsg)
            elif ext == ".dxf":
                dxf, epsg = path, a.epsg or ask_epsg(path)
            else:
                raise ValueError("formato no soportado (usar .kmz, .kml o .dxf)")
            hechos.append(os.path.abspath(add_orthophoto(dxf, epsg, a.margen / 100, a.zoom, a.curvas)))
        except Exception as e:  # seguir con el resto de archivos
            errores += 1
            print(f"  ERROR: {e}")

    if hechos:
        print("\nGuardado en:")
        for h in hechos:
            print("  " + h)
        if a.abrir:
            import subprocess
            subprocess.Popen(f'explorer /select,"{hechos[-1]}"')
    sys.exit(1 if errores else 0)


if __name__ == "__main__":
    main()
