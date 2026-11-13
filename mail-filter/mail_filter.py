#!/usr/bin/env python3
"""Junk rescue and sender learning for the live.se Outlook.com mailbox.

Every run (default every 5 minutes with --loop):

1. Learn from the owner's own moves. A message last seen in Junk that is now in
   Inbox (Roundcube "Not junk", or a move from any other client) puts its sender on
   the allowlist. A message last seen in Inbox that is now in Junk puts the sender on
   the blocklist. Moves made by this job are recorded first, so they are not
   mistaken for the owner's.
2. Rescue: a Junk message goes back to Inbox when its sender authenticates for its
   own domain (aligned DMARC, DKIM or SPF in Microsoft's Authentication-Results) and
   is known: allowlisted, a recipient in Sent, or a sender in a kept folder.
3. Block: an Inbox message whose sender is on the blocklist goes to Junk.

Only headers are fetched (BODY.PEEK, flags unchanged). Bodies are never read.
Sign-in reuses the otp-cleanup refresh token; see README.md.
"""
import argparse
import datetime as dt
import email
import email.policy
import email.utils
import fcntl
import json
import os
import re
import sys
import time

sys.path.insert(0, os.environ.get("OTP_CLEANUP_DIR", "/otp"))
import otp_cleanup as oc  # noqa: E402  (shared OAuth/IMAP helpers)

DATA = os.environ.get("MF_DIR", "/data")
CONFIG_FILE = os.path.join(DATA, "config.env")
STATE_FILE = os.path.join(DATA, "state.json")
ALLOW_FILE = os.path.join(DATA, "allow.txt")
BLOCK_FILE = os.path.join(DATA, "block.txt")
TOKEN_LOCK = os.path.join(os.environ.get("OTP_CLEANUP_DIR", "/otp"), ".token.lock")

LOOKBACK_DAYS = 30          # Inbox/Junk window checked each run
STATE_TTL_DAYS = 45         # forget message ids not seen for this long
KNOWN_REFRESH = 3600        # rebuild the known-sender set hourly
HEADERS = "FROM SUBJECT MESSAGE-ID AUTHENTICATION-RESULTS"

# Folders that do not say "the owner wants this sender".
NOT_KNOWN_SPECIAL = {"\\Junk", "\\Trash", "\\Drafts", "\\Noselect", "\\NonExistent", "\\All"}
NOT_KNOWN_PREFIXES = ("deleted", "trash", "junk", "outbox", "drafts", "notes", "scheduled",
                      "synkroniseringsproblem")

# Shared mail providers: trust is per address, never per domain.
FREEMAIL = {"gmail.com", "googlemail.com", "msn.com", "icloud.com", "me.com", "mac.com",
            "aol.com", "mail.ru", "proton.me", "protonmail.com", "pm.me", "tutamail.com",
            "tuta.io", "tutanota.com", "zoho.com", "mail.com", "inbox.lv", "bredband.net",
            "telia.com", "spray.se", "passagen.se"}
FREEMAIL_BRANDS = {"hotmail", "outlook", "live", "yahoo", "gmx", "yandex", "web"}
# Generic second-level labels under country TLDs (co.uk, com.au, biz.id, mil.ec ...):
# there the registrable domain has three labels.
GENERIC_SLD = {"co", "com", "net", "org", "gov", "ac", "edu", "mil", "biz", "ne", "or", "go", "gob", "nic"}


