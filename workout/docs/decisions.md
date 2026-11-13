# Workout app: decisions

Last updated 2026-11-11.

## Scope

- Personal app for one user (Jacob). No multi-user accounts.
- Lifting only. No cardio, GPS or heart-rate tracking.
- Bodyweight tracking is in scope: daily weigh-ins with a 7-day moving-average trend.
- UI language: English. Units: kg only (no lb toggle).
- The app is Jacob's own calendar. Events live in this app, not in Google or iCloud.
- One codebase serves both a normal web app (desktop and mobile browsers) and an installable PWA on iPhone.
- Hosted on tower (Unraid) in Docker, under `/mnt/user/documents/compose/workout`.

## Stack

| Layer | Choice | Reason |
|---|---|---|
| Frontend | Vite + React + TypeScript + Tailwind | Same skills as other projects; SPA is enough for one user |
| PWA | vite-plugin-pwa (Workbox) | Service worker, offline app shell, install manifest |
| Local data | Dexie (IndexedDB) | Logging a set never waits on the network |
| Routing / server state | TanStack Router + TanStack Query | Typed routes, cache and sync status |
| Charts | Apache ECharts 6 via `echarts/core` + echarts-for-react | See `research/chart-libraries.md` |
| Calendar UI | Schedule-X | MIT, React adapter, drag and drop |
| Recurrence | rrule.js (RFC 5545) | Repeating events with exceptions |
| Backend | Bun + Hono | Small, typed, matches the hstab container pattern |
| Database | SQLite + Drizzle | One file, easy nightly backup |
| Reminders | Web Push (VAPID) | Works on iOS 16.4+ when installed to the home screen |
| Calendar export | Read-only ICS feed | Lets iPhone Calendar show events and alarms |

## iPhone constraints that shape the design

- Push notifications only work after "Add to Home Screen".
- No background sync on iOS. Sync runs when the app opens or regains focus.
- Safari may evict local storage for unused sites. The server copy is the source of truth for backup.
- No HealthKit or Bluetooth access from a PWA.

## Exposure and hosting

- Reachable only over NetBird at `https://workout.netbird.hjacke.com`, the same pattern as hstab.
- The app has no login. Caddy (dockhand-netbird-proxy) returns 403 to any client outside `100.113.0.0/16`.
- DNS already resolves the name to the proxy (`100.113.194.104`) through the existing wildcard. Caddy obtains the certificate with the Cloudflare DNS challenge.
- Consequences: the iPhone needs NetBird connected to sync and to refresh the ICS subscription. Web Push still arrives without NetBird, because Apple's push service delivers it.
- Data lives in `/mnt/user/appdata/workout/` (SQLite file), included in the nightly backup.
- Moving to public access later requires adding a login (passkey) and rate limiting.
