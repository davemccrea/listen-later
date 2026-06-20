#!/usr/bin/env python3
"""Build an RSS/podcast feed from the audio yt-dlp has downloaded.

Reads the *.info.json files (in PODCAST_STATE_DIR) that yt-dlp writes for each
download, pairs them with the *.mp3 in PODCAST_PUBLIC_DIR/audio, and writes
PODCAST_PUBLIC_DIR/feed.xml. Caddy serves PODCAST_PUBLIC_DIR at the web root, so
the feed is at <PODCAST_BASE_URL>/feed.xml and audio at /audio/<id>.mp3.

Episode order is by mp3 mtime (download time), so a video becomes the newest
episode right after it's fetched.

Config (from the environment / docker-compose.yml):
  PODCAST_BASE_URL    public base URL Caddy is served at, e.g. https://listen-later.mccrea.link
  PODCAST_PUBLIC_DIR  served dir (default /data/public)
  PODCAST_STATE_DIR   where the *.info.json live (default /data/state)
  PODCAST_TITLE / PODCAST_DESCRIPTION / PODCAST_AUTHOR / PODCAST_IMAGE
"""
import os
import sys
import json
import glob
from email.utils import formatdate
from xml.sax.saxutils import escape

PUBLIC_DIR = os.environ.get("PODCAST_PUBLIC_DIR", "/data/public")
STATE_DIR = os.environ.get("PODCAST_STATE_DIR", "/data/state")
AUDIO_DIR = os.path.join(PUBLIC_DIR, "audio")
FEED_PATH = os.path.join(PUBLIC_DIR, "feed.xml")

BASE_URL = os.environ.get("PODCAST_BASE_URL", "").rstrip("/")
if not BASE_URL:
    sys.exit("PODCAST_BASE_URL is not set")

TITLE = os.environ.get("PODCAST_TITLE", "Listen Later")
DESCRIPTION = os.environ.get("PODCAST_DESCRIPTION", "Audio from my YouTube playlist")
AUTHOR = os.environ.get("PODCAST_AUTHOR", "listen-later")
IMAGE = os.environ.get("PODCAST_IMAGE", "")


def itunes_duration(seconds):
    seconds = int(seconds or 0)
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"


def collect_items():
    items = []
    for info_path in glob.glob(os.path.join(STATE_DIR, "*.info.json")):
        vid = os.path.basename(info_path)[: -len(".info.json")]
        mp3_path = os.path.join(AUDIO_DIR, vid + ".mp3")
        if not os.path.exists(mp3_path):
            continue  # download still in progress / failed
        try:
            with open(info_path, encoding="utf-8") as fh:
                info = json.load(fh)
        except (OSError, json.JSONDecodeError):
            continue
        items.append({
            "id": vid,
            "title": info.get("title") or vid,
            "description": info.get("description") or "",
            "duration": info.get("duration") or 0,
            "image": info.get("thumbnail") or "",
            "url": f"{BASE_URL}/audio/{vid}.mp3",
            "length": os.path.getsize(mp3_path),
            "mtime": os.path.getmtime(mp3_path),
            "link": info.get("webpage_url") or f"https://youtu.be/{vid}",
        })
    items.sort(key=lambda it: it["mtime"], reverse=True)
    return items


def build_xml(items):
    out = []
    out.append('<?xml version="1.0" encoding="UTF-8"?>')
    out.append('<rss version="2.0" '
               'xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" '
               'xmlns:content="http://purl.org/rss/1.0/modules/content/">')
    out.append("<channel>")
    out.append(f"<title>{escape(TITLE)}</title>")
    out.append(f"<link>{escape(BASE_URL)}</link>")
    out.append(f"<description>{escape(DESCRIPTION)}</description>")
    out.append("<language>en-us</language>")
    out.append(f"<itunes:author>{escape(AUTHOR)}</itunes:author>")
    out.append('<itunes:explicit>false</itunes:explicit>')
    if IMAGE:
        out.append(f'<itunes:image href="{escape(IMAGE)}"/>')
    if items:
        out.append(f"<lastBuildDate>{formatdate(items[0]['mtime'])}</lastBuildDate>")

    for it in items:
        out.append("<item>")
        out.append(f"<title>{escape(it['title'])}</title>")
        out.append(f"<link>{escape(it['link'])}</link>")
        out.append(f'<guid isPermaLink="false">{escape(it["id"])}</guid>')
        out.append(f"<pubDate>{formatdate(it['mtime'])}</pubDate>")
        out.append(f"<description>{escape(it['description'])}</description>")
        out.append(f'<enclosure url="{escape(it["url"])}" '
                   f'length="{it["length"]}" type="audio/mpeg"/>')
        out.append(f"<itunes:duration>{itunes_duration(it['duration'])}</itunes:duration>")
        if it["image"]:
            out.append(f'<itunes:image href="{escape(it["image"])}"/>')
        out.append("</item>")

    out.append("</channel>")
    out.append("</rss>")
    return "\n".join(out)


def main():
    os.makedirs(PUBLIC_DIR, exist_ok=True)
    items = collect_items()
    xml = build_xml(items)
    tmp = FEED_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(xml)
    os.replace(tmp, FEED_PATH)  # atomic so Caddy never serves a half-written feed
    print(f"listen-later: wrote {FEED_PATH} with {len(items)} episode(s)")


if __name__ == "__main__":
    main()
