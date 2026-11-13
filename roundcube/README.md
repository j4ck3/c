# Private Roundcube for Outlook.com

This deployment uses Roundcube 1.7.4, the supported stable release checked on 2026-10-18. The official nonroot Apache image is pinned to its OCI index digest. It runs as UID/GID 33:33 with no published Docker ports and no public Traefik route.

## Access

Open https://mail.netbird.hjacke.com from a device connected to the authorized NetBird network. The existing tower Caddy proxy publishes HTTPS only on 100.113.194.104. Certificates use the existing Cloudflare DNS challenge, not a public HTTP listener. Roundcube also restricts direct backend requests to the proxy address, 172.25.0.23, and its local health check.

The installed `netbird expose` command creates a public reverse proxy service. It was not used because that would conflict with the requirement that the site remain unreachable outside NetBird. The existing NetBird connection and DNS already provide the private path.

## Complete Microsoft sign-in

Personal live.se mailboxes use Outlook.com OAuth2. A mailbox password is not enough. Run the guided setup on tower as root:

```bash
bash /mnt/user/documents/compose/roundcube/setup-microsoft.sh
```

The wizard opens or prints the Microsoft pages. It walks through these steps:

1. Enable IMAP in Outlook.com under Settings > Mail > Forwarding and IMAP. Leave POP disabled unless you need it.
2. Register an owned Microsoft Entra Web application that accepts personal Microsoft accounts. Microsoft may require Azure/tenant access and application-registration permissions. The wizard does not create subscriptions or billing resources.
3. Add this exact Web redirect URI:

   ```text
   https://mail.netbird.hjacke.com/index.php/login/oauth
   ```

4. Create a client secret, record its expiry, and enter its **Value**, not its secret ID, into the wizard's hidden prompt. Do not paste the secret or mailbox password into chat.
5. Save the application ID and secret locally, then sign in to Microsoft from the private Roundcube site. Microsoft redirects your browser to the private callback, so Microsoft does not need inbound access to the site.

The wizard stores its answers at `/mnt/cache/appdata/roundcube/secrets/.microsoft-oauth.env` with mode 0600. It also writes the two files Roundcube reads, `microsoft_client_id` and `microsoft_client_secret`, as root:33 with mode 0640. The directory is mounted read-only into the container. Secrets are not put in Compose or Docker environment variables. The application ID is public, but is kept beside the secret for consistent setup.

Until the app ID and secret exist, the page says "Microsoft setup required". Do not enter a mailbox password into that page. After provisioning, the login flow uses Microsoft only. The wizard does not claim success for mailbox access until you test it yourself.

## Mail connection

- IMAP: `outlook.office365.com:993`, implicit TLS, XOAUTH2.
- SMTP: `smtp-mail.outlook.com:587`, mandatory STARTTLS, XOAUTH2.
- OAuth audience: Microsoft consumer accounts.
- Delegated scopes: `https://outlook.office.com/IMAP.AccessAsUser.All`, `https://outlook.office.com/SMTP.Send`, `openid`, `profile`, `email`, and `offline_access`.
- TLS peer and hostname verification remain enabled. OAuth and protocol debug logs remain disabled.
- The intended mailbox identity must match the email claim Microsoft returns. A live.se alias may resolve to the account's primary address.

A first Microsoft sign-in, consent, inbox read, test send, and token refresh remain owner-dependent checks. App-secret expiry, revoked consent, or account restrictions can require another sign-in or secret rotation. A personal mailbox does not use Microsoft 365 tenant SMTP toggles.

## Persistence and operations

The server stack is [compose.yml](</mnt/user/documents/compose/roundcube/compose.yml>). Application data is on the local cache filesystem, not shared network storage:

- `/mnt/cache/appdata/roundcube/db` contains SQLite, preferences, contacts, and sessions.
- `/mnt/cache/appdata/roundcube/temp` contains uploads and temporary files.
- [des_key](</mnt/cache/appdata/roundcube/secrets/des_key>) contains the persistent AES-256 encryption key. The PHP configuration reads it explicitly and fails closed if it is missing or invalid. Do not print, replace, or discard it during an update.
- Mail messages and mailbox credentials remain with Microsoft. Roundcube stores encrypted OAuth/session data.

