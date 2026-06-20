# listen-later

Add a video to a YouTube playlist; within ~15 minutes its audio shows up as a new
episode in your podcast app. No n8n — just a small fetcher container, Caddy, and a
Cloudflare tunnel.

## How it works

```
fetcher container (loop, every POLL_INTERVAL)
   ├─ fetch.sh        yt-dlp grabs audio for any *new* playlist videos as mp3
   └─ build_feed.py   rebuilds feed.xml from the downloaded files
                          │
   Caddy serves ./data/public ──► Cloudflare tunnel ──► listen-later.mccrea.link
                          │
              your podcast app subscribes to
              https://listen-later.mccrea.link/feed.xml
```

YouTube has no "playlist changed" push API, so the fetcher polls. `yt-dlp
--download-archive` makes each poll cheap and idempotent — already-grabbed videos
are skipped.

The feed is **public** (no auth) so it works in every podcast app. See Notes for
what that means.

## Layout

```
listen-later/
├─ docker-compose.yml      fetcher + caddy + tunnel
├─ Dockerfile              python-alpine + ffmpeg + yt-dlp + scripts
├─ Caddyfile              serves data/public at the web root
├─ scripts/
│  ├─ run.sh               poll loop
│  ├─ fetch.sh             yt-dlp download of new videos
│  └─ build_feed.py        builds feed.xml
└─ data/                   runtime, git-ignored
   ├─ public/              <- served by Caddy
   │  ├─ feed.xml
   │  └─ audio/<id>.mp3
   └─ state/               <- NOT served
      ├─ <id>.info.json    metadata for the feed
      └─ archive.txt       yt-dlp's "already downloaded" list
```

## Setup

1. **Make a playlist.** Create a dedicated **Unlisted** (or Public) YouTube
   playlist and copy its URL (`https://www.youtube.com/playlist?list=PL...`).

2. **Fill in `.env`** (copy from `.env.example`): `TUNNEL_TOKEN`, `PLAYLIST_URL`,
   `PODCAST_BASE_URL`, and the title/description/author.

3. **Cloudflare tunnel hostname.** In Zero Trust → Networks → Tunnels → your
   tunnel → Public Hostnames, add: `listen-later.mccrea.link` → Service `HTTP` →
   `caddy:80`. (cloudflared resolves the `caddy` container by name on the compose
   network.)

4. **Build & start:**
   ```bash
   cd ~/stacks/listen-later
   docker compose up -d --build
   ```
   The first run backfills the whole playlist; watch it with
   `docker compose logs -f fetcher`.

5. **Subscribe** in your podcast app to:
   ```
   https://listen-later.mccrea.link/feed.xml
   ```

## Tuning

- **Poll interval** — `POLL_INTERVAL` (seconds) in `.env`.
- **Audio quality / format** — edit `scripts/fetch.sh` (e.g. switch
  `--audio-format` to `m4a`; update the `type=` in `build_feed.py`). Rebuild after.
- **Keep yt-dlp fresh** — YouTube changes break old yt-dlp. Refresh with
  `docker compose build --no-cache fetcher && docker compose up -d` periodically.

## Notes & limits

- **Unlisted/Public playlists only.** A Private playlist needs exported YouTube
  cookies for yt-dlp — not configured here.
- **Removing a video from the playlist** does *not* delete its episode. Delete the
  `data/public/audio/<id>.mp3` + `data/state/<id>.info.json` and wait for the next
  poll (or `docker compose restart fetcher`) to prune it from the feed.
- **The feed is fully public.** Anyone with the URL can fetch the audio; the
  `noindex` header only keeps it out of search results. For privacy, serve it over
  Tailscale instead, or put the feed under an unguessable `PODCAST_BASE_URL` path.
- This downloads copyrighted audio from YouTube. Keep it personal and private.
