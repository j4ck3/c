#!/usr/bin/env python3
"""Gor om Skippos Mapbox-stil till en MapLibre-stil med lokala tiles.

Skippos planerare ar Mapbox GL + S-57-vektorkakel. Har byts kartkallorna mot
vara egna kopior under /tiles, sprites/glyphs mot /sprite och /glyphs, och de
Mapbox-specifika "config"-uttrycken byts mot konstanter (MapLibre kan dem inte).

Bygger tva stilar med samma regler: site/style.json (Skippos light.json) och
site/style-night.json (Skippos night.json, med nattsprite i site/sprite-night/).
"""
import json

# kalla, utfil, sprite-katalog
VARIANTS = (
    ('skippo_style_light.json', 'site/style.json', 'sprite-v2'),
    ('skippo_style_night.json', 'site/style-night.json', 'sprite-night'),
)
CONFIG_DEFAULTS = {'hideDepth': 50000, 'symbolScale': 1}


def fix(node):
    if isinstance(node, dict):
        return {k: fix(v) for k, v in node.items()}
    if isinstance(node, list):
        if len(node) == 2 and node[0] == 'config':
            return CONFIG_DEFAULTS.get(node[1], 1)
        return [fix(v) for v in node]
    return node


def sanitize(node):
    """MapLibre kann inte allt som Mapbox v3 kann: ta bort slot-lager, pitch-villkor
    och uttryck dar MapLibre kraver konstanter."""
    if isinstance(node, list):
        if len(node) > 2 and node[0] == 'step' and node[1] == ['pitch']:
            return node[2]                     # behall "true"-grenen
        return [sanitize(v) for v in node]
    if isinstance(node, dict):
        out = {}
        for k, v in node.items():
            if k == 'visibility' and isinstance(v, list):
                out[k] = 'visible'
            elif k == 'text-offset' and isinstance(v, list) and any(isinstance(x, list) for x in v):
                out[k] = [0, 0]
            elif k == 'text-font' and isinstance(v, list) and v and v[0] == 'step':
                out[k] = v[2]                  # MapLibre kraver konstant typsnitt
            else:
                out[k] = sanitize(v)
        return out
    return node


