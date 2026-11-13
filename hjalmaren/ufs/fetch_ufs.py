"""Fetch Ufs notices (Underrättelser för sjöfarande) for chart 114 Hjälmaren.

Writes a compact JSON file for the map page: number, date, title, type,
situation time, positions and a link back to the notice on ufs.sjofartsverket.se.
Reads only the public Ufs web pages; the licensed Ufs map service is not used.
"""
import datetime as dt
import html
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

BASE = "https://ufs.sjofartsverket.se"
CHART_ID = "23"          # Ufs internal id for chart 114 Hjälmaren
YEARS_BACK = 3
OUT = sys.argv[1] if len(sys.argv) > 1 else "ufs.json"
UA = "hjalmaren-karta/1.0 (personal use)"

def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8", "replace")

def text(s):
    s = re.sub(r"<br\s*/?>", "\n", s)
    s = re.sub(r"<[^>]+>", " ", s)
    return re.sub(r"[ \t]+", " ", html.unescape(s)).strip()

def search():
    end = dt.date.today()
    start = end.replace(year=end.year - YEARS_BACK)
    q = urllib.parse.urlencode({
        "SearchFormModel.ChartNumbers": CHART_ID,
        "SearchFormModel.SearchTimePeriod": "1000",
        "SearchFormModel.StartDate": start.isoformat(),
        "SearchFormModel.EndDate": end.isoformat(),
    })
    page = get(f"{BASE}/Notice/Search/?{q}")
    rows = []
    # Two tables: notices for the chart, and general announcements.
    for section in re.split(r'<h5 class="mt-4">', page)[1:]:
        heading = text(section.split("</h5>", 1)[0])
        general = heading.startswith("Tillk")
        for href, num, charts, date, title in re.findall(
            r'<tr[^>]*>\s*<th[^>]*><a href="([^"]+)"[^>]*>([^<]+)</a></th>\s*<td>(.*?)</td>\s*<td[^>]*>([^<]*)</td>\s*<td>(.*?)</td>',
            section, re.S):
            num = html.unescape(num).strip()
            rows.append({
                "id": re.sub(r"\D.*", "", num),
                "number": num,
                "temporary": "(T)" in num,
                "preliminary": "(P)" in num,
                "general": general,
                "charts": text(charts).replace("\n", " / "),
                "published": date.strip(),
                "title": text(title),
                "url": BASE + html.unescape(href).split("&from=")[0],
            })
    return rows

POS = re.compile(r"(\d{2})-(\d{2}),(\d{1,3})N\s*(\d{3})-(\d{2}),(\d{1,3})E")

def detail(row):
    page = get(row["url"])
    main = page[page.find("<main"):]
    body = text(main)
    def field(label):
        m = re.search(label + r"\s*:\s*([^\n]+?)(?:\s{2,}|\n|$)", body)
        return m.group(1).strip() if m else ""
    row["kind"] = field("Typ av notis")
    row["situation"] = field("Situationstid")
    m = re.search(r"Sjöfartsverket\.\s*Publ\.[^\n]*", body)
    row["publisher"] = m.group(0).strip() if m else ""
    # Positions: degrees-minutes with decimal minutes, e.g. 59-10,85N 015-45,00E.
    pts = []
    for d1, m1, f1, d2, m2, f2 in POS.findall(body):
        lat = int(d1) + float(f"{m1}.{f1}") / 60
        lon = int(d2) + float(f"{m2}.{f2}") / 60
        pts.append([round(lat, 6), round(lon, 6)])
    row["positions"] = pts
    # Short action list: "Inför undervattenssten", "Ändra 3 meter djupkurva" ...
    actions = re.findall(r"\b(Inför|Ändra|Stryk|Flytta|Ersätt|Släckt|Tänd|Indragen|Utlagd)\b\s*\n?\s*([^\n]{2,80})", body)
    row["actions"] = [f"{a} {b.strip()}" for a, b in actions][:20]
    m = re.search(r"Bsp [^\n]*\n\s*([^\n]{10,200})\n\s*Sjöfartsverket\. Publ", body)
    row["summary"] = m.group(1).strip() if m else ""
    return row

def previous_count():
    try:
        with open(OUT, encoding="utf-8") as f:
            return len(json.load(f).get("notices", []))
    except (OSError, ValueError):
        return 0

def main():
    rows = search()
    # An empty result almost always means Ufs changed its HTML, not that every notice
    # was withdrawn. Keep the last good file instead of silently emptying the map.
    if not rows and previous_count():
        print(f"0 notices parsed (had {previous_count()}); keeping {OUT}", file=sys.stderr)
        sys.exit(1)
    out = []
    for r in rows:
        try:
            out.append(detail(r))
        except Exception as e:
            r["error"] = str(e)
            out.append(r)
        time.sleep(1)
    failed = sum(1 for r in out if "error" in r)
    if out and failed == len(out) and previous_count():
        print(f"all {failed} notice pages failed; keeping {OUT}", file=sys.stderr)
        sys.exit(1)
    out.sort(key=lambda r: r["published"], reverse=True)
    data = {"fetched": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
            "source": BASE, "chart": "114 Hjälmaren", "notices": out}
    tmp = OUT + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    os.replace(tmp, OUT)
    print(f"{len(out)} notices -> {OUT}")

if __name__ == "__main__":
    main()
