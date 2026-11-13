# orb-watch: Telegram alerts for destination-less 767 freighters heading to Örebro

The container `orb-watch` runs [orb_watch.py](orb_watch.py) every 60 seconds. It polls the public Flightradar24 web feed (`data-cloud.flightradar24.com/zones/fcgi/feed.js`), filtered server-side to Boeing 767 types (`B762,B763,B764`), for a box that covers 2000 km around Örebro airport (ORB/ESOE, 59.2237 N 15.0380 E).

## Alert rule

An aircraft triggers a Telegram message when all of these hold:

1. It is airborne, faster than 40 kt, and FR24 lists no destination.
2. It is within `RADIUS_KM` (2000 km) of ORB.
3. Its track points at ORB: the airport is ahead, and the angle between its track and the great-circle bearing to ORB is at most `MAX_ANGLE_DEG` (10°). Close in, a cross-track distance of at most `MAX_XTRACK_KM` (8 km) also counts.
4. Inside `NEAR_KM` (150 km) it is at or below `MAX_ALT_FT` (15000 ft) or descending faster than `DESCENT_FPM` (−300 fpm). This drops high-level overflights near ORB. Farther out, cruise altitude is allowed.
5. It is a freighter. For candidates only, the script fetches FR24's flight details. The aircraft counts as cargo when the model text names a freighter variant (`767-3xxF`, `BCF`, `BDSF`, `SF`, `P2F`, `Freighter`). If FR24 returns no model text, the operator's ICAO code is checked against `CARGO_AIRLINES` instead. Set `CARGO_ONLY=0` to alert on every 767.

The message gives callsign, model, registration, operator, origin, distance, altitude, vertical speed, ground speed, angle off the direct course, the FR24 link, and the ETA in local time (CET/CEST). The ETA is the along-track distance divided by current ground speed. From 2000 km out it ignores winds, descent and routing, so treat it as rough.

Each aircraft (keyed by ICAO hex) alerts once per `COOLDOWN_MIN` (240 min). State is kept in `/mnt/cache/appdata/orb-watch/alerted.json`.

## Files

- `compose.yml`: digest-pinned `python:3.12-alpine`, read-only root, no capabilities.
- `.env`: `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID`, copied from `../backup/.env` (the homeserver_ntfy_bot). Any threshold above can also be set here; run `docker compose up -d` after a change.
- Set `DRY_RUN=1` to log alerts instead of sending them.

## Operations

- Logs: `docker logs -f orb-watch`. Each alert is logged as `alert <flight-id> <callsign> <model> <km>`.
- FR24 rate-limits the details endpoint (HTTP 429) when it is called many times in a row. The script only calls it for aircraft that already pass rules 1–4, which is rarely more than one at a time.
- The feed endpoints are unofficial. If FR24 changes or blocks them, the log shows `error:` lines every minute.
