# Custom Caddy build with the Cloudflare DNS plugin for DNS-01 challenges.
# Rebuild after bumping the base tag:  docker compose build --no-cache
FROM caddy:2-builder AS builder
RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare

FROM caddy:2
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
