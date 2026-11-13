#!/usr/bin/env python3
"""Hamtar Sjomarken, stenar och djupkurvor for Hjalmaren fran Skippos vektorkakel.

Skippos planerare (https://www.skippo.se/plan) ritar S-57-data som Mapbox
vektortiles. Kaklen ar oppna och ligger pa onlinemaps.skippo.cloud. Skriptet
laddar ner de kakel som tacker Hjalmaren, plockar ut lager for stenar (UWTROC),
djupkurvor (DEPCNT) och bojar/prickar/fyrar (BOYS, BEACONS, LIGHTS) och skriver
tre filer till site/data/.

Kor:  python3 fetch_skipper.py [--out site/data] [--cache .cache_skipper]
Bara stdlib + curl behovs (Unraids python3 saknar ssl-modul darfor curl).
"""
import argparse
import collections
import json
import math
import os
import subprocess
import sys

BASE = "https://onlinemaps.skippo.cloud"
DATASET = "20260706_s57"
ZOOMS = (12, 13, 14)
# Fallback om ingen sjo-polygon finns: Hjalmarens ungefarliga utbredning.
BBOX = (15.246, 59.123, 16.439, 59.339)  # W, S, E, N

# ---------------------------------------------------------------- MVT-lasare


def _varint(buf, pos):
    result = 0
    shift = 0
    while True:
        b = buf[pos]
        pos += 1
        result |= (b & 0x7F) << shift
        if not b & 0x80:
            return result, pos
        shift += 7


def _zigzag(n):
    return (n >> 1) ^ (-(n & 1))


def _fields(buf):
    pos = 0
    n = len(buf)
    while pos < n:
        key, pos = _varint(buf, pos)
        fnum, wtype = key >> 3, key & 7
        if wtype == 0:
            val, pos = _varint(buf, pos)
        elif wtype == 1:
            import struct
            val = struct.unpack_from("<d", buf, pos)[0]
            pos += 8
        elif wtype == 2:
            ln, pos = _varint(buf, pos)
            val = buf[pos:pos + ln]
            pos += ln
        elif wtype == 5:
            import struct
            val = struct.unpack_from("<f", buf, pos)[0]
            pos += 4
        else:
            raise ValueError("wire type %d" % wtype)
        yield fnum, wtype, val


def _packed_ints(buf):
    out, pos = [], 0
    while pos < len(buf):
        v, pos = _varint(buf, pos)
        out.append(v)
    return out


def _value(raw):
    for fnum, _wt, val in _fields(raw):
        if fnum == 1:
            return val.decode("utf-8", "replace")
        if fnum in (2, 3, 5):
            return val
        if fnum == 4:
            return val - 2 ** 64 if val >= 2 ** 63 else val
        if fnum == 6:
            return _zigzag(val)
        if fnum == 7:
            return bool(val)
    return None


def _geometry(geom):
    i = 0
    x = y = 0
    rings, cur = [], []
    while i < len(geom):
        cmdint = geom[i]
        i += 1
        cmd, count = cmdint & 7, cmdint >> 3
        if cmd in (1, 2):
            for _ in range(count):
                x += _zigzag(geom[i])
                y += _zigzag(geom[i + 1])
                i += 2
                if cmd == 1:
                    if cur:
                        rings.append(cur)
                    cur = [(x, y)]
                else:
                    cur.append((x, y))
        elif cmd == 7:
            if cur:
                cur.append(cur[0])
                rings.append(cur)
                cur = []
        else:
            raise ValueError("cmd %d" % cmd)
    if cur:
        rings.append(cur)
    return rings


