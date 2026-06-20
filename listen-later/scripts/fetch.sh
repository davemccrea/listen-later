#!/usr/bin/env bash
# Download audio for any *new* videos in the playlist.
# yt-dlp's --download-archive makes this idempotent: videos already grabbed on a
# previous run are skipped, so it's safe to call on every poll.
#
# Layout (so only the audio + feed are web-served, never the state):
#   /data/public/audio/<id>.mp3   <- served by Caddy
#   /data/state/<id>.info.json    <- metadata for build_feed.py (not served)
#   /data/state/archive.txt       <- yt-dlp's "already done" list (not served)
set -uo pipefail

PUBLIC_DIR="${PODCAST_PUBLIC_DIR:-/data/public}"
STATE_DIR="${PODCAST_STATE_DIR:-/data/state}"
AUDIO_DIR="$PUBLIC_DIR/audio"
PLAYLIST_URL="${PLAYLIST_URL:?PLAYLIST_URL is not set}"

mkdir -p "$AUDIO_DIR" "$STATE_DIR"

yt-dlp \
	--download-archive "$STATE_DIR/archive.txt" \
	--no-overwrites \
	--ignore-errors \
	--no-warnings \
	-f "bestaudio/best" \
	-x --audio-format mp3 --audio-quality 0 \
	--embed-thumbnail --embed-metadata \
	--write-info-json \
	--no-write-playlist-metafiles \
	-P "home:$AUDIO_DIR" \
	-P "infojson:$STATE_DIR" \
	-o "%(id)s.%(ext)s" \
	"$PLAYLIST_URL"

echo "listen-later: fetch complete"
