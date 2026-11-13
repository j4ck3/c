#!/usr/bin/env python3
"""Telegram alert for Boeing 767 freighters without a filed destination that are heading to Örebro (ORB/ESOE).

Polls the Flightradar24 web feed, filtered server-side to TYPES, for a box that covers RADIUS_KM
around ORB. An aircraft triggers an alert when:
  * it is airborne and FR24 lists no destination,
  * it is within RADIUS_KM of the airport,
  * its track points at the airport: the airport is ahead, and either the angle between its
    track and the great-circle bearing to ORB is at most MAX_ANGLE_DEG or the cross-track
    distance is at most MAX_XTRACK_KM,
  * inside NEAR_KM it is low enough or descending (alt <= MAX_ALT_FT, or vertical speed
    <= DESCENT_FPM), which filters out high-level overflights close to ORB,
  * it is a freighter: the FR24 aircraft model names a freighter variant (767-xxxF, BCF, BDSF,
    SF, P2F, "Freighter"), or FR24 gives no model and the operator is a known cargo airline.

Each aircraft alerts at most once per COOLDOWN_MIN.
"""
import json
import math
import os
import re
import sys
import time
import urllib.parse
import urllib.request

ORB_LAT, ORB_LON = 59.2237, 15.0380
RADIUS_KM = float(os.environ.get("RADIUS_KM", "2000"))
TYPES = os.environ.get("TYPES", "B762,B763,B764")
CARGO_ONLY = os.environ.get("CARGO_ONLY", "1") == "1"
MAX_ANGLE_DEG = float(os.environ.get("MAX_ANGLE_DEG", "10"))
MAX_XTRACK_KM = float(os.environ.get("MAX_XTRACK_KM", "8"))
NEAR_KM = float(os.environ.get("NEAR_KM", "150"))
MAX_ALT_FT = int(os.environ.get("MAX_ALT_FT", "15000"))
DESCENT_FPM = int(os.environ.get("DESCENT_FPM", "-300"))
COOLDOWN_MIN = int(os.environ.get("COOLDOWN_MIN", "240"))
POLL_S = int(os.environ.get("POLL_S", "60"))
STATE = os.path.join(os.environ.get("STATE_DIR", "/data"), "alerted.json")
TG_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
TG_CHAT = os.environ.get("TELEGRAM_CHAT_ID", "")
DRY_RUN = os.environ.get("DRY_RUN", "") == "1"

# Operators that fly 767s only as freighters. Used only when FR24 gives no model text.
CARGO_AIRLINES = set(os.environ.get(
    "CARGO_AIRLINES",
    "FDX,UPS,ABX,ATN,CJT,DHK,DHL,BCS,DAE,AZG,MSX,LCO,LTG,CKS,NCR,GEL,AJT,WGN,SWG,ASL,ABR,TAY,"
    "SRR,CLX,MPH,JOS,GTI,EIA,CAO,CSS,YTO,SFX,PAC,AEC,CHZ,ICV,MSC,TMU,BOX",
).split(","))
CARGO_MODEL = re.compile(r"\d[0-9A-Z]{1,3}F\b|\((?:[^)]*\b)?(?:BCF|BDSF|SF|P2F|PCF|F)\b|freighter", re.I)

_lat_span = RADIUS_KM / 111.0
_lon_span = RADIUS_KM / (111.0 * math.cos(math.radians(min(ORB_LAT + _lat_span, 80))))
FEED = "https://data-cloud.flightradar24.com/zones/fcgi/feed.js?" + urllib.parse.urlencode({
    "bounds": f"{min(ORB_LAT + _lat_span, 89):.2f},{ORB_LAT - _lat_span:.2f},"
              f"{max(ORB_LON - _lon_span, -180):.2f},{min(ORB_LON + _lon_span, 180):.2f}",
    "faa": 1, "satellite": 1, "mlat": 1, "flarm": 1, "adsb": 1, "gnd": 0, "air": 1,
    "vehicles": 0, "estimated": 1, "maxage": 14400, "gliders": 1, "stats": 0,
    "type": TYPES, "limit": 5000,
})
DETAILS = "https://data-live.flightradar24.com/clickhandler/?version=1.5&flight="
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Safari/537.36"
R_KM = 6371.0
_details_cache = {}


def log(msg):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), msg, flush=True)


