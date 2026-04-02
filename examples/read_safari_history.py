#!/usr/bin/env python3
"""Read Safari browsing history via FDA tunnel.

Usage:
    ~/.local/bin/fda-python3 read_safari_history.py
    ~/.local/bin/fda-python3 read_safari_history.py --limit 50
    ~/.local/bin/fda-python3 read_safari_history.py --since 2026-01-01

Will fail with "unable to open database file" if run with regular python3
from launchd/cron (no FDA).
"""

import sqlite3
import os
import sys
import argparse
from datetime import datetime

SAFARI_HISTORY = os.path.expanduser("~/Library/Safari/History.db")

# Safari stores timestamps as seconds since 2001-01-01 (Core Data epoch)
CORE_DATA_EPOCH = 978307200  # Unix timestamp of 2001-01-01


def read_history(limit=20, since=None):
    if not os.path.exists(SAFARI_HISTORY):
        print("Safari History.db not found")
        sys.exit(1)

    if not os.access(SAFARI_HISTORY, os.R_OK):
        print("Cannot read History.db — FDA not granted to this Python binary")
        print(f"Binary: {sys.executable}")
        print()
        print("Fix: grant Full Disk Access to this binary in System Settings,")
        print("or run this script with an FDA-tunneled binary:")
        print(f"  ~/.local/bin/fda-python3 {__file__}")
        sys.exit(1)

    conn = sqlite3.connect(f"file:{SAFARI_HISTORY}?mode=ro", uri=True)
    cursor = conn.cursor()

    query = """
        SELECT
            hi.url,
            hv.title,
            datetime(hv.visit_time + 978307200, 'unixepoch', 'localtime') as visit_date
        FROM history_items hi
        JOIN history_visits hv ON hi.id = hv.history_item
    """

    params = []
    if since:
        # Convert since date to Core Data timestamp
        since_dt = datetime.strptime(since, "%Y-%m-%d")
        since_ts = since_dt.timestamp() - CORE_DATA_EPOCH
        query += " WHERE hv.visit_time > ?"
        params.append(since_ts)

    query += " ORDER BY hv.visit_time DESC LIMIT ?"
    params.append(limit)

    cursor.execute(query, params)
    rows = cursor.fetchall()
    conn.close()

    if not rows:
        print("No history entries found")
        return

    for url, title, visit_date in rows:
        title = title or "(no title)"
        print(f"  {visit_date}  {title[:60]}")
        print(f"    {url[:100]}")
        print()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Read Safari history (requires FDA)")
    parser.add_argument("--limit", type=int, default=20, help="Number of entries")
    parser.add_argument("--since", type=str, help="Filter since date (YYYY-MM-DD)")
    args = parser.parse_args()
    read_history(limit=args.limit, since=args.since)
