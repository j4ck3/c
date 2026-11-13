"""Build the data files the map page loads: marks.geojson (buoys and lights) and rocks.json."""
import json, re, sys

SRC_MARKS, SRC_ROCKS, OUT = sys.argv[1:4]
SRC_UFS = sys.argv[4] if len(sys.argv) > 4 else None

TYPE_SV = {
    "lateral_port": "Röd babordsprick", "lateral_starboard": "Grön styrbordsprick",
    "cardinal_N": "Nordprick", "cardinal_S": "Sydprick", "cardinal_E": "Ostprick", "cardinal_W": "Västprick",
    "special": "Gul specialprick", "isolated_danger": "Grundprick", "safe_water": "Mittledsboj",
    "other": "Boj", "fixed_light": "Fast fyr / ljus",
}
TOPMARK_SV = [
    (r"cylinder|square", "Röd cylinder"), (r"cone.*up|triangle", "Grön kon, spets upp"),
    (r"points? up|cones up", "Två svarta koner, spetsar upp (N)"),
    (r"points? down|cones down", "Två svarta koner, spetsar ned (S)"),
    (r"base together|base-to-base", "Två svarta koner, baser mot varandra (O)"),
    (r"point to point|point together", "Två svarta koner, spetsar mot varandra (V)"),
    (r"\bX\b|x-shape|cross", "Gult kryss"), (r"ball|sphere", "Klot"),
]
CONF_SV = {"high": "Säker", "medium": "Ganska säker", "low": "Osäker"}

def place(label):
    """Strip side letters and light codes from the chart label, keep the place name."""
    s = label or ""
    s = re.sub(r"\b(L?Fl|Iso|Q|F)\s*(\(\d+\))?\s*[RGWY]*\s*\d*s?\b", "", s)
    s = re.sub(r"^(G/R|RW|G|R)\b[ ,]*", "", s.strip())
    s = re.sub(r"\(\s*\d+(_\d+)?\s*\)", "", s)          # depth figures like (15)
    s = re.sub(r"\b(junction to|branch|harbour|inner channel|mouth|shoal|of|near|west|E|S|N|W)\b", lambda m: {
        "junction to": "korsning mot", "branch": "gren", "harbour": "hamn", "inner channel": "inre farled",
        "mouth": "mynning", "shoal": "grund", "of": "om", "near": "nära", "west": "väst"}.get(m.group(0), m.group(0)), s)
    s = s.replace("fish traps", "fiskeredskap").replace("leading light", "ledfyr").replace("sector light", "sektorfyr")
    s = re.sub(r"[\s,()/]+$", "", re.sub(r"^[\s,()/]+", "", s))
    s = re.sub(r"\s{2,}", " ", s).strip(" ,")
    return "" if re.fullmatch(r"[\d\s.,_-]*", s) else s

TOPMARK_BY_KIND = {
    "lateral_port": "Röd cylinder", "lateral_starboard": "Grön kon, spets upp",
    "cardinal_N": "Två svarta koner, spetsar upp", "cardinal_S": "Två svarta koner, spetsar ned",
    "cardinal_E": "Två svarta koner, baser mot varandra", "cardinal_W": "Två svarta koner, spetsar mot varandra",
    "special": "Gult kryss", "isolated_danger": "Två svarta klot",
}

def topmark(raw, kind):
    """Topmark text; the buoy type decides the shape, the raw chart reading only says one exists."""
    if not raw:
        return ""
    if kind in TOPMARK_BY_KIND:
        return TOPMARK_BY_KIND[kind]
    for pat, sv in TOPMARK_SV:
        if raw and re.search(pat, raw, re.I):
            return sv
    return "Toppmärke" if raw else ""

src = json.load(open(SRC_MARKS))["features"]
feats = []
for i, f in enumerate(sorted(src, key=lambda f: f["geometry"]["coordinates"][0]), 1):
    p = f["properties"]
    kind = p["kind"]
    group = "fixed" if p["fixed"] else "lit" if p["lit"] else "topmark" if p["has_topmark"] else "plain"
    feats.append({"type": "Feature", "geometry": f["geometry"], "properties": {
        "id": i, "kind": kind, "group": group,
        "type": TYPE_SV.get(kind, kind),
        "name": place(p.get("label", "")),
        "light": p.get("light", ""),
        "topmark": topmark(p.get("topmark", ""), kind),
        "confidence": CONF_SV.get(p.get("confidence", ""), ""),
    }})
# Special buoys introduced by Ufs notices that the chart reading did not cover.
import math
def near(lat, lon, tol=25):
    for f in feats:
        x, y = f["geometry"]["coordinates"]
        if math.hypot((x - lon) * 111320 * math.cos(math.radians(lat)), (y - lat) * 111320) < tol:
            return True
    return False
if SRC_UFS:
    for n in json.load(open(SRC_UFS))["notices"]:
        acts = n.get("actions") or []
        if n.get("general") or not any(re.search(r"Inför specialprick", a) for a in acts):
            continue
        # Positions listed after a "Stryk" (remove) action belong to removed buoys; only take
        # as many positions as the notice introduces (letters a) - e) or one per "Inför" line).
        m = re.search(r"Inför specialprick[^)]*\b([a-z])\)\s*-\s*([a-z])\)", " ".join(acts))
        count = (ord(m.group(2)) - ord(m.group(1)) + 1) if m else sum("Inför specialprick" in a for a in acts)
        for lat, lon in (n.get("positions") or [])[:count]:
            if near(lat, lon):
                continue
            feats.append({"type": "Feature", "geometry": {"type": "Point", "coordinates": [round(lon, 6), round(lat, 6)]},
                "properties": {"id": len(feats) + 1, "kind": "special", "group": "topmark", "type": TYPE_SV["special"],
                    "name": re.sub(r"\.\s*Utmärkning\.?$|\.\s*Utprickning\.?$", "", n["title"]).strip(),
                    "light": "", "topmark": TOPMARK_BY_KIND["special"], "confidence": f"Ufs {n['number']}",
                    "source": n["url"]}})
# Marks reported by the user that no official source lists yet (manual_marks.json next to this script).
import os
MANUAL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "manual_marks.json")
if os.path.exists(MANUAL):
    for m in json.load(open(MANUAL)):
        if near(m["lat"], m["lon"], tol=5):
            continue
        feats.append({"type": "Feature", "geometry": {"type": "Point", "coordinates": [m["lon"], m["lat"]]},
            "properties": {"id": len(feats) + 1, "kind": m["kind"], "group": "topmark" if m["kind"] in TOPMARK_BY_KIND else "plain",
                "type": TYPE_SV.get(m["kind"], m["kind"]), "name": m.get("name", ""), "light": m.get("light", ""),
                "topmark": TOPMARK_BY_KIND.get(m["kind"], ""), "confidence": m.get("note", "Uppgift från användare")}})
json.dump({"type": "FeatureCollection", "features": feats}, open(f"{OUT}/marks.geojson", "w"), ensure_ascii=False)

rocks = json.load(open(SRC_ROCKS))["features"]
json.dump([[round(r["geometry"]["coordinates"][1], 6), round(r["geometry"]["coordinates"][0], 6)] for r in rocks],
          open(f"{OUT}/rocks.json", "w"))
print(len(feats), "marks,", len(rocks), "rocks")
