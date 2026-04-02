#!/usr/bin/env python3
"""Export Safari cookies — common use case for browser automation tools.

Usage:
    ~/.local/bin/fda-python3 export_cookies.py
    ~/.local/bin/fda-python3 export_cookies.py --domain github.com

Many Python libraries (browser_cookie3, pycookiecheat) need to read
~/Library/Cookies/Cookies.binarycookies. They fail silently from
launchd/cron without FDA.
"""

import os
import sys
import struct
import argparse
from datetime import datetime, timezone

COOKIES_PATH = os.path.expanduser("~/Library/Cookies/Cookies.binarycookies")
CORE_DATA_EPOCH = datetime(2001, 1, 1, tzinfo=timezone.utc)


def check_access():
    if not os.path.exists(COOKIES_PATH):
        print("Cookies.binarycookies not found")
        sys.exit(1)
    if not os.access(COOKIES_PATH, os.R_OK):
        print("Cannot read Cookies — FDA not granted to this Python binary")
        print(f"Binary: {sys.executable}")
        print()
        print("Run with: ~/.local/bin/fda-python3", __file__)
        sys.exit(1)


def read_cookies(domain_filter=None):
    """Parse the binary cookies file. Simplified parser for demonstration."""
    check_access()

    with open(COOKIES_PATH, "rb") as f:
        magic = f.read(4)
        if magic != b"cook":
            print("Not a valid binarycookies file")
            sys.exit(1)

        num_pages = struct.unpack(">I", f.read(4))[0]
        page_sizes = [struct.unpack(">I", f.read(4))[0] for _ in range(num_pages)]

        count = 0
        for page_size in page_sizes:
            page_data = f.read(page_size)
            if len(page_data) < 8:
                continue

            page_header = struct.unpack("<II", page_data[0:8])
            if page_header[0] != 0x00000100:
                continue

            num_cookies = page_header[1]
            offsets = [
                struct.unpack("<I", page_data[8 + i * 4 : 12 + i * 4])[0]
                for i in range(num_cookies)
            ]

            for offset in offsets:
                try:
                    cookie = parse_cookie(page_data, offset)
                    if cookie and (
                        not domain_filter or domain_filter in cookie["domain"]
                    ):
                        print(f"  Domain: {cookie['domain']}")
                        print(f"  Name:   {cookie['name']}")
                        print(f"  Path:   {cookie['path']}")
                        print()
                        count += 1
                except Exception:
                    continue

    print(
        f"Total: {count} cookies"
        + (f" matching {domain_filter}" if domain_filter else "")
    )


def parse_cookie(page_data, offset):
    """Parse a single cookie record from page data."""
    if offset + 16 > len(page_data):
        return None

    size = struct.unpack("<I", page_data[offset : offset + 4])[0]
    if offset + size > len(page_data):
        return None

    # Cookie record layout (offsets relative to cookie start)
    # 0: size, 4: flags, 8: padding, 16: url_offset, 20: name_offset,
    # 24: path_offset, 28: value_offset
    url_off = struct.unpack("<I", page_data[offset + 16 : offset + 20])[0]
    name_off = struct.unpack("<I", page_data[offset + 20 : offset + 24])[0]
    path_off = struct.unpack("<I", page_data[offset + 24 : offset + 28])[0]

    def read_string(off):
        start = offset + off
        end = page_data.index(b"\x00", start)
        return page_data[start:end].decode("utf-8", errors="replace")

    return {
        "domain": read_string(url_off),
        "name": read_string(name_off),
        "path": read_string(path_off),
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Export Safari cookies (requires FDA)")
    parser.add_argument("--domain", type=str, help="Filter by domain")
    args = parser.parse_args()
    read_cookies(domain_filter=args.domain)
