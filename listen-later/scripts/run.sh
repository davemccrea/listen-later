#!/usr/bin/env bash
# Poll loop: fetch new audio, rebuild the feed, sleep, repeat.
# Runs immediately on start, then every POLL_INTERVAL seconds (default 15 min).
set -uo pipefail

INTERVAL="${POLL_INTERVAL:-900}"
echo "listen-later: polling every ${INTERVAL}s"

while true; do
	/app/fetch.sh        || echo "listen-later: fetch failed, continuing"
	python3 /app/build_feed.py || echo "listen-later: feed build failed, continuing"
	sleep "$INTERVAL"
done
