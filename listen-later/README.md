# listen-later

Add a video to a YouTube playlist, get it as a podcast episode a few minutes later.
fetcher container polls the playlist, yt-dlp grabs the audio, a script rebuilds
feed.xml, Caddy serves it through a Cloudflare tunnel.

## Layout

```
docker-compose.yml   fetcher + caddy + tunnel
Dockerfile           python + ffmpeg + yt-dlp + scripts
Caddyfile            serves data/public
scripts/run.sh       poll loop
scripts/fetch.sh     yt-dlp download
scripts/build_feed.py  writes feed.xml
data/                runtime, git-ignored
  public/            served: feed.xml, audio/<id>.mp3
  state/             private: <id>.info.json, archive.txt
```

## Setup

1. Make an Unlisted YouTube playlist, copy its URL.
2. Copy `.env.example` to `.env`, fill in `TUNNEL_TOKEN`, `PLAYLIST_URL`,
   `PODCAST_BASE_URL`, title/description/author.
3. Cloudflare tunnel: add hostname `listen-later.mccrea.link` → HTTP → `caddy:80`.
4. `docker compose up -d --build` (first run backfills the whole playlist;
   `docker compose logs -f fetcher` to watch).
5. Subscribe to `https://listen-later.mccrea.link/feed.xml`.

## Notes

- `POLL_INTERVAL` (seconds) in `.env` sets how often it checks.
- Audio format: edit `scripts/fetch.sh` + the `type=` in `build_feed.py`, rebuild.
- yt-dlp breaks when YouTube changes; refresh with
  `docker compose build --no-cache fetcher && docker compose up -d`.
- Unlisted/Public only; Private needs cookies.
- Removing a video from the playlist doesn't delete the episode: rm its
  `data/public/audio/<id>.mp3` + `data/state/<id>.info.json`, restart fetcher.
- Feed is fully public: anyone with the URL gets the audio.
