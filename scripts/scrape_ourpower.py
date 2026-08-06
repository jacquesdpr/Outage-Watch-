#!/usr/bin/env python3
"""Scrape OurPower.co.za status pages and refresh data.json.

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

Safety behavior: if a page can't be fetched or the pattern can't be
found, that area/service is left untouched and a warning is printed — a
parsing miss should never silently overwrite good data with a guess.
"""
import json
import re
import sys
from datetime import datetime
from pathlib import Path

import requests
from bs4 import BeautifulSoup

REPO_ROOT = Path(__file__).resolve().parent.parent
DATA_PATH = REPO_ROOT / "data.json"
INDEX_PATH = REPO_ROOT / "index.html"

REQUEST_HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; OutageWatchBot/1.0)"}

STATUS_PATTERN = re.compile(
    r"([^.]*?outage[^.]*?)\.?\s*Last checked:\s*(\d{1,2} \w+ \d{4} at \d{1,2}:\d{2})",
    re.I,
)


def fetch_status(url, service):
    resp = requests.get(url, timeout=20, headers=REQUEST_HEADERS)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")
    text = re.sub(r"\s+", " ", soup.get_text(" ", strip=True)).strip()

    match = STATUS_PATTERN.search(text)
    if not match:
        raise ValueError("could not find a status/Last-checked pattern on the page")

    sentence = match.group(1).strip()
    checked_raw = match.group(2)
    checked = datetime.strptime(checked_raw, "%d %b %Y at %H:%M").strftime("%Y-%m-%d %H:%M")

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

    for area in data["areas"]:
        for tag in ("elec", "water"):
            entry = area.get(tag)
            if not entry or not entry.get("link"):
                continue
            service = "power" if tag == "elec" else "water"
            try:
                status, status_text, checked = fetch_status(entry["link"], service)
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

    if not changed:
        print("no changes detected")
        return

    DATA_PATH.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    update_fallback(data)
    print("data.json updated")


if __name__ == "__main__":
    main()
