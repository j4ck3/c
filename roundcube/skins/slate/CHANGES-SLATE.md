# Slate changes relative to Elastic (Roundcube 1.7.4)

Slate started as a copy of `skins/elastic` from the official `roundcube/roundcubemail:1.7.4-apache-nonroot` image. It does not set `extends`, so it keeps working if Elastic changes in a later release. Upgrades still need a diff against the new Elastic.

## Files changed

- `meta.json`: name, black theme colour, `dark_mode_support` off, skin localization on.
- `templates/includes/layout.html`: `<html>` always has `dark-mode slate`; the colour-mode cookie script is gone. Print pages stay light.
- `templates/includes/menu.html`: task menu kept for Roundcube's commands but hidden on desktop and tablet; a phone bottom bar (Inbox, Junk, Settings) is added.
- `templates/includes/mail-menu.html`: toolbar reduced to Compose, Reply, Reply all, Delete, Move and a more menu. The more menu holds forward, archive, junk, mark read/unread/flagged, copy, forward and reply options, print, export, edit as new, source, new window and import.
- `templates/mail.html`: account header with compose, main-folder sidebar with Settings and Logout, list header with refresh and options menu, All/Unread/Flagged filter pills.
- `templates/compose.html`: options sidebar removed; options open in a dialog from the more menu, attachments list below the body, Cc and Bcc as text links.
- `templates/includes/settings-menu.html`, `addressbook.html`, `error.html`: back-to-mail button instead of the task menu button.
- `templates/includes/footer.html`: loads `slate.js` after `ui.js`.
- `ui.js`: `color_mode_init()` always selects dark mode; `toolbar_init()` skips `.slate-toolbar` so the mail and compose toolbars stay inline on small screens.
- `slate.js` (new): one-line message rows, hover actions (delete, move, mark unread/read) in place of the date, compact dates, filter pills, folder grouping, plugin buttons moved into the more menu, right-click menu, bottom bar state and badges, compose options dialog.
- `slate-prefetch.js` (new): preloads message previews in hidden iframes and swaps the ready frame in on open; works with the `slate_prefetch` plugin.
- `ui.js` also exports `UI.bind_content_frame()` and keeps the content-frame load handler in `env.content_frame_load`, so a swapped-in frame gets the same layout handling.
- `styles/_variables.less` (new): Inter 13px, 28px list rows, black palette, accent `#5e6ad2`.
- `styles/_styles.less` (new): all Slate layout and component styles.
- `styles/global.less`, `styles/mixins.less`: Roboto replaced by self-hosted Inter 4.1.
- `watermark.html`: empty black page.
- `localization/`: month abbreviations for list dates.

## Build

`./build.sh` compiles the LESS files and minifies `ui.js` and `slate.js`. It needs `lessc` with `less-plugin-clean-css` and `terser`. Roundcube serves `*.min.css` and `*.min.js` when present, so rebuild after every change.