Use one container replica. SQLite is suitable for this small single-node deployment, not a multi-node shared-filesystem deployment.

```bash
docker compose -f /mnt/user/documents/compose/roundcube/compose.yml ps
docker compose -f /mnt/user/documents/compose/roundcube/compose.yml logs --tail 50
docker compose -f /mnt/user/documents/compose/roundcube/compose.yml restart
```

The health check runs inside the container and accepts either the unconfigured login page or the configured OAuth redirect. Apache access logs omit query strings and referrers. The local `private_log_redaction` plugin also replaces the current request's query string in Roundcube application logs. Its focused test uses artificial callback values only. A post-setup task copies this small plugin from a read-only source after the image extracts its built-in application files. Protocol and OAuth debug logs must remain disabled.

Before upgrades, stop Roundcube briefly and back up the entire data directory and the stack configuration to protected storage. Preserve the database and encryption key together. No automatic backup schedule was added. The container restarts unless explicitly stopped. Watchtower updates are disabled for this container, and the digest is pinned. Review Roundcube security releases and refreshed base images, then deliberately update the image and digest after a backup.

The proxy IP is checked by the backend as well as Roundcube's immediate-proxy setting. The Caddy container `dockhand-netbird-proxy` has the fixed address `ipv4_address: 172.25.0.23` in [netbird/docker-compose.yml](</mnt/user/documents/compose/netbird/docker-compose.yml>), so a restart keeps it. On 2026-10-22 the proxy restarted without a fixed address and moved from .22 to .23, and the site answered HTTP 403 until [apache-private.conf](</mnt/user/documents/compose/roundcube/apache-private.conf>) was updated. If the proxy address ever changes, update both files, then recreate Roundcube with `docker compose -f compose.yml up -d --force-recreate roundcube`. Do not edit `apache-private.conf` with `sed -i` and only reload Apache: the file is a single-file bind mount, `sed -i` replaces the file, and the container keeps the deleted original. Apache then loses the virtual host and serves the "configure your HTTP server" page. A mismatched address fails closed with HTTP 403. No broad firewall rules or other stacks were changed.

## Slate skin

The interface uses Slate, a local fork of Roundcube's Elastic skin stored in `skins/slate`. It is black and always dark, uses the self-hosted Inter font, and shows each message on one line: sender, subject and date, with the subject in bold and a dot when the message is unread. The mail toolbar shows Compose, Reply, Reply all, Delete and Move. Everything else (forward, archive, junk, mark read/unread/flagged, copy, print, export, view source) sits in the `...` menu, which a right-click on a message also opens. On phones a bottom bar switches between Inbox, Junk and Settings.

How it is installed:

- [skins/slate](</mnt/user/documents/compose/roundcube/skins/slate>) is mounted read-only at `/opt/slate`. The post-setup task [install-slate-skin.sh](</mnt/user/documents/compose/roundcube/install-slate-skin.sh>) copies it into `/var/www/html/skins/slate` on every start, after the image has extracted its own files.
- [95-slate-skin.php](</mnt/user/documents/compose/roundcube/config/95-slate-skin.php>) selects the skin, locks the skin choice, sorts by date, sets `archive_mbox` to `Archive`, and puts the junk buttons in the menu. `ROUNDCUBEMAIL_SKIN` stays `elastic`, because the entrypoint would otherwise try to install a missing skin with composer before the post-setup task runs.
- The `markasjunk` plugin is enabled. With no learning driver it only moves messages between Inbox and Junk. The separate `mail-filter` stack (/mnt/user/documents/compose/mail-filter/README.md) watches those moves: "Not junk" allowlists the sender and "Junk" blocklists it.

