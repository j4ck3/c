# mail-filter: Junk rescue for the live.se mailbox

Outlook.com sends a lot of legitimate mail to Junk. A header scan on 2026-10-26 found 29 Junk mails from the previous 90 days. Microsoft gave every one of them SCL 5, and at least 8 were real mail that passed DMARC: the RJHDESIGN shop, Aquatuning orders, Microsoft Security, Enable Banking and Claude sign-in links, and Weekday. Microsoft's verdict carries no usable confidence, so this job overrides it for senders you already know.

The container `mail-filter` runs [mail_filter.py](mail_filter.py) every 5 minutes. It fetches headers only (`BODY.PEEK`, so read flags do not change) from Inbox and Junk for the last 30 days. It never reads message bodies.

## Rules

A Junk mail moves to Inbox when both of these hold:

1. **Authenticated for its own domain.** Microsoft's `Authentication-Results` shows `dmarc=pass`, or `dkim=pass` / `spf=pass` for the same organisational domain as the From address. Spoofed mail ("Svensk polisstation" from a hijacked mailbox, phishing that copies a brand name) fails this test.
2. **Known sender.** The sender is in `allow.txt`, or appears in any kept folder. Kept folders include Inbox, Archive, kvitton, Pågen, the receipt folders, and the recipients in Sent. Junk, Deleted, Trash, Drafts and Outbox do not count.

An Inbox mail moves to Junk only when its sender is in `block.txt`. The blocklist also overrides rescue.

Gmail, Hotmail, Outlook, Live, Yahoo, mail.ru and similar shared providers are matched per address and never per domain. Every other sender is matched by organisational domain, so `weekday.com` covers `mail1.weekday.com`.

## Learning from Roundcube

`state.json` records which folder each Message-ID was last seen in. When you move a mail yourself:

- Junk → Inbox ("Not junk" in Roundcube, or a move from any other client) adds the sender's domain, or the full address for shared providers, to `allow.txt` and removes it from `block.txt`.
- Inbox → Junk ("Junk" in Roundcube) adds the sender's address to `block.txt` and removes it from `allow.txt`. To block a whole domain, edit the file by hand.

The job records its own moves before it makes them, so they are not read as your verdicts. Learning takes effect on the next run, within 5 minutes.

## Files

- `/mnt/user/documents/compose/mail-filter/compose.yml`: the stack, using a digest-pinned `python:3.12-alpine` with a read-only root filesystem and no capabilities.
- `/mnt/cache/appdata/mail-filter/config.env`: `MODE=move` moves mail; `MODE=dry-run` only logs. Restart the container after a change.
- `/mnt/cache/appdata/mail-filter/allow.txt` and `block.txt`: one domain or address per line, with `#` comments. You can edit these while the job runs. The seed entries from 2026-10-26 are marked `seed`.
- `/mnt/cache/appdata/mail-filter/state.json`: last folder per Message-ID, pruned after 45 days.
- [test_mail_filter.py](test_mail_filter.py): unit tests for the decision rules.

## Sign-in

The job reuses the otp-cleanup refresh token in `/mnt/cache/appdata/otp-cleanup/token.json` and its OAuth/IMAP helpers (`otp_cleanup.py`, mounted at `/otp`). It takes `ACCOUNT` from `otp-cleanup/config.env`. It holds an access token for 45 minutes and refreshes it under a file lock. If Microsoft revokes the token, both jobs log `Token refresh failed`; run `/mnt/cache/appdata/otp-cleanup/run.sh --login` once to fix both.

## Operations

```bash
cd /mnt/user/documents/compose/mail-filter
docker logs --tail 50 mail-filter          # MOVE / LEARN lines; quiet runs print nothing
docker compose restart                     # after editing config.env or mail_filter.py
docker compose run --rm mail-filter python3 /app/mail_filter.py --dry-run   # one run, logs only
docker compose run --rm mail-filter python3 /app/mail_filter.py --known     # print the known-sender set
docker run --rm --read-only --tmpfs /tmp -e OTP_CLEANUP_DIR=/otp -v /mnt/cache/appdata/otp-cleanup:/otp:ro -v "$PWD":/app:ro python:3.12-alpine python3 /app/test_mail_filter.py
```

## Limits

- A spam sender left in Inbox becomes a known sender, so its later mail would be rescued from Junk. Marking that mail as Junk puts the sender on the blocklist and stops this.
- First-time senders are never rescued, because no reputation exists for them yet. If one lands in Junk, click "Not junk" once and its later mail is rescued.
- Rescue runs every 5 minutes, so a rescued mail sits in Junk for up to 5 minutes first.
- No content filter (rspamd or Bayes) runs here. At roughly 10 Junk mails a month, a Bayes classifier would need more than a year of training before it activated.

## Remove

```bash
docker compose -f /mnt/user/documents/compose/mail-filter/compose.yml down
```

Mail that was already moved stays where it is. The lists and state in `/mnt/cache/appdata/mail-filter` remain until you delete them.
