#!/usr/bin/env python3
"""Extract every sea mark from the mirrored S-57 tiles into site/data/sjomarken.geojson.

Why: in Skippo's tiles a topmark is its own point (layer TOPMAR) and a light is often its
own point (layer LIGHTS), each at exactly the same tile coordinate as the buoy or beacon it
belongs to. A MapLibre filter cannot join two features, so "buoys with a topmark" cannot be
expressed against the tiles. This script joins them once and writes the result:

    _L          source layer: BOYS, BEACONS, TOPMAR, LIGHTS or LIGHTHOUSES
    HJ_TOPMARK  the mark carries a topmark (for TOPMAR points: always true)
    HJ_TOPSHP   S-57 TOPSHP of that topmark, when known
    HJ_LIGHT    the mark carries a light (LIGHTS_TEXT, a LIGHTS point on it, or a lighthouse)
    HJ_WATER    the point lies in water: inside a depth/dredged/river/lake area of the chart
                and not inside a land area. Lighthouses on islets and leading-light beacons
                on shore are false. Needs shapely.
    HJ_MINZ     lowest tile zoom (9-14) whose tiles contain this point. Skippo thins marks
                out at low zoom; the style shows a point only from this zoom, as before.

All original properties are kept, so the chart style renders these points exactly like the
tile features. build_style.py points the mark layers at this file.

Uses the zoom-14 tiles (most precise). Needs mapbox-vector-tile:

    docker run --rm -v "$PWD":/w -w /w python:3.12-slim \
      sh -c 'pip -q install mapbox-vector-tile shapely && python build_marks.py'
"""
import json
import math
import os

Z = 14
TILES = f'site/tiles/s57/{Z}'
OUT = 'site/data/sjomarken.geojson'
MARKS = ('BOYS', 'BEACONS', 'LIGHTHOUSES')


def lonlat(x, y, tx, ty, ext, z=Z):
    # mapbox_vector_tile decodes with y pointing up from the tile's bottom edge
    n = 2 ** z
    X = (tx + x / ext) / n
    Y = (ty + 1 - y / ext) / n
    return round(X * 360 - 180, 7), round(math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * Y)))), 7)


def read_zoom(mvt, z, names):
    """(layer, lon, lat) of every point in the tiles of one zoom level."""
    out = []
    for d, _, files in os.walk(f'site/tiles/s57/{z}'):
        if not os.path.basename(d).isdigit():
            continue
        tx = int(os.path.basename(d))
        for f in files:
            tile = mvt.decode(open(os.path.join(d, f), 'rb').read())
            for name in names:
                layer = tile.get(name)
                for ft in (layer or {}).get('features', []):
                    if ft['geometry']['type'] == 'Point':
                        x, y = ft['geometry']['coordinates']
                        out.append((name, *lonlat(x, y, tx, int(f.split('.')[0]), layer['extent'], z)))
    return out


WATER_LAYERS = ('DEPARE', 'DRGARE', 'RIVERS', 'LAKARE')


def water_test(tile):
    """Return f(x, y) -> True when the tile point is in water and not on land."""
    from shapely.geometry import Point, shape
    from shapely.ops import unary_union

    def area(names):
        polys = [shape(ft['geometry']).buffer(0) for n in names for ft in tile.get(n, {}).get('features', [])
                 if ft['geometry']['type'] in ('Polygon', 'MultiPolygon')]
        return unary_union(polys) if polys else None
    water, land = area(WATER_LAYERS), area(('LNDARE_POLYGON',))
    return lambda x, y: bool(water is not None and water.covers(Point(x, y))
                             and not (land is not None and land.contains(Point(x, y))))


def main():
    import mapbox_vector_tile as mvt
    points = {}                 # (layer, lon, lat) -> props; dedupes tile-buffer copies
    in_water = {}               # (lon, lat) -> bool
    for d, _, files in os.walk(TILES):
        tx = int(os.path.basename(d)) if os.path.basename(d).isdigit() else None
        for f in files:
            if tx is None or not f.endswith('.mvt'):
                continue
            ty = int(f.split('.')[0])
            tile = mvt.decode(open(os.path.join(d, f), 'rb').read())
            is_water = water_test(tile)
            for name in MARKS + ('TOPMAR', 'LIGHTS'):
                layer = tile.get(name)
                if not layer:
                    continue
                ext = layer['extent']
                for ft in layer['features']:
                    if ft['geometry']['type'] != 'Point':
                        continue
                    x, y = ft['geometry']['coordinates']
                    if not (0 <= x < ext and 0 <= y < ext):
                        continue        # buffer copy; the neighbouring tile owns it
                    lon, lat = lonlat(x, y, tx, ty, ext)
                    points[(name, lon, lat)] = dict(ft['properties'])
                    in_water[(lon, lat)] = is_water(x, y)

    tops = {(lo, la): p.get('TOPSHP') for (n, lo, la), p in points.items() if n == 'TOPMAR'}
    lights = {(lo, la) for (n, lo, la) in points if n == 'LIGHTS'}
    marks = {(lo, la): p for (n, lo, la), p in points.items() if n in MARKS}

    # First zoom at which each point exists in Skippo's tile pyramid (positions at low zoom
    # are rounded to the tile grid, so match within a few grid cells).
    minz = {}
    for z in range(9, Z):
        tol = 4 * 360 / 2 ** z / 4096
        found = read_zoom(mvt, z, MARKS + ('TOPMAR', 'LIGHTS'))
        for key in points:
            if key in minz:
                continue
            name, lon, lat = key
            if any(n == name and abs(lo - lon) < tol and abs(la - lat) < tol / 2 for n, lo, la in found):
                minz[key] = z

    feats = []
    for (name, lon, lat), p in sorted(points.items()):
        pos = (lon, lat)
        if name == 'TOPMAR':
            host = marks.get(pos, {})
            has_top, shp = True, p.get('TOPSHP')
            has_light = pos in lights or bool(host.get('LIGHTS_TEXT'))
        elif name == 'LIGHTS':
            host = marks.get(pos, {})
            has_top, shp = pos in tops, tops.get(pos)
            has_light = True
        else:
            has_top, shp = pos in tops or p.get('HAS_TOPMARK') is True, tops.get(pos)
            has_light = name == 'LIGHTHOUSES' or pos in lights or bool(p.get('LIGHTS_TEXT'))
        props = {'_L': name, **p, 'HJ_TOPMARK': has_top, 'HJ_LIGHT': has_light,
                 'HJ_MINZ': minz.get((name, lon, lat), Z), 'HJ_WATER': in_water[pos]}
        if shp is not None:
            props['HJ_TOPSHP'] = shp
        feats.append({'type': 'Feature', 'geometry': {'type': 'Point', 'coordinates': [lon, lat]},
                      'properties': props})

    tmp = OUT + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as fh:
        json.dump({'type': 'FeatureCollection', 'features': feats}, fh, ensure_ascii=False,
                  separators=(',', ':'))
    os.replace(tmp, OUT)
    count = lambda pred: sum(1 for (lo, la), p in marks.items() if pred((lo, la), p))
    print(f'{len(feats)} points -> {OUT}: {len(marks)} marks, '
          f'{count(lambda k, p: k in tops)} with topmark, '
          f'{count(lambda k, p: k in lights or p.get("LIGHTS_TEXT"))} with light, '
          f'{len(lights - set(marks))} lights not on a mark, '
          f'{count(lambda k, p: not in_water[k])} marks on land')


if __name__ == '__main__':
    main()