To change the skin, edit the source and run `skins/slate/build.sh` (needs Node with `less`, `less-plugin-clean-css` and `terser`), then restart the container. Roundcube serves the minified files. [CHANGES-SLATE.md](</mnt/user/documents/compose/roundcube/skins/slate/CHANGES-SLATE.md>) lists every file that differs from Elastic; diff against the new Elastic before a Roundcube upgrade.

Rollback: move `config/95-slate-skin.php` out of `config/` and recreate the container. Elastic is still installed. The stack backup taken before the change is in `backups/stack-before-slate-*.tgz`; the database snapshot is in `/mnt/cache/appdata/roundcube/backups/`.

During start the log shows `Failed to load plugin file .../private_log_redaction.php` once. The database step runs before the post-setup tasks copy the plugin in; this happened before Slate as well and requests afterwards load the plugin.

## Faster message opening (prefetch and cache)

Opening a message that is not preloaded takes about 0.75 s on the server (measured on 2026-10-22 against the live mailbox, 15 runs): TLS connect 0.17 s, XOAUTH2 sign-in 0.30 s, folder select 0.07 s, message fetch 0.20 s. Slow runs reach 1-2 s, and one earlier run took 6.3 s, mostly in the Outlook sign-in. Every Roundcube request opens a new IMAP connection, so this cost repeats on every click. Two changes speed this up.

**Prefetch in the browser** (`skins/slate/slate-prefetch.js`). Slate loads likely-next message previews into hidden iframes. When the list loads it preloads the first three rows and then unread messages in list order, eight in total. On top of that come the row under the pointer after 150 ms (on touch screens, on touch start) and the next and previous rows around the open message. At most twelve previews are kept and three load at once. A preview is dropped after 30 minutes, or when its row leaves the list after the one-minute refresh, which catches mail moved from another device. All previews are dropped when the list changes (folder switch, refresh, search, move, delete, archive, junk). When you open a preloaded message, the ready frame replaces the reading pane. In a local test with 1 s of added sign-in delay, opening took about 25 ms for preloaded messages and about 1.6 s for others.

`slatePrefetch.stats()` in the browser console shows recent open times: `hit` = preloaded, `waited` = preload still loading, `miss` = normal load. `slatePrefetch.cache()` lists the current preloads.

**No side effects from prefetch** (`plugins/slate_prefetch`). Prefetch requests carry `_prefetch=1`. For them the plugin turns off the read flag and read receipts and keeps remote images blocked. Slate marks a message as read when you actually open it, following the user's "mark as read" delay setting. A preview that would ask for a read receipt is not kept and loads normally on click. The plugin is copied in by the post-setup task `install-slate-prefetch.sh`.

**IMAP index cache** (`config/96-cache.php`). Roundcube caches folder lists and message indexes in `roundcube-redis` (redis:7-alpine, digest pinned): memory only, 64 MB with LRU eviction, no ports, on the internal `cache` network. Message bodies are not cached because Outlook.com lacks QRESYNC/CONDSTORE, which Roundcube's message cache needs. If Redis is down, Roundcube works without a cache.

Check prefetch in the browser console with `slatePrefetch.cache()`. Rollback: remove `slate_prefetch` from `ROUNDCUBEMAIL_PLUGINS`, move `config/96-cache.php` out of `config/`, and recreate the stack. Without the plugin, Slate still preloads, but those previews would mark messages as read, so remove both or neither. The backups from before this change are `backups/stack-before-prefetch-*.tgz` and `/mnt/cache/appdata/roundcube/backups/sqlite-before-prefetch-*.db`.

## OTP cleanup job

A daily job moves one-time-code mails that arrived more than five minutes ago to the trash. It runs at 10:00 as the Unraid User Script `otp_cleanup` and checks every folder of the live.se mailbox except Sent, Drafts and Trash.

A mail counts as an OTP mail only when both checks pass:

- the subject contains a code keyword (kod, engångskod, säkerhetskod, verifieringskod, verifikationskod, inloggningskod, bekräfta, code, verification, OTP, security code, sign-in, login, 2FA, confirm, passcode), and
- the text has a standalone 4-8 digit code (or `123 456` / `123-456`) within 120 characters of a code word. A code in the subject, such as "428193 is your Instagram code", also counts.

