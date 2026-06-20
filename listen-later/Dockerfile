# Self-contained YouTube-playlist → audio fetcher.
# yt-dlp comes from pip so it's current (YouTube changes often break old builds);
# rebuild this image periodically to refresh it.
FROM python:3.12-alpine

RUN apk add --no-cache bash ffmpeg \
    && pip install --no-cache-dir --upgrade yt-dlp

COPY scripts/ /app/
RUN chmod +x /app/fetch.sh /app/run.sh

# Loop: fetch new audio, rebuild the feed, sleep, repeat.
CMD ["/app/run.sh"]
