#!/usr/bin/env python3
"""Scrape OurPower.co.za status pages and refresh data.json.

This was written without ever loading a live OurPower.co.za page (no
outbound network access in the dev environment), so the status-detection
patterns below are a best guess at common phrasing rather than something
verified against the site's actual markup. Expect to need to adjust
CLEAR_PATTERNS / PLANNED_PATTERNS / ACTIVE_PATTERNS (and the status_text
extraction) after watching a real run against the live pages.

Safety behavior: if a page can't be fetched or its status can't be
confidently classified, that area/service is left untouched and a
warning is printed — a parsing miss should never silently overwrite good
data with a wrong guess.
"""
import json
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import requests
from bs4 import BeautifulSoup

REPO_ROOT = Path(__file__).resolve().parent.parent
DATA_PATH = REPO_ROOT / "data.json"
INDEX_PATH = REPO_ROOT / "index.html"
SAST = timezone(timedelta(hours=2))

REQUEST_HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; OutageWatchBot/1.0)"}

CLEAR_PATTERNS = re.compile(
    r"no (?:reported|active|current)\s+(?:power\s+)?outages?|no outages? reported|all clear",
    re.I,
)
PLANNED_PATTERNS = re.compile(r"planned\s+(?:maintenance|outage|power outage)", re.I)
ACTIVE_PATTERNS = re.compile(
    r"\b(?:active|current|ongoing)\s+(?:power\s+)?outage|fault reported|burst\s+(?:pipe|main)",
    re.I,
)


def classify(text):
    if PLANNED_PATTERNS.search(text):
        return "planned"
    if ACTIVE_PATTERNS.search(text):
        return "active"
    if CLEAR_PATTERNS.search(text):
        return "clear"
    return None


def fetch_status(url):
    resp = requests.get(url, timeout=20, headers=REQUEST_HEADERS)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")
    text = soup.get_text(" ", strip=True)

    status = classify(text)
    if status is None:
        raise ValueError("could not classify status from page text")

    main = soup.find("main") or soup.find(attrs={"class": re.compile("content|main", re.I)}) or soup
    heading = main.find(["h1", "h2", "h3"])
    status_text = heading.get_text(strip=True) if heading else text[:120]

    return status, status_text


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
        for service in ("elec", "water"):
            entry = area.get(service)
            if not entry or not entry.get("link"):
                continue
            try:
                status, status_text = fetch_status(entry["link"])
            except Exception as exc:
                print(f"warn: {area['id']}/{service}: {exc}", file=sys.stderr)
                continue
            if entry.get("status") != status or entry.get("statusText") != status_text:
                entry["status"] = status
                entry["statusText"] = status_text
                changed = True

    if not changed:
        print("no changes detected")
        return

    data["checked"] = datetime.now(SAST).strftime("%Y-%m-%d %H:%M")
    DATA_PATH.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    update_fallback(data)
    print("data.json updated")


if __name__ == "__main__":
    main()
