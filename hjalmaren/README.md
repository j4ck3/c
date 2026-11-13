# Hjälmaren – sjömärkeskarta

Statisk karta över Hjälmaren som visar sjömärken, stenar, djupkurvor och ortnamn.
Sidan ligger bakom basic auth på https://hjalmaren.hjacke.com/ (inget indexeras) och
är avsedd för privat bruk.

## Var datat kommer ifrån

| Data | Källa | Vad vi gör |
|---|---|---|
| Sjökort (S‑57) | Sjöfartsverket, paketerat som vektorkakel av Skippo: `onlinemaps.skippo.cloud/20260706_s57/{z}/{x}/{y}.mvt` | Speglat till `site/tiles/s57/`, zoom 4–14, Hjälmarens utbredning |
| Baskarta under zoom 9 | Skippos OSM‑kakel: `onlinemaps.skippo.cloud/osm_20260326/{z}/{x}/{y}.mvt` | Speglat till `site/tiles/osm/`, zoom 0–8 |
| Kartstil | Skippos Mapbox‑stilar `mapresources.skippo.cloud/20260706/style/{light,night}.json` | Omarbetade till MapLibre i `site/style.json` (dag) och `site/style-night.json` (natt) |
| Typsnitt och symboler | `mapresources.skippo.cloud/20260706/{glyphs,sprite}` | Speglade till `site/glyphs/` och `site/sprite-v2/` |
| Ufs‑notiser | `ufs.sjofartsverket.se` via `ufs/fetch_ufs.py` | Hämtas var 6:e timme till `site/data/ufs.json` |

Datumbeteckningen `20260706` är Skippos utgåva av sjökortet. När de släpper en ny
behöver kaklen speglas om och stilen byggas om.

## Filer

- `site/index.html` – kartan (MapLibre GL, panel för lager och Ufs‑notiser, GPS‑knapp, vyn sparas i adressen som `#zoom/lat/lon`)
- `site/style.json` – MapLibre‑stil, genererad av `build_style.py`. Redigera inte för hand.
- `site/tiles/` – speglade vektorkakel (cirka 20 MB)
- `site/glyphs/`, `site/sprite-v2/` – typsnitt och symboler
- `site/sprite-night/` – Skippos nattsymboler (`/20260706/sprite/night/`) för mörkt läge
- `site/vendor/v6.17.0/` – MapLibre GL JS 6.17.0 (ES-modul + worker). Uppgradera genom att lägga en ny version i en ny katalog och ändra sökvägen i `index.html`; katalognamnet är cache-versionen. 4.7.1 ligger i `archive/`.
- `site/data/ufs.json` – Ufs‑notiser, skrivs av containern `hjalmaren-ufs`
- `site/data/sjomarken.geojson` – alla sjömärken ur kaklen, med `HJ_TOPMARK`/`HJ_LIGHT` för filtret i lagerpanelen. Byggs av `build_marks.py`.
- `nginx/default.conf` – cachning och gzip (kakel serveras som `application/x-protobuf` så att de komprimeras)
- `mirror_tiles.py` – speglar kaklen
- `build_style.py` – bygger om stilen från `skippo_style_light.json`, byter Skippos engelska etiketter mot svenska och ritar sjömärkena från `sjomarken.geojson`
- `build_marks.py` – plockar ut bojar, prickar, toppbeteckningar, ljus och fyrar ur zoom‑14‑kaklen och kopplar ihop dem (i kaklen är toppbeteckning och ljus egna punkter på samma koordinat som bojen, vilket ett kartfilter inte kan koppla ihop)
- `ufs/fetch_ufs.py` – hämtar Ufs‑notiserna. Ger den 0 notiser behålls den förra filen.
- `fetch_skipper.py`, `build_data.py` – äldre pipeline för Leaflet‑versionen, används inte av kartan
- `archive/` – gamla sidversioner, nedladdningsfilerna (`filer/`) och säkerhetskopior. Serveras inte.

## Uppdatera

```sh
python3 mirror_tiles.py                      # ladda ner nya kakel
cat /tmp/hj_mirror_jobs.txt | xargs -P 14 -n 2 bash -c 'curl -s -m 60 --retry 3 -o "$0" "$1"'
docker run --rm -v "$PWD":/w -w /w python:3.12-slim \
  sh -c 'pip -q install mapbox-vector-tile shapely && python build_marks.py'   # sjömärken + filterdata
# byt VERSION i build_style.py (t.ex. till dagens datum), sedan:
python3 build_style.py                       # bygg om stilen
```

Kakel, typsnitt och symboler cachas i webbläsaren i 30 dagar (`immutable`). Utan ny
`VERSION` i `build_style.py` ser besökarna det gamla sjökortet tills cachen går ut. Byts
spriten, lägg den i en ny katalog (`sprite-v3`) och ändra sökvägen i `build_style.py`.

## Mörkt läge

Överst i lagerpanelen väljs tema: Auto (följer systemet), Ljust eller Mörkt. Mörkt läge
byter sjökortet till Skippos nattstil (svart vatten, röd‑lila grund, för att bevara
mörkerseendet) och panelerna till mörka färger. Valet sparas i webbläsaren och sätts
innan sidan ritas, så den blinkar inte ljus först. `build_style.py` bygger båda stilarna.

## Lagerpanelen

Under "Bojar, prickar och fyrar" finns ett filter: Alla, Med toppbeteckning, Med ljus,
Med båda. Toppbeteckningar och ljuspunkter följer med sin boj, så "Med ljus" visar bojen,
dess ljussymbol och ljusbeteckningen. Valet sparas i webbläsaren.

"Bara i vattnet" döljer märken som står på land: fyrar på holmar och ensmärken på
stranden (30 av 431). Ett märke räknas som i vattnet när det ligger i en djupyta, ett
muddrat område, en å eller en sjö i sjökortet och inte på en landyta (`HJ_WATER` i
`sjomarken.geojson`). Alla bojar ligger i vattnet; det som försvinner är fyrar och prickar
med ljus, så "Med ljus" går från 78 till 51.

Varje stillager hör till en grupp i `groupOf()` i `index.html`. Land och strandlinje
syns alltid. "Farleder, vrak, hinder, kablar, fartgränser" är allt övrigt i sjökortet;
det får inte hamna i "Bakgrund", annars försvinner farorna när bakgrunden döljs.

## Rättigheter

Sjökortet tillhör Sjöfartsverket och kaklen/stilen är Skippos bearbetning. Materialet
används här enbart privat, på en sida som kräver inloggning och som är märkt `noindex`.
Sidan får inte göras publik eller användas kommersiellt utan tillstånd.

## Typsnitt: speglade teckenintervall

MapLibre hämtar ett glyph-intervall (`{range}.pbf`) för varje tecken i en etikett. Saknas
intervallet (404) misslyckas layouten för hela kaklet, och rutan ritas tom (vit fyrkant).
Speglade intervall: `0-255`, `256-511`, `512-767`, `768-1023`, `1024-1279` (kyrilliska i
OSM-namn) och `8192-8447` (tankstreck "—" i datumen för naturreservat, t.ex. vid
Grundholmarna). Lägg till nya intervall om kartan börjar visa nya tecken.
