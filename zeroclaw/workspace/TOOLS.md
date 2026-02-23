# CLI tools available to the agent

This document describes the command-line tools installed in this environment. Use them when the user asks for network reconnaissance, DNS lookups, OSINT, or similar tasks. Always use these tools only on targets you are authorized to test (e.g. your own domains or with explicit permission).

---

## Network and port scanning

### nmap

**Purpose:** Port scanning, service and version detection, basic host discovery.

**Typical usage:**

- Quick port check: `nmap -p 80,443,22 <host>`
- Service/version: `nmap -sV -p 80,443 <host>`
- Ping scan (discovery): `nmap -sn <network>/24`
- Full TCP connect scan: `nmap -sT -p- <host>` (slower)

**When to use:** Enumerating open ports, identifying services, checking if a host is up.

**Caveats:** Only scan targets you are allowed to. Aggressive or broad scans can trigger IDS/IPS or violate ToS.

---

## DNS

### dig

**Purpose:** DNS lookups (A, AAAA, MX, NS, TXT, etc.) with detailed output.

**Typical usage:**

- A record: `dig +short A example.com`
- Any record: `dig example.com MX`, `dig example.com TXT`
- Specific nameserver: `dig @8.8.8.8 example.com`
- Reverse: `dig -x 8.8.8.8`

**When to use:** Resolving hostnames, checking MX/NS/TXT, DNS troubleshooting.

### nslookup

**Purpose:** Simpler DNS lookup (interactive or one-shot).

**Typical usage:** `nslookup example.com`, `nslookup -type=MX example.com`

**When to use:** Quick DNS checks when dig is not needed.

---

## WHOIS and registration

### whois

**Purpose:** Domain and IP registration / RIR information.

**Typical usage:**

- Domain: `whois example.com`
- IP: `whois 8.8.8.8`

**When to use:** Finding registrant, nameservers, creation/expiry dates, or IP allocation.

**Caveats:** Output format varies by TLD/RIR. Some registries limit rate or require CAPTCHA.

---

## Traceroute

### traceroute

**Purpose:** Show the path (hops) to a host.

**Typical usage:** `traceroute example.com`, `traceroute -n 8.8.8.8`

**When to use:** Diagnosing routing, latency, or where a path fails.

---

## HTTP and data handling

### curl

**Purpose:** Fetch URLs, APIs, headers; support for many protocols.

**Typical usage:**

- GET: `curl -s https://example.com`
- Headers: `curl -I https://example.com`
- POST: `curl -X POST -d '{"key":"value"}' -H "Content-Type: application/json" https://api.example.com/endpoint`
- With auth: `curl -u user:pass https://example.com`

**When to use:** Checking endpoints, APIs, redirects, or downloading small resources.

### wget

**Purpose:** Download files and mirror sites non-interactively.

**Typical usage:** `wget https://example.com/file.zip`, `wget -O - https://example.com` (stdout).

**When to use:** Downloading files or when wget’s recursion/mirror options are needed.

### jq

**Purpose:** Parse and transform JSON on the command line.

**Typical usage:**

- Pretty-print: `curl -s https://api.example.com | jq .`
- Field: `echo '{"a":1,"b":2}' | jq .a`
- Array slice: `jq '.[0:5]'`
- Filter: `jq '.[] | select(.active == true)'`

**When to use:** Any JSON from APIs, configs, or logs.

---

## OSINT (Python-based)

### theHarvester

**Purpose:** Gather emails, subdomains, hosts, and open ports from public sources (search engines, PGP, etc.).

**Typical usage:**

- Domain: `theHarvester -d example.com -b all`
- Limit sources: `theHarvester -d example.com -b bing,duckduckgo`
- Limit results: `theHarvester -d example.com -b all -l 200`

**When to use:** Domain reconnaissance, finding related subdomains and contacts.

**Caveats:** Respect rate limits and ToS of data sources. Use only on authorized targets.

### sherlock

**Purpose:** Check whether a username exists across many sites.

**Typical usage:** `sherlock username`, `sherlock user123 --timeout 15`

**When to use:** Username enumeration across social/forum sites (e.g. for OSINT or account discovery).

**Caveats:** Use only for authorized research (e.g. your own username or with permission). Do not use for harassment or unauthorized tracking.

---

## Summary

| Tool         | Use for                          |
| ------------ | --------------------------------- |
| nmap         | Port scans, service detection     |
| dig/nslookup | DNS lookups                       |
| whois        | Domain/IP registration info       |
| traceroute   | Network path to host              |
| curl/wget    | HTTP requests and downloads      |
| jq           | JSON parsing and filtering        |
| theHarvester | Domain/subdomain/email OSINT     |
| sherlock     | Username presence on many sites   |

Reference this file (e.g. in AGENTS.md or identity) so the model uses these tools appropriately and only on authorized targets.