def build(SRC, OUT, SPRITE):
    style = json.load(open(SRC))
    style['layers'] = [l for l in style['layers'] if l.get('type') != 'slot']
    style = fix(style)
    style = sanitize(style)

    # Kakel, typsnitt och sprite serveras med "immutable" (30 dagar). ?v= i adressen ar darfor
    # enda sattet att fa webblasarna att hamta om dem: byt VERSION nar kaklen speglas om, nya
    # glyph-intervall laggs till eller spriten byts. Annars visar webblasarna det gamla i en manad.
    VERSION = '20261108c'
    style['glyphs'] = f'/glyphs/{{fontstack}}/{{range}}.pbf?v={VERSION}'
    style['sprite'] = f'/{SPRITE}/sprite'   # bytt sprite? byt katalognamn (sprite-v3), query-strang fungerar inte har

    drop = {'mapbox.satellite', 'skippo-orto'}
    # Stenarna finns bara i kaklen fran zoom 12 och uppat (Skippos egen kakelpyramid).
    # Egen kalla med minzoom 12 gor att de anda kan visas fran zoom 11 (nedskalade).
    # Samma ruta som mirror_tiles.py speglar. Utanfor den finns inga kakel; med bounds slutar
    # MapLibre fraga efter dem (de gav hundratals 404 per besok).
    BOUNDS = [15.15, 59.05, 16.55, 59.45]
    ATTRIB_CHART = 'Sjökort © Sjöfartsverket (S-57), kakel och stil via Skippo'
    ATTRIB_OSM = '© OpenStreetMap contributors'

    style['sources'] = {
        'osm': {
            'type': 'vector',
            'tiles': [f'/tiles/osm/{{z}}/{{x}}/{{y}}.mvt?v={VERSION}'],
            'bounds': BOUNDS,
            'minzoom': 0,
            'maxzoom': 8,
            'attribution': ATTRIB_OSM,
        },
        'nautical': {
            'type': 'vector',
            'tiles': [f'/tiles/s57/{{z}}/{{x}}/{{y}}.mvt?v={VERSION}'],
            'bounds': BOUNDS,
            'minzoom': 4,
            'maxzoom': 14,
            'attribution': ATTRIB_CHART,
        },
    }
    style['layers'] = [l for l in style['layers'] if l.get('source') not in drop and l['id'] not in drop]

    # Sjomarkena (bojar, prickar, toppbeteckningar, ljus, fyrar) ritas fran site/data/sjomarken.geojson
    # i stallet for kaklen. Filen byggs av build_marks.py fran samma kakel och har tre extra
    # egenskaper: HJ_TOPMARK och HJ_LIGHT (sa att sidan kan filtrera pa "har toppbeteckning/ljus",
    # vilket kraver en koppling mellan tva kakellager som ett MapLibre-filter inte kan gora) och
    # HJ_MINZ (forsta zoom dar Skippo visar punkten, sa att gallringen pa lag zoom ar densamma).
    MARK_LAYERS = ('BOYS', 'BEACONS', 'TOPMAR', 'LIGHTS', 'LIGHTHOUSES')
    style['sources']['marks'] = {
        'type': 'geojson',
        'data': f'/data/sjomarken.geojson?v={VERSION}',
        'attribution': ATTRIB_CHART,
    }
    for layer in style['layers']:
        sl = layer.get('source-layer')
        if layer.get('source') == 'nautical' and sl in MARK_LAYERS:
            layer['source'] = 'marks'
            del layer['source-layer']
            own = layer.get('filter', True)
            layer['filter'] = ['all', ['==', ['get', '_L'], sl], ['>=', ['zoom'], ['get', 'HJ_MINZ']], own]

    # Fargbokstaverna (R, G, BY ...) som lagren BOYS-colour/BEACONS-colour skrev ut
    # bredvid varje boj behovs inte - ikonen visar redan fargen. Ljusbeteckningarna
    # ("Fl G 4s") ligger kvar i BOYS/BEACONS-lagren.
    style['layers'] = [l for l in style['layers']
                       if l['id'] not in ('BOYS-colour', 'BEACONS-colour')]

    # OSM-baskartan har bara kakel till zoom 8. Lager utan maxzoom (bara
    # "land_polygons") ritades darfor vidare pa hog zoom fran overzoomade z8-rutor
    # och gav en stor gul landruta mitt i sjon. Samma tak som syskonlagren.
    for layer in style['layers']:
        if layer.get('source') == 'osm' and layer.get('maxzoom') is None:
            layer['maxzoom'] = 9.5

    # Skippos fasta etiketter ar pa engelska. Byt dem mot svenska i text-field-uttrycken.
    # Bara strangkonstanter byts (inte egenskapsnamn), sa datat i kaklen paverkas inte.
    LABELS_SV = {
        'Nature reserve': 'Naturreservat', 'Speed restr. zone': 'Fartbegr. område', 'Speed restriction zone': 'Fartbegränsning',
        'Cable ferry': 'Linfärja', 'Flood barrage': 'Flodbarriär', 'Floating barrier': 'Flytande spärr',
        'Ice boom': 'Isbom', 'Well': 'Brunn', 'Obstn': 'Hinder', 'Log Pond': 'Timmerdamm',
        'Precautionary Area': 'Försiktighetsområde', 'Mine field': 'Minfält', 'Swinging area': 'Svajområde',
        'Water skiing area': 'Vattenskidområde', 'Submarine excercise area': 'Ubåtsövningsområde',
        'Dumping Ground for Chemicals': 'Dumpningsplats för kemikalier',
        'Explosives Dumping Ground': 'Dumpningsplats för sprängämnen', 'Spoil Ground': 'Muddertipp',
        'Hulk': 'Hulk', 'Wk ': 'Vrak ', 'Masts ': 'Master ', 'Wd': 'Tång', 'Hostel': 'Vandrarhem',
        'Pilots\n': 'Lotsar\n', 'Pilot lookout\n': 'Lotsutkik\n', '(open ': '(öppen ',
        'Jan': 'jan', 'Feb': 'feb', 'Mar': 'mar', 'Apr': 'apr', 'May': 'maj', 'June': 'jun', 'July': 'jul',
        'Aug': 'aug', 'Sept': 'sep', 'Oct': 'okt', 'Nov': 'nov', 'Dec': 'dec',
    }


    def sv(node, top=True):
        if isinstance(node, str):
            return node if top else LABELS_SV.get(node, node)
        if isinstance(node, list):
            if node and node[0] == 'get':           # egenskapsnamn, inte etikett
                return node
            return [sv(v, False) for v in node]
        return node


    for layer in style['layers']:
        lay = layer.get('layout') or {}
        if 'text-field' in lay:
            tf = lay['text-field']
            lay['text-field'] = LABELS_SV.get(tf, tf) if isinstance(tf, str) else sv(tf)

    json.dump(style, open(OUT, 'w'), separators=(',', ':'), ensure_ascii=False)
    print('skrev', OUT, len(style['layers']), 'lager')


for variant in VARIANTS:
    build(*variant)