def get_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def dist_bearing(lat1, lon1, lat2, lon2):
    """Great-circle distance (km) and initial bearing (deg) from point 1 to point 2."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dl = math.radians(lon2 - lon1)
    a = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    d = 2 * R_KM * math.asin(math.sqrt(a))
    y = math.sin(dl) * math.cos(p2)
    x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return d, (math.degrees(math.atan2(y, x)) + 360) % 360


def evaluate(f):
    """Return a match dict for a feed row, or None if it does not qualify (cargo check excluded)."""
    lat, lon, track, alt, spd = f[1], f[2], f[3], f[4], f[5]
    dest, on_ground, vs = f[12], f[14], f[15]
    if dest or on_ground or spd < 40:
        return None
    d, brg = dist_bearing(lat, lon, ORB_LAT, ORB_LON)
    if d > RADIUS_KM:
        return None
    off = (brg - track + 540) % 360 - 180  # signed angle between track and bearing-to-ORB
    if abs(off) >= 90:
        return None  # airport is behind the aircraft
    xtrack = abs(d * math.sin(math.radians(off)))
    if abs(off) > MAX_ANGLE_DEG and xtrack > MAX_XTRACK_KM and d > MAX_XTRACK_KM:
        return None
    if d <= NEAR_KM and alt > MAX_ALT_FT and vs > DESCENT_FPM:
        return None
    along = d * math.cos(math.radians(off))
    eta_s = along / (spd * 1.852) * 3600
    return {"dist_km": d, "off_deg": off, "eta": time.time() + eta_s, "eta_min": eta_s / 60}


def details(fid):
    if fid not in _details_cache:
        try:
            _details_cache[fid] = get_json(DETAILS + fid)
        except Exception as e:
            log(f"details {fid} failed: {e!r}")
            return {}
    return _details_cache[fid]


def cargo_info(fid, f):
    """Return (is_cargo, model_text, airline_name)."""
    c = details(fid)
    model = ((c.get("aircraft") or {}).get("model") or {}).get("text") or ""
    airline = (c.get("airline") or {}).get("name") or ""
    by_model = bool(CARGO_MODEL.search(model))
    by_airline = (f[18] or "") in CARGO_AIRLINES
    return by_model or (not model and by_airline), model, airline


def fr24_link(fid, f):
    name = f[16] or f[13] or f[9] or "flight"
    return f"https://www.flightradar24.com/{urllib.parse.quote(name)}/{fid}"


def fmt_eta(m):
    eta = time.strftime("%H:%M", time.localtime(m["eta"]))
    mins = round(m["eta_min"])
    span = f"{mins // 60} h {mins % 60:02d} min" if mins >= 60 else f"{mins} min"
    return f"{eta} local (in {span})"


def message(fid, f, m, model="", airline=""):
    callsign = f[16] or f[13] or "(no callsign)"
    reg = f[9] or "?"
    origin = f[11] or "unknown"
    vs = f[15]
    trend = "descending" if vs < -100 else "climbing" if vs > 100 else "level"
    ac = model or f[8] or "?"
    who = f" · {airline}" if airline else ""
    return (
        f"📦✈️ {callsign} cargo 767 heading to Örebro (no destination filed)\n"
        f"{ac} · {reg}{who} · from {origin}\n"
        f"{m['dist_km']:.0f} km out, {f[4]} ft {trend} ({vs:+d} fpm), {f[5]} kt, "
        f"{abs(m['off_deg']):.0f}° off direct\n"
        f"ETA ORB ≈ {fmt_eta(m)}\n"
        f"{fr24_link(fid, f)}"
    )


def send(text):
    if DRY_RUN or not (TG_TOKEN and TG_CHAT):
        log("DRY " + text.replace("\n", " | "))
        return
    data = urllib.parse.urlencode({"chat_id": TG_CHAT, "text": text, "disable_web_page_preview": "true"}).encode()
    with urllib.request.urlopen(f"https://api.telegram.org/bot{TG_TOKEN}/sendMessage", data, timeout=20) as r:
        r.read()


def load_state():
    try:
        with open(STATE) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def save_state(state):
    tmp = STATE + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(state, fh)
    os.replace(tmp, STATE)


def tick(state):
    now = time.time()
    for k in [k for k, t in state.items() if now - t > COOLDOWN_MIN * 60]:
        del state[k]
    feed = get_json(FEED)
    live = {k for k, v in feed.items() if isinstance(v, list)}
    for k in [k for k in _details_cache if k not in live]:
        del _details_cache[k]
    for fid, f in feed.items():
        if not isinstance(f, list) or len(f) < 19:
            continue
        m = evaluate(f)
        if not m:
            continue
        key = f[0] or f[9] or fid  # ICAO hex survives FR24 flight-id changes
        if key in state:
            continue
        is_cargo, model, airline = cargo_info(fid, f)
        if CARGO_ONLY and not is_cargo:
            continue
        send(message(fid, f, m, model, airline))
        log(f"alert {fid} {f[16] or f[9]} {model} {m['dist_km']:.0f}km")
        state[key] = now
        save_state(state)


def main():
    once = "--once" in sys.argv
    log(f"orb-watch start types={TYPES} cargo_only={CARGO_ONLY} radius={RADIUS_KM}km "
        f"angle<={MAX_ANGLE_DEG}° dry={DRY_RUN or not TG_TOKEN}")
    state = load_state()
    while True:
        try:
            tick(state)
        except Exception as e:  # keep polling through network hiccups
            log(f"error: {e!r}")
        if once:
            return
        time.sleep(POLL_S)


if __name__ == "__main__":
    main()