def log(msg):
    print(dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S"), msg, flush=True)


# ---------- decisions (pure, unit-tested) ----------

def org_domain(domain):
    labels = [p for p in (domain or "").lower().strip(".").split(".") if p]
    if len(labels) < 2:
        return ".".join(labels)
    if len(labels) >= 3 and len(labels[-1]) == 2 and labels[-2] in GENERIC_SLD:
        return ".".join(labels[-3:])
    return ".".join(labels[-2:])


def is_freemail(domain):
    org = org_domain(domain)
    return org in FREEMAIL or org.split(".")[0] in FREEMAIL_BRANDS


def sender_key(addr):
    """List key for a sender: the address for shared providers, else the org domain."""
    addr = (addr or "").lower()
    if "@" not in addr:
        return None
    dom = addr.rsplit("@", 1)[1]
    return addr if is_freemail(dom) else org_domain(dom)


def auth_aligned(auth_results, from_addr):
    """True when Microsoft's top Authentication-Results shows the From domain authenticated.

    Accepts dmarc=pass, or dkim=pass / spf=pass whose domain shares the From org domain
    (covers dmarc=bestguesspass senders without a DMARC record).
    """
    if not auth_results or "@" not in (from_addr or ""):
        return False
    ar = auth_results.lower()
    from_org = org_domain(from_addr.rsplit("@", 1)[1])
    if re.search(r"\bdmarc=pass\b", ar):
        m = re.search(r"dmarc=pass[^;]*header\.from=([^\s;]+)", ar)
        if not m or org_domain(m.group(1)) == from_org:
            return True
    for m in re.finditer(r"\bdkim=pass\b[^;]*?header\.d=([^\s;]+)", ar):
        if org_domain(m.group(1)) == from_org:
            return True
    m = re.search(r"\bspf=pass\b[^;]*?smtp\.mailfrom=([^\s;]+)", ar)
    if m and org_domain(m.group(1).rsplit("@", 1)[-1]) == from_org:
        return True
    return False


def listed(addr, entries):
    """Entry match: exact address, or domain entry covering the sender's domain."""
    addr = (addr or "").lower()
    if not addr or "@" not in addr:
        return False
    if addr in entries:
        return True
    dom = addr.rsplit("@", 1)[1]
    if is_freemail(dom):
        return False
    return any(dom == e or dom.endswith("." + e) for e in entries if "@" not in e)


def rescue_reason(addr, auth_results, allow, block, known):
    """Why a Junk message should go to Inbox, or None to leave it."""
    if listed(addr, block):
        return None
    if not auth_aligned(auth_results, addr):
        return None
    if listed(addr, allow):
        return "allowlist"
    if listed(addr, known):
        return "known sender"
    return None


def learn(prev, now_folder, moved_by_job):
    """Owner verdict from a folder change: 'ham', 'spam' or None."""
    if moved_by_job or prev is None or prev == now_folder:
        return None
    if prev == "junk" and now_folder == "inbox":
        return "ham"
    if prev == "inbox" and now_folder == "junk":
        return "spam"
    return None


# ---------- lists and state ----------

def read_list(path):
    entries = set()
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.split("#", 1)[0].strip().lower()
                if line:
                    entries.add(line)
    return entries


def add_entry(path, entry, note):
    if entry in read_list(path):
        return False
    with open(path, "a", encoding="utf-8") as fh:
        fh.write("%s  # %s %s\n" % (entry, dt.date.today().isoformat(), note.replace("\n", " ")[:100]))
    return True


def remove_entry(path, entry):
    if not os.path.exists(path):
        return False
    with open(path, encoding="utf-8") as fh:
        lines = fh.readlines()
    keep = [l for l in lines if l.split("#", 1)[0].strip().lower() != entry]
    if len(keep) == len(lines):
        return False
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.writelines(keep)
    os.replace(tmp, path)
    return True


def load_state():
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE, encoding="utf-8") as fh:
            return json.load(fh)
    return {"seen": {}}


def save_state(state):
    tmp = STATE_FILE + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(state, fh)
    os.replace(tmp, STATE_FILE)


# ---------- IMAP ----------

_token = {"value": None, "t": 0}
TOKEN_REUSE = 45 * 60  # access tokens live about an hour; refresh before that


