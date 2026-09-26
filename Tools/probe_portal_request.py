#!/usr/bin/env python3
"""
Finds which parts of a working portal request actually matter.

Usage:
  1. In Safari Web Inspector → Network, right-click a working api/ request
     (e.g. FetchHealthSummary) → Copy as cURL.
  2. Run:  python3 Tools/probe_portal_request.py
     (it reads the curl command from the clipboard via `pbpaste`).

It replays the request once as-is, then once per header with that header
removed, plus a few substitutions matching what the iOS app sends. Only header
NAMES and HTTP status codes are printed — never cookie or token values. All
requests go only to the host in the copied command.
"""
import json
import shlex
import subprocess
import urllib.error
import urllib.request

APP_USER_AGENT = ("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
                  "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1")


def parse_curl(text):
    args = shlex.split(text.replace("\\\n", " "))
    url, method, headers, data = None, "GET", {}, None
    i = 1
    while i < len(args):
        a = args[i]
        if a in ("-X", "--request"):
            method = args[i + 1]; i += 2; continue
        if a in ("-H", "--header"):
            name, _, value = args[i + 1].partition(":")
            headers[name.strip()] = value.strip(); i += 2; continue
        if a in ("--data-raw", "--data", "-d", "--data-binary"):
            data = args[i + 1]; method = "POST" if method == "GET" else method; i += 2; continue
        if not a.startswith("-") and url is None:
            url = a
        i += 1
    # Let urllib compute these; a compressed body would also confuse the check.
    for h in ("Content-Length", "Accept-Encoding", "Connection"):
        headers.pop(h, None)
    return url, method, headers, data


def send(url, method, headers, data):
    req = urllib.request.Request(url, data=data.encode() if data is not None else None,
                                 headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            body = resp.read()
            final = resp.geturl()
            status = resp.status
    except urllib.error.HTTPError as e:
        body, final, status = e.read(), e.geturl(), e.code
    ok = status == 200 and "Home/Error" not in final
    try:
        parsed = json.loads(body)
        shape = f"JSON with {len(parsed)} top-level keys" if isinstance(parsed, dict) else "JSON"
    except ValueError:
        shape = "not JSON"
    return status, ok, shape, final.split("?")[0].rsplit("/", 2)[-2:]


def main():
    text = subprocess.run(["pbpaste"], capture_output=True, text=True).stdout
    if "curl" not in text:
        print("Clipboard doesn't contain a curl command. Use Safari's 'Copy as cURL' first.")
        return
    url, method, headers, data = parse_curl(text)
    print(f"{method} {url.split('?')[0]}  body={data!r}\n")

    status, ok, shape, where = send(url, method, headers, data)
    print(f"{'baseline (as copied)':40} HTTP {status}  {'OK ' if ok else 'FAIL'}  {shape}  → {'/'.join(where)}")
    if not ok:
        print("\nBaseline already fails — the Safari session has probably expired. Reload the page and copy again.")
        return
    print()

    for name in sorted(headers):
        trimmed = {k: v for k, v in headers.items() if k != name}
        status, ok, shape, _ = send(url, method, trimmed, data)
        print(f"{'without ' + name:40} HTTP {status}  {'OK ' if ok else 'FAIL'}  {shape}")

    # Which individual cookies matter? (names only in output)
    cookie_header = headers.get("Cookie", "")
    jar = [c.strip() for c in cookie_header.split(";") if c.strip()]
    if len(jar) > 1:
        print()
        for c in jar:
            name = c.split("=", 1)[0]
            kept = "; ".join(x for x in jar if x is not c)
            status, ok, shape, _ = send(url, method, {**headers, "Cookie": kept}, data)
            print(f"{'without cookie ' + name:40} HTTP {status}  {'OK ' if ok else 'FAIL'}  {shape}")

    print()
    variants = {
        "with the app's iPhone User-Agent": {**headers, "User-Agent": APP_USER_AGENT},
        "with Accept-Language: en-US": {**headers, "Accept-Language": "en-US,en;q=0.9"},
        "with X-Requested-With added": {**headers, "X-Requested-With": "XMLHttpRequest"},
    }
    for label, h in variants.items():
        status, ok, shape, _ = send(url, method, h, data)
        print(f"{label:40} HTTP {status}  {'OK ' if ok else 'FAIL'}  {shape}")


if __name__ == "__main__":
    main()
