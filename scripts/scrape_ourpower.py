#!/usr/bin/env python3
"""Scrape OurPower.co.za status pages and refresh data.json.

A plain HTTP fetch of these pages returns only the page shell — the
actual status content ("No power outage reported... Last checked: ...")
is rendered client-side by JavaScript and simply isn't present in the
raw HTML (confirmed: an earlier requests+BeautifulSoup version couldn't
find the status pattern on any of 8 pages). This uses a headless
browser (Playwright/Chromium) to actually load and render each page
before reading its text.

Status detection is anchored on the confirmed real page pattern (verified
via screenshots of live pages): each status box reads roughly

    <headline mentioning "outage"> ... Last checked: DD Mon YYYY at HH:MM

e.g. "No power outage reported in Brackenfell by the City ... Last
checked: 04 Aug 2026 at 06:46" for a clear power page, or "No water
outage reported in Brackenfell ... Last checked: ..." for water (no "by
the City" suffix on water pages). An active example looked like "Water
outage in Macassar - reported 19 hours ago Burst Water Main - C/O Kramat
Road & N2 ... Last checked: ...". No "planned" example has been seen
live yet, so that classification is still a guess.

Safety behavior: if a page can't be loaded or the pattern can't be
found, that area/service is left untouched and a warning is printed — a
parsing miss should never silently overwrite good data with a guess.
"""
import json
import re
import sys
from datetime import datetime
from pathlib import Path

from playwright.sync_api import sync_playwright

REPO_ROOT = Path(__file__).resolve().parent.parent
DATA_PATH = REPO_ROOT / "data.json"
INDEX_PATH = REPO_ROOT / "index.html"

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)

DATETIME_PATTERN = r"\d{1,2} \w+ \d{4}(?:\s+at\s+|,\s*)\d{1,2}:\d{2}"
CHECKED_FORMATS = ("%d %b %Y at %H:%M", "%d %b %Y, %H:%M")

# Anchored on the two confirmed real headline phrasings rather than any text
# containing "outage" — the breadcrumb nav ("Home > Power Outages > Cape
# Town > ...") and the page's own <h1> ("Power Outage in Brackenfell, Cape
# Town") both also contain "outage" and sit before the real status text with
# no punctuation to stop a generic lazy match, which was swallowing them in
# as prefix noise. No "planned" example has been seen live yet, so a page
# using different wording will correctly fail to match rather than guess.
CLEAR_PHRASE = r"No\s+(?:Power|Water)\s+outage\s+reported\s+in\s+[^.,]*?"
# [^.,] (not just [^.]) stops the lazy match at a comma — the page's <h1>
# ("Water Outage in Macassar, Cape Town") also matches the start of this
# pattern and has no other punctuation before the real phrase, so without
# the comma boundary it swallows the whole h1 as a prefix too.
ACTIVE_PHRASE = r"(?:Power|Water)\s+outage\s+in\s+[^.,]*?-\s*reported\s+[^.]*?"
STATUS_PATTERN = re.compile(
    rf"({CLEAR_PHRASE}|{ACTIVE_PHRASE})\.?\s*Last checked:\s*({DATETIME_PATTERN})",
    re.I,
)


def fetch_status(page, url, service):
    page.goto(url, wait_until="networkidle", timeout=30000)
    text = re.sub(r"\s+", " ", page.inner_text("body")).strip()

    match = STATUS_PATTERN.search(text)
    if not match:
        snippet = text[:900] if text else "(empty body text)"
        raise ValueError(f"could not find a status/Last-checked pattern; page text starts: {snippet!r}")

    sentence = match.group(1).strip()
    checked_raw = match.group(2)
    for fmt in CHECKED_FORMATS:
        try:
            checked = datetime.strptime(checked_raw, fmt).strftime("%Y-%m-%d %H:%M")
            break
        except ValueError:
            continue
    else:
        raise ValueError(f"unrecognized 'Last checked' date format: {checked_raw!r}")

    if re.search(rf"no\s+{service}\s+outage\s+reported", sentence, re.I):
        status = "clear"
    elif re.search(r"planned", sentence, re.I):
        status = "planned"
    else:
        status = "active"

    return status, sentence, checked


def update_fallback(data):
    html = INDEX_PATH.read_text(encoding="utf-8")
    start_marker = '<script type="application/json" id="fallback-data">\n'
    end_marker = "\n  </script>"
    start = html.index(start_marker) + len(start_marker)
    end = html.index(end_marker, start)
    new_json = json.dumps(data, indent=2, ensure_ascii=False)
    INDEX_PATH.write_text(html[:start] + new_json + html[end:], encoding="utf-8")


def main():
    data = json.loads(DATA_PATH.read_text(encoding="utf-8"))
    changed = False

    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(user_agent=USER_AGENT)

        for area in data["areas"]:
            for tag in ("elec", "water"):
                entry = area.get(tag)
                if not entry or not entry.get("link"):
                    continue
                service = "power" if tag == "elec" else "water"
                try:
                    status, status_text, checked = fetch_status(page, entry["link"], service)
                except Exception as exc:
                    print(f"warn: {area['id']}/{tag}: {exc}", file=sys.stderr)
                    continue
                if (
                    entry.get("status") != status
                    or entry.get("statusText") != status_text
                    or entry.get("checked") != checked
                ):
                    entry["status"] = status
                    entry["statusText"] = status_text
                    entry["checked"] = checked
                    changed = True

        browser.close()

    if not changed:
        print("no changes detected")
        return

    DATA_PATH.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    update_fallback(data)
    print("data.json updated")


if __name__ == "__main__":
    main()