def connect(account):
    if not _token["value"] or time.time() - _token["t"] > TOKEN_REUSE:
        # The refresh token file is shared with otp-cleanup; serialize refresh+rewrite here.
        with open(TOKEN_LOCK, "a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            _token["value"], _ = oc.access_token()
        _token["t"] = time.time()
    token = _token["value"]
    conn = oc.imaplib.IMAP4_SSL(oc.IMAP_HOST, oc.IMAP_PORT)
    auth = "user=%s\x01auth=Bearer %s\x01\x01" % (account, token)
    conn.authenticate("XOAUTH2", lambda _: auth.encode())
    return conn


def fetch_headers(conn, folder, fields, since=None):
    typ, _ = conn.select(oc.quote(folder), readonly=True)
    if typ != "OK":
        return []
    crit = ["SINCE", since.strftime("%d-%b-%Y")] if since else ["ALL"]
    typ, data = conn.uid("SEARCH", None, *crit)
    uids = data[0].split() if typ == "OK" and data and data[0] else []
    out = []
    for i in range(0, len(uids), 100):
        typ, resp = conn.uid("FETCH", b",".join(uids[i:i + 100]).decode(),
                             "(UID BODY.PEEK[HEADER.FIELDS (%s)])" % fields)
        for item in resp or []:
            if not isinstance(item, tuple):
                continue
            m = re.search(rb"UID (\d+)", item[0])
            if m:
                msg = email.message_from_bytes(item[1], policy=email.policy.compat32)
                out.append((m.group(1).decode(), msg))
    return out


def addr_of(msg, field="From"):
    return email.utils.parseaddr(oc.decode_header(msg.get(field, "")))[1].lower()


def known_senders(conn, folders, own):
    keys = set()
    for name, flags in folders:
        if flags & NOT_KNOWN_SPECIAL or name.lower().startswith(NOT_KNOWN_PREFIXES):
            continue
        sent = "\\Sent" in flags
        for _, msg in fetch_headers(conn, name, "TO CC" if sent else "FROM"):
            vals = msg.get_all("To", []) + msg.get_all("Cc", []) if sent else msg.get_all("From", [])
            for _, a in email.utils.getaddresses([oc.decode_header(v) for v in vals]):
                k = sender_key(a)
                if k and a.lower() != own:
                    keys.add(k)
    return keys


def move(conn, folder, uids, dest):
    conn.select(oc.quote(folder), readonly=False)
    typ, _ = conn.uid("MOVE", ",".join(uids), oc.quote(dest))
    conn.close()
    return typ == "OK"


# ---------- one run ----------

_known_cache = {"t": 0, "keys": set()}


def run_once(do_move, account):
    conn = connect(account)
    try:
        folders = oc.list_folders(conn)
        junk = next((n for n, f in folders if "\\Junk" in f), "Junk")
        inbox = next((n for n, _ in folders if n.upper() == "INBOX"), "INBOX")
        own = account.lower()
        if time.time() - _known_cache["t"] > KNOWN_REFRESH:
            _known_cache["keys"] = known_senders(conn, folders, own)
            _known_cache["t"] = time.time()
        known = _known_cache["keys"]
        since = dt.date.today() - dt.timedelta(days=LOOKBACK_DAYS)
        state = load_state()
        seen = state["seen"]
        now = int(time.time())
        first_run = not seen

        current = {}
        for fname, label in ((inbox, "inbox"), (junk, "junk")):
            for uid, msg in fetch_headers(conn, fname, HEADERS, since):
                mid = (msg.get("Message-ID") or "").strip()
                if mid:
                    current[mid] = (label, uid, msg)

        # 1. learn from the owner's moves
        for mid, (label, _, msg) in current.items():
            prev = seen.get(mid, {})
            verdict = None if first_run else learn(prev.get("f"), label, False)
            addr = addr_of(msg)
            subj = oc.decode_header(msg.get("Subject", ""))[:80]
            key = sender_key(addr)
            if verdict and key:
                if verdict == "ham":
                    entry = key
                    changed = add_entry(ALLOW_FILE, entry, "not junk: " + subj) if do_move else True
                    for e in {addr, key}:
                        if do_move:
                            remove_entry(BLOCK_FILE, e)
                else:
                    entry = addr  # block per address; a domain block is a manual choice
                    changed = add_entry(BLOCK_FILE, entry, "junk: " + subj) if do_move else True
                    if do_move:
                        remove_entry(ALLOW_FILE, addr)
                if changed:
                    log("LEARN %s %s | %s" % (verdict, entry, subj))
            seen[mid] = {"f": label, "t": now}

        allow, block = read_list(ALLOW_FILE), read_list(BLOCK_FILE)
        to_inbox, to_junk = [], []
        for mid, (label, uid, msg) in current.items():
            addr = addr_of(msg)
            subj = oc.decode_header(msg.get("Subject", ""))[:100]
            if label == "junk":
                why = rescue_reason(addr, msg.get("Authentication-Results"), allow, block, known)
                if why:
                    to_inbox.append((mid, uid))
                    log("%s Junk->Inbox (%s) | %s | %s" % ("MOVE" if do_move else "WOULD MOVE", why, addr, subj))
            elif listed(addr, block):
                to_junk.append((mid, uid))
                log("%s Inbox->Junk (blocklist) | %s | %s" % ("MOVE" if do_move else "WOULD MOVE", addr, subj))

        if do_move:
            # record first so the next run does not read these as owner verdicts
            for items, folder, dest, label in ((to_inbox, junk, inbox, "inbox"), (to_junk, inbox, junk, "junk")):
                if not items:
                    continue
                for mid, _ in items:
                    seen[mid] = {"f": label, "t": now}
                save_state(state)
                if not move(conn, folder, [u for _, u in items], dest):
                    log("ERROR move %s->%s failed" % (folder, dest))
        cutoff = now - STATE_TTL_DAYS * 86400
        state["seen"] = {k: v for k, v in seen.items() if v["t"] >= cutoff}
        if do_move or first_run:
            save_state(state)
        return len(to_inbox), len(to_junk)
    finally:
        try:
            conn.logout()
        except Exception:
            pass


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--loop", type=int, metavar="SECONDS", help="repeat every SECONDS")
    ap.add_argument("--dry-run", action="store_true", help="log only, regardless of MODE")
    ap.add_argument("--known", action="store_true", help="print the known-sender set and exit")
    args = ap.parse_args()
    cfg = oc.load_config()  # ACCOUNT comes from the otp-cleanup config
    mf = {"MODE": "dry-run"}
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    mf[k.strip()] = v.strip().strip('"')
    account = mf.get("ACCOUNT") or cfg.get("ACCOUNT")
    if args.known:
        conn = connect(account)
        print("\n".join(sorted(known_senders(conn, oc.list_folders(conn), account.lower()))))
        conn.logout()
        return
    while True:
        do_move = mf["MODE"] == "move" and not args.dry_run
        try:
            a, b = run_once(do_move, account)
            if a or b or not args.loop:
                log("%s: %d rescued to Inbox, %d moved to Junk" % ("move" if do_move else "dry-run", a, b))
        except Exception as err:  # keep looping on network/token hiccups
            _token["value"] = None
            log("ERROR %s: %s" % (type(err).__name__, str(err)[:200]))
            if not args.loop:
                raise
        if not args.loop:
            return
        time.sleep(args.loop)


if __name__ == "__main__":
    main()