def read_tile(data, z, tx, ty):
    out = {}
    n = 2 ** z
    for fnum, _wt, raw in _fields(data):
        if fnum != 3:
            continue
        name = None
        keys, vals, feats, extent = [], [], [], 4096
        for lf, _lwt, lraw in _fields(raw):
            if lf == 1:
                name = lraw.decode("utf-8")
            elif lf == 2:
                feats.append(lraw)
            elif lf == 3:
                keys.append(lraw.decode("utf-8"))
            elif lf == 4:
                vals.append(_value(lraw))
            elif lf == 5:
                extent = lraw
        layer = []
        for fb in feats:
            tags, gtype, geom = [], 0, []
            for ff, _fw, fr in _fields(fb):
                if ff == 2:
                    tags = _packed_ints(fr)
                elif ff == 3:
                    gtype = fr
                elif ff == 4:
                    geom = _packed_ints(fr)
            attrs = {keys[tags[i]]: vals[tags[i + 1]] for i in range(0, len(tags) - 1, 2)}
            coords = []
            for ring in _geometry(geom):
                pts = []
                for px, py in ring:
                    lon = (tx + px / extent) / n * 360.0 - 180.0
                    lat = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * (ty + py / extent) / n))))
                    pts.append((round(lon, 7), round(lat, 7)))
                coords.append(pts)
            layer.append({"attrs": attrs, "geom": coords, "type": gtype})
        out[name] = layer
    return out


# ---------------------------------------------------------------- polygon


def load_polygon(path):
    if not os.path.exists(path):
        return None
    g = json.load(open(path))
    if g.get("type") == "Polygon":
        return [g["coordinates"]]
    if g.get("type") == "MultiPolygon":
        return g["coordinates"]
    return None


class Clip:
    """Punkt-i-polygon med lat-band for snabbhet (sjon har 18k kantpunkter)."""

    BAND = 0.002

    def __init__(self, polys, bbox):
        self.polys = polys or []
        self.bbox = bbox
        self.buckets = collections.defaultdict(list)
        for poly in self.polys:
            for ring in poly:
                self._add(ring)

    def _add(self, ring):
        for (x1, y1), (x2, y2) in zip(ring, ring[1:]):
            if y1 == y2:
                continue
            lo, hi = (y1, y2) if y1 < y2 else (y2, y1)
            for b in range(int(lo / self.BAND), int(hi / self.BAND) + 1):
                self.buckets[b].append((x1, y1, x2, y2))

    def __call__(self, lon, lat):
        w, s, e, n = self.bbox
        if not (w <= lon <= e and s <= lat <= n):
            return False
        if not self.polys:
            return True
        xs = []
        for x1, y1, x2, y2 in self.buckets.get(int(lat / self.BAND), ()):
            if (y1 > lat) != (y2 > lat):
                xs.append(x1 + (lat - y1) * (x2 - x1) / (y2 - y1))
        return sum(1 for x in xs if x > lon) % 2 == 1


def metres(lat1, lon1, lat2, lon2):
    dx = (lon2 - lon1) * 111320 * math.cos(math.radians((lat1 + lat2) / 2))
    dy = (lat2 - lat1) * 111320
    return math.hypot(dx, dy)


def clip_rect(ring, minx, miny, maxx, maxy):
    """Sutherland-Hodgman: klipp en ring mot en rektangel (kaklets egen yta)."""
    def clip_edge(pts, inside, cut):
        out = []
        for i, cur in enumerate(pts):
            prv = pts[i - 1]
            if inside(cur):
                if not inside(prv):
                    out.append(cut(prv, cur))
                out.append(cur)
            elif inside(prv):
                out.append(cut(prv, cur))
        return out

    def cut_x(x):
        def f(p1, p2):
            t = (x - p1[0]) / (p2[0] - p1[0])
            return (x, p1[1] + t * (p2[1] - p1[1]))
        return f

    def cut_y(y):
        def f(p1, p2):
            t = (y - p1[1]) / (p2[1] - p1[1])
            return (p1[0] + t * (p2[0] - p1[0]), y)
        return f

    pts = list(ring)
    for inside, cut in ((lambda p: p[0] >= minx, cut_x(minx)),
                        (lambda p: p[0] <= maxx, cut_x(maxx)),
                        (lambda p: p[1] >= miny, cut_y(miny)),
                        (lambda p: p[1] <= maxy, cut_y(maxy))):
        if not pts:
            return []
        pts = clip_edge(pts, inside, cut)
    return pts