One-time sign-in links count too, for example Claude's "Your secure link to Claude is here". These need a link keyword in the subject (secure link, sign-in link, magic link, login link, inloggningslänk, säker länk) and text that both mentions signing in and says the link expires. Receipts and subscription mails from the same sender do not match.

Order numbers with `#`, dates, amounts, longer numbers and numbers inside links do not match. Security notices ("En ny inloggning identifierades", "unusual sign-in", password changed) are never moved. Daily runs look at mail from the last three days; `--all` scans everything. `--verbose` also logs rejected subject candidates and why a mail matched, with digits masked. Both read and unread mails are moved. The log at `/mnt/cache/appdata/otp-cleanup/logs/otp-cleanup.log` records time, folder, sender and subject, never the code or body.

Files:

- `/mnt/cache/appdata/otp-cleanup/run.sh`: starts the job in a throwaway `python:3.12-alpine` container (read-only, no capabilities). Unraid's own python3 cannot do HTTPS because its ssl module needs the missing `libssl.so.1.1`.
- `/mnt/cache/appdata/otp-cleanup/otp_cleanup.py`: the job (Python standard library only). `test_otp_cleanup.py` holds the detector tests.
- `/mnt/cache/appdata/otp-cleanup/config.env`: `MODE=dry-run` only logs; `MODE=move` moves. `ACCOUNT` can stay empty.
- `/mnt/cache/appdata/otp-cleanup/token.json` (mode 0600): the refresh token from the one-time sign-in. It reuses the Roundcube Entra app ID and no client secret.
- `/boot/config/plugins/user.scripts/scripts/otp_cleanup/script`: the User Scripts wrapper with a lock and log rotation. The schedule is in `schedule.json` and `customSchedule.cron`; the copies from before the change end in `.before-otp`.

The one-time sign-in uses a Microsoft device code, which needs **Allow public client flows = Yes** on the Entra app (Authentication page). Then run as root on tower:

```bash
/mnt/cache/appdata/otp-cleanup/run.sh --login
/mnt/cache/appdata/otp-cleanup/run.sh --dry-run --all --verbose
```

Outlook.com closes the IMAP connection on long `OR` searches, so the job searches one subject term at a time. The token response has no email claim, so `ACCOUNT` in `config.env` holds the mailbox address.

If Microsoft revokes the token (password change, removed consent, 90 days without a run), the log shows `Token refresh failed`; run `--login` again. To stop the job, set its schedule to Disabled in User Scripts.

## Remove the deployment

Remove only the `mail.netbird.hjacke.com` block from [dockhand-netbird.Caddyfile](</mnt/user/documents/compose/netbird/dockhand-netbird.Caddyfile>), validate and reload Caddy, then stop/remove this stack:

```bash
docker exec dockhand-netbird-proxy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker exec dockhand-netbird-proxy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
docker compose -f /mnt/user/documents/compose/roundcube/compose.yml down
```

The pre-change proxy backup is [Caddyfile.before-roundcube-20261018](</mnt/user/documents/compose/netbird/backups/Caddyfile.before-roundcube-20261018>). Restore the whole backup only if no other proxy edits have occurred since then. Stopping the stack does not delete application data. Do not delete data or revoke the Microsoft application unless you intend to lose sessions or remove its access.

## Sources

- https://roundcube.net/download/
- https://hub.docker.com/v2/repositories/roundcube/roundcubemail/tags/1.7.4-apache-nonroot
- https://docs.netbird.io/manage/reverse-proxy/expose-from-cli
- https://support.microsoft.com/en-us/outlook/pop-imap-and-smtp-settings-for-outlook-com
- https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app
- https://learn.microsoft.com/en-us/entra/identity-platform/how-to-add-credentials
- https://learn.microsoft.com/en-us/exchange/client-developer/legacy-protocols/how-to-authenticate-an-imap-pop-smtp-application-by-using-oauth
