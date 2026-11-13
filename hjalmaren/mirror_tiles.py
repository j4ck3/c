#!/usr/bin/env python3
"""Speglar Skippos vektorkakel for Hjalmaren till site/tiles.

Kallor (oppna, ingen inloggning):
  S-57/sjokort   https://onlinemaps.skippo.cloud/20260706_s57/{z}/{x}/{y}.mvt
  OSM/baskarta   https://onlinemaps.skippo.cloud/osm_20260326/{z}/{x}/{y}.mvt

S-57-datat ar Sjofartsverkets sjoortdata som Skippo paketerat om till vektorkakel.
Datumbeteckningen (20260706) ar Skippos utgave och byts nar de slapper en ny karta.
OSM-kaklen behovs bara for zoom 0-8; fran 9,5 tar sjoortskiktet over.

Kor:  python3 mirror_tiles.py
"""
import math, os

BBOX = (15.15, 59.05, 16.55, 59.45)   # W, S, E, N med marginal
OUT = '/mnt/user/documents/compose/hjalmaren/site'
SOURCES = (
    ('s57', 'https://onlinemaps.skippo.cloud/20260706_s57', 4, 14),
    ('osm', 'https://onlinemaps.skippo.cloud/osm_20260326', 0, 8),
)


def xy(lon, lat, z):
    n = 2 ** z
    return (int((lon + 180) / 360 * n),
            int((1 - math.log(math.tan(math.radians(lat)) + 1 / math.cos(math.radians(lat))) / math.pi) / 2 * n))


def main():
    jobs = []
    w, s, e, nlat = BBOX
    for name, base, zmin, zmax in SOURCES:
        total = 0
        for z in range(zmin, zmax + 1):
            x0, y0 = xy(w, nlat, z)
            x1, y1 = xy(e, s, z)
            for x in range(x0, x1 + 1):
                for y in range(y0, y1 + 1):
                    path = f'{OUT}/tiles/{name}/{z}/{x}/{y}.mvt'
                    if not os.path.exists(path):
                        jobs.append((path, f'{base}/{z}/{x}/{y}.mvt'))
                    total += 1
        print(name, 'kakel', total)
    with open('/tmp/hj_mirror_jobs.txt', 'w') as fh:
        for path, url in jobs:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            fh.write(f'{path} {url}\n')
    print('att hamta', len(jobs))


if __name__ == '__main__':
    main()