def curve_labels(curves, spacing=900.0, min_len=400.0, min_gap=300.0):
    """Etikettpunkter ("3", "6") langs kurvorna, med vinkel i grader for texten."""
    out = []
    placed = []

    def far_from_others(lat, lon):
        for la, lo in placed:
            if metres(lat, lon, la, lo) < min_gap:
                return False
        return True

    for c in curves:
        pts = [(p[1], p[0]) for p in c["c"]]        # (lon, lat)
        total = 0.0
        segs = []
        for a, b in zip(pts, pts[1:]):
            d = metres(a[1], a[0], b[1], b[0])
            segs.append((a, b, d, total))
            total += d
        if total < min_len or not segs:
            continue
        if total < spacing * 1.6:
            targets = [total / 2]
        else:
            targets = [spacing * (i + 0.5) for i in range(int(total // spacing))]
        for t in targets:
            for a, b, d, start in segs:
                if start <= t <= start + d and d > 0:
                    f = (t - start) / d
                    lon = a[0] + (b[0] - a[0]) * f
                    lat = a[1] + (b[1] - a[1]) * f
                    dx = (b[0] - a[0]) * math.cos(math.radians(lat))
                    dy = b[1] - a[1]
                    bearing = math.degrees(math.atan2(dx, dy))
                    ang = bearing - 90.0
                    if ang < -90:
                        ang += 180
                    if ang > 90:
                        ang -= 180
                    if far_from_others(lat, lon):
                        placed.append((lat, lon))
                        out.append([round(lat, 5), round(lon, 5), round(ang, 1), str(c["d"])])
                    break
    return out


def cluster(items, radius_m):
    """Slår ihop punkter inom radius_m; behåller namn, ljus och bästa typ."""
    grid = collections.defaultdict(list)
    out = []
    for p in items:
        cx, cy = int(p["lat"] / 0.0002), int(p["lon"] / 0.0002)
        hit = None
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                for q in grid.get((cx + dx, cy + dy), ()):
                    if (q["kind"] != p["kind"]) or (q["light"] != p["light"]):
                        continue
                    if metres(p["lat"], p["lon"], q["lat"], q["lon"]) <= radius_m:
                        hit = q
                        break
                if hit:
                    break
            if hit:
                break
        if hit is None:
            grid[(cx, cy)].append(p)
            out.append(p)
            continue
        if not hit["name"] and p["name"]:
            hit["name"] = p["name"]
        if not hit["light"] and p["light"]:
            hit["light"] = p["light"]
        if hit["kind"] == "other" and p["kind"] != "other":
            hit["kind"] = p["kind"]
        if p["kind"] == "fixed_light" and hit["kind"] != "fixed_light":
            hit["kind"] = "fixed_light"
    return out


def simplify(pts, tol_m):
    """Douglas-Peucker med tolerans i meter (grader raknas om vid 59 N)."""
    if len(pts) < 3:
        return pts
    lat0 = pts[0][1]
    kx = 111320 * math.cos(math.radians(lat0))
    ky = 111320
    tol = tol_m

    def seg_dist(p, a, b):
        px, py = p[0] * kx, p[1] * ky
        ax, ay = a[0] * kx, a[1] * ky
        bx, by = b[0] * kx, b[1] * ky
        dx, dy = bx - ax, by - ay
        if dx == 0 and dy == 0:
            return math.hypot(px - ax, py - ay)
        t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
        return math.hypot(px - (ax + t * dx), py - (ay + t * dy))

    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        i, j = stack.pop()
        best, idx = 0.0, None
        for k in range(i + 1, j):
            d = seg_dist(pts[k], pts[i], pts[j])
            if d > best:
                best, idx = d, k
        if idx is not None and best > tol:
            keep[idx] = True
            stack.append((i, idx))
            stack.append((idx, j))
    return [p for p, k in zip(pts, keep) if k]


def tile_xy(lon, lat, z):
    n = 2 ** z
    return (int((lon + 180) / 360 * n),
            int((1 - math.log(math.tan(math.radians(lat)) + 1 / math.cos(math.radians(lat))) / math.pi) / 2 * n))


# ---------------------------------------------------------------- nedladdning


def download(cache, bbox):
    os.makedirs(cache, exist_ok=True)
    w, s, e, n = bbox
    todo = []
    for z in ZOOMS:
        x0, y0 = tile_xy(w, n, z)
        x1, y1 = tile_xy(e, s, z)
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                path = os.path.join(cache, "%d_%d_%d.mvt" % (z, x, y))
                if not os.path.exists(path):
                    todo.append((z, x, y, path))
    print("kakel: %d saknas av %d" % (len(todo), len(todo) + sum(
        1 for f in os.listdir(cache) if f.endswith(".mvt"))))
    # Parallell nedladdning med curl (12 at gangen).
    if todo:
        jobs = os.path.join(cache, "_fetch.txt")
        with open(jobs, "w") as fh:
            for z, x, y, path in todo:
                fh.write('%s\t%s/%s/%d/%d/%d.mvt\n' % (path, BASE, DATASET, z, x, y))
        with open(jobs) as stdin:
            subprocess.run(
                ["xargs", "-P", "12", "-n", "2", "bash", "-c",
                 'curl -s -m 45 --retry 2 --retry-delay 1 -o "$0" "$1"'],
                stdin=stdin, check=False,
            )
    files = [os.path.join(cache, f) for f in os.listdir(cache) if f.endswith(".mvt")]
    return sorted(files)


# ---------------------------------------------------------------- S-57-koder

COLOUR = {1: "V", 2: "Sv", 3: "R", 4: "G", 5: "B", 6: "Y", 7: "Gr", 8: "Br",
          9: "O", 10: "Vio", 11: "Or", 12: "M", 13: "P"}
LIGHT_CHAR = {1: "F", 2: "Fl", 3: "LFl", 4: "Q", 5: "VQ", 6: "UQ", 7: "Iso",
              8: "OC", 9: "Mo", 10: "IQ", 11: "IVQ", 12: "IUQ", 13: "Fl+Fl",
              14: "Fl(2+1)", 15: "Q+LFl", 16: "VQ+LFl", 17: "UQ+LFl", 18: "Al",
              19: "Al+Fl", 20: "Al+OC"}

KIND_SV = {
    "lateral_port": "Röd babordsprick",
    "lateral_starboard": "Grön styrbordsprick",
    "special": "Gul specialprick",
    "isolated_danger": "Grundprick (enstaka fara)",
    "safe_water": "Mittledsboj",
    "fixed_light": "Fyr / fast ljus",
    "other": "Boj / prick",
}
TOPMARK_BY_KIND = {
    "lateral_port": "Röd cylinder",
    "lateral_starboard": "Grön kon, spets upp",
    "cardinal_N": "Två svarta koner, spetsar upp",
    "cardinal_S": "Två svarta koner, spetsar ned",
    "cardinal_E": "Två svarta koner, baser mot varandra",
    "cardinal_W": "Två svarta koner, spetsar mot varandra",
    "special": "Gult kryss",
    "isolated_danger": "Två svarta klot",
}


def kind_for_colour(raw):
    """S-57-farg (lista som strang) -> IALA-typ for Hjalmarens prickar."""
    try:
        cols = json.loads(raw) if raw else []
    except Exception:
        cols = []
    cols = [c for c in cols if isinstance(c, int)]
    if not cols:
        return "other"
    if cols[0] == 3 and len(cols) > 1 and cols[1] == 1:
        return "lateral_port"          # röd/vit... sallsynt har
    if cols[0] == 2 and len(cols) > 2 and cols[1] == 3:
        return "isolated_danger"       # svart-röd-svart
    if cols[0] == 3:
        return "lateral_port"
    if cols[0] == 4:
        return "lateral_starboard"
    if cols[0] == 6:
        return "special"
    if cols[0] == 2 and len(cols) > 1 and cols[1] == 6:
        return "special"               # svart/gul specialprick
    if cols[0] == 1 and 3 in cols:
        return "safe_water"            # röd/vit mittledsboj
    return "other"


def light_text(attrs):
    """LITCHR/SIGGRP/SIGPER/COLOUR -> 'Fl R 4s'."""
    txt = attrs.get("LIGHTS_TEXT")
    if txt:
        return txt
    ch = LIGHT_CHAR.get(attrs.get("LITCHR"), "")
    if not ch:
        return ""
    colour = ""
    try:
        cols = json.loads(attrs.get("COLOUR") or "[]")
        if cols:
            colour = COLOUR.get(cols[0], "")
    except Exception:
        pass
    grp = attrs.get("SIGGRP") or ""
    per = attrs.get("SIGPER")
    per = ("%ds" % per) if per else ""
    return " ".join(p for p in (ch + (grp if grp and grp != "(1)" else ""), colour, per) if p)


# ---------------------------------------------------------------- bygge


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="site/data")
    ap.add_argument("--cache", default=".cache_skipper")
    ap.add_argument("--polygon", default="lake_polygon.json")
    args = ap.parse_args()

    polys = load_polygon(args.polygon)
    bbox = BBOX
    if polys:
        pts = [p for poly in polys for ring in poly for p in ring]
        bbox = (min(p[0] for p in pts) - 0.01, min(p[1] for p in pts) - 0.01,
                max(p[0] for p in pts) + 0.01, max(p[1] for p in pts) + 0.01)
    clip = Clip(polys, bbox)
    print("bbox %.4f %.4f %.4f %.4f  polygon=%s" % (bbox + (bool(polys),)))

    files = download(args.cache, bbox)

    rocks = []        # (lat, lon, depth)
    curves = []       # {"d": valdco, "c": [[lat, lon], ...]}
    areas = []        # {"d": DRVAL1, "c": [ring, ...]} - djupytor med fyllning
    soundings = []    # (lat, lon, djup) - siffrorna i oppet vatten
    names = []        # (lat, lon, namn, sort, rang) - ortnamn fran sjoskortet
    buoys = []        # dicts
    lights = []
    seen_curve = set()

    for path in files:
        base = os.path.basename(path)[:-4]
        if "_" not in base:
            continue
        z, x, y = (int(v) for v in base.split("_"))
        data = open(path, "rb").read()
        if not data:
            continue
        try:
            tile = read_tile(data, z, x, y)
        except Exception as exc:                       # trasigt kakel: hoppa
            print("  varning: %s: %s" % (path, exc))
            continue
        for layer, feats in tile.items():
            if layer == "UWTROC":
                for f in feats:
                    if not f["geom"]:
                        continue
                    lon, lat = f["geom"][0][0]
                    if not clip(lon, lat):
                        continue
                    depth = f["attrs"].get("VALSOU")
                    rocks.append((round(lat, 6), round(lon, 6),
                                  round(float(depth), 1) if depth is not None else -1))
            elif layer == "DEPCNT":
                if z != max(ZOOMS):
                    continue
                for f in feats:
                    if not f["geom"]:
                        continue
                    # Inga urklippningar av linjer: kaklen ar redan begransade till
                    # Hjalmarens bbox, och att klippa mitt i en kurva gav gluggar.
                    ring = f["geom"][0]
                    val = f["attrs"].get("VALDCO")
                    if val is None:
                        continue
                    key = (val, len(ring), round(ring[0][0], 4), round(ring[0][1], 4),
                           round(ring[-1][0], 4), round(ring[-1][1], 4))
                    if key in seen_curve:
                        continue
                    seen_curve.add(key)
                    kept = simplify([(lo, la) for lo, la in ring], 6.0)
                    coarse = simplify([(lo, la) for lo, la in ring], 30.0)
                    if len(kept) >= 2:
                        curves.append({"d": val,
                                       "c": [[round(la, 6), round(lo, 6)] for lo, la in kept],
                                       "c2": [[round(la, 6), round(lo, 6)] for lo, la in coarse]})
            elif layer == "DEPARE":
                if z != max(ZOOMS):
                    continue
                # Kakklen overlappar varandra i kanterna (buffer). Behåll bara de
                # polygoner vars tyngdpunkt ligger inom rutans egen yta, annars
                # ritas samma yta två gånger och fyllningen släcks ut.
                n = 2.0 ** z
                lon0, lon1 = x / n * 360.0 - 180.0, (x + 1) / n * 360.0 - 180.0
                lat_top = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / n))))
                lat_bot = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * (y + 1) / n))))
                for f in feats:
                    if not f["geom"]:
                        continue
                    d = f["attrs"].get("DRVAL1")
                    if d is None:
                        continue
                    rings, rings_c = [], []
                    for ring in f["geom"]:
                        clipped = clip_rect([(lo, la) for lo, la in ring], lon0, lat_bot, lon1, lat_top)
                        if len(clipped) < 3:
                            continue
                        keep = simplify(clipped, 15.0)
                        coarse = simplify(clipped, 60.0)
                        if len(keep) >= 4:
                            rings.append([[round(la, 5), round(lo, 5)] for lo, la in keep])
                            rings_c.append([[round(la, 5), round(lo, 5)] for lo, la in coarse])
                    if rings:
                        areas.append({"d": d, "c": rings, "c2": rings_c})
            elif layer in ("SEAARE_POINT", "LNDRGN_POINT", "LAKARE_POINT"):
                if z != max(ZOOMS):
                    continue
                for f in feats:
                    if not f["geom"]:
                        continue
                    nm = (f["attrs"].get("OBJNAM") or "").strip()
                    if not nm:
                        continue
                    # Inget polygon-urklipp: ortnamnen ligger ofta pa land (oar, uddar).
                    lon, lat = f["geom"][0][0]
                    if layer == "LNDRGN_POINT":
                        kind, rank = 1, 3
                    elif "Hjälmaren" in nm:
                        kind, rank = 0, (0 if nm.strip() == "Hjälmaren" else 1)
                    else:
                        kind, rank = 0, 2
                    names.append((round(lat, 6), round(lon, 6), nm, kind, rank))
            elif layer == "SOUNDG":
                if z != max(ZOOMS):
                    continue
                for f in feats:
                    if not f["geom"] or "point_count" in f["attrs"]:
                        continue
                    lon, lat = f["geom"][0][0]
                    if not clip(lon, lat):
                        continue
                    v = f["attrs"].get("ZVALUE")
                    if v is None:
                        continue
                    soundings.append((round(lat, 6), round(lon, 6), round(float(v), 1)))
            elif layer in ("BOYS", "BEACONS"):
                for f in feats:
                    if not f["geom"]:
                        continue
                    lon, lat = f["geom"][0][0]
                    if not clip(lon, lat):
                        continue
                    a = f["attrs"]
                    if layer == "BEACONS":
                        kind = "fixed_light" if a.get("LIGHTS_TEXT") else "other"
                    else:
                        kind = kind_for_colour(a.get("COLOUR"))
                    buoys.append({
                        "lat": round(lat, 6), "lon": round(lon, 6), "kind": kind,
                        "name": (a.get("OBJNAM") or "").strip(),
                        "light": a.get("LIGHTS_TEXT") or "",
                    })
            elif layer == "LIGHTS":
                for f in feats:
                    if not f["geom"]:
                        continue
                    lon, lat = f["geom"][0][0]
                    if not clip(lon, lat):
                        continue
                    lights.append({"lat": round(lat, 6), "lon": round(lon, 6),
                                   "light": light_text(f["attrs"])})

    # --- stenar: slå ihop samma sten fran olika zoomar (kvantisering skiljer nagra meter)
    uniq = {}
    for lat, lon, depth in sorted(rocks, key=lambda r: (r[2] < 0, r[0])):
        key = (round(lat / 0.00008), round(lon / 0.00008))   # ~8 m ruta
        if key in uniq:
            old = uniq[key]
            if old[2] < 0 and depth >= 0:
                uniq[key] = (old[0], old[1], depth)
            continue
        uniq[key] = (lat, lon, depth)
    stones = sorted(uniq.values())

    # --- ortnamn: samma namn kan komma fran flera rutor och fran bada lagren
    seen_name = {}
    for lat, lon, nm, kind, rank in names:
        key = (nm.lower(), round(lat, 3), round(lon, 3))
        if key not in seen_name or rank < seen_name[key][4]:
            seen_name[key] = (lat, lon, nm, kind, rank)
    names = sorted(seen_name.values(), key=lambda n: (n[4], n[2]))

    # --- djupssiffror: samma siffra kan komma fran flera rutor
    seen_snd = set()
    uniq_snd = []
    for lat, lon, v in soundings:
        key = (round(lat / 0.0001), round(lon / 0.0001))
        if key in seen_snd:
            continue
        seen_snd.add(key)
        uniq_snd.append([lat, lon, v])
    soundings = uniq_snd

    # --- bojar: samma prick finns pa alla tre zoomnivaer -> slå ihop inom 10 m
    buoys = cluster(buoys, 6.0)

    # --- ljus: fäst pa närmaste boj/prick om det finns nagon inom 25 m
    for li in lights:
        best, bestd = None, 1e9
        for b in buoys:
            d = metres(li["lat"], li["lon"], b["lat"], b["lon"])
            if d < bestd:
                best, bestd = b, d
        if best is not None and bestd < 25:
            if not best["light"]:
                best["light"] = li["light"]
            if best["kind"] == "other":
                best["kind"] = "fixed_light"
        else:
            buoys.append({"lat": li["lat"], "lon": li["lon"], "kind": "fixed_light",
                          "name": "", "light": li["light"]})

    feats = []
    for b in buoys:
        kind = b["kind"]
        group = ("fixed" if kind == "fixed_light" else
                 "lit" if b["light"] else
                 "topmark" if kind in TOPMARK_BY_KIND else "plain")
        feats.append({
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [b["lon"], b["lat"]]},
            "properties": {
                "kind": kind,
                "group": group,
                "type": KIND_SV.get(kind, kind),
                "name": b["name"],
                "light": b["light"],
                "topmark": TOPMARK_BY_KIND.get(kind, ""),
                "source": "S-57 via Skippo",
            },
        })

    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "stenar.json"), "w") as fh:
        json.dump({"count": len(stones), "stones": stones}, fh, separators=(",", ":"))
    # Sjon som basfyllning: S-57 saknar djupyta i en del omraden, och utan en bas
    # blir de halorna genomskinliga (man ser OSM-vattnet under).
    lake_rings = []
    if polys:
        for ring in polys[0]:
            keep = simplify([(lon, lat) for lon, lat in ring], 30.0)
            if len(keep) >= 4:
                lake_rings.append([[round(lat, 5), round(lon, 5)] for lon, lat in keep])

    labels = curve_labels(curves)
    with open(os.path.join(args.out, "djup.json"), "w") as fh:
        json.dump({"lake": lake_rings, "areas": areas, "curves": curves, "labels": labels,
                   "soundings": soundings, "names": names}, fh, separators=(",", ":"))
    with open(os.path.join(args.out, "s57marken.geojson"), "w") as fh:
        json.dump({"type": "FeatureCollection", "features": feats}, fh, ensure_ascii=False)

    print("stenar: %d  djupytor: %d  djupkurvor: %d  etiketter: %d  djupssiffror: %d  ortnamn: %d  sjomarken: %d"
          % (len(stones), len(areas), len(curves), len(labels), len(soundings), len(names), len(feats)))
    for f in ("stenar.json", "djup.json", "s57marken.geojson"):
        p = os.path.join(args.out, f)
        print("  %-22s %7.0f kB" % (f, os.path.getsize(p) / 1024))


if __name__ == "__main__":
    main()
