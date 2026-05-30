# caddy — ingress for `*.mccrea.link`

Single Tailscale ingress node terminating a wildcard `*.mccrea.link` cert and
reverse-proxying to every service by Docker container name over the external
`proxy` bridge. Implements `caddy-url-access-plan.md`.

The config lives in `conf/Caddyfile` and the **directory** is mounted at
`/etc/caddy` (not the file). This matters: a single-file bind mount pins the
inode, so edits would be silently ignored by the running container. To apply a
Caddyfile change after editing `conf/Caddyfile`:

```bash
docker exec caddy caddy reload --config /etc/caddy/Caddyfile
```

## One-time bootstrap

1. **Create the shared bridge** (already done if `docker network ls` shows it):
   ```bash
   docker network create proxy
   ```
2. **Cloudflare token.** Mint a token scoped `Zone:DNS:Edit` on the
   `mccrea.link` zone, then:
   ```bash
   cp .env.example .env
   # fill CF_API_TOKEN (and ACME_EMAIL)
   ```
3. **Build + start**:
   ```bash
   docker compose build
   docker compose up -d
   ```
   First start blocks a few minutes while the DNS-01 wildcard issues. Watch:
   ```bash
   docker compose logs -f caddy
   ```
4. **Pin the Caddy tailnet IP** and add the AdGuard wildcard rewrite:
   `*.mccrea.link → <caddy tailnet IP>`. Get the IP with:
   ```bash
   docker exec tailscale-caddy tailscale ip -4
   ```
5. **Verify** end-to-end, independent of any backend:
   ```bash
   curl https://whoami.mccrea.link   # -> "caddy ok", browser-trusted cert
   ```

## Migrating a service onto Caddy

Per `caddy-url-access-plan.md` §3, for each service (one at a time, verify, commit):

1. Remove its `tailscale-<svc>` sidecar, `network_mode: service:...`,
   matching `depends_on`, and `./tailscale/state` volume.
2. Attach the app container to the external `proxy` network.
3. Set any host/base-URL config (see plan table — Vaultwarden `DOMAIN`,
   Paperless `PAPERLESS_URL`/CSRF/hosts, Homepage `HOMEPAGE_ALLOWED_HOSTS`,
   Immich external domain, etc.).
4. `docker compose up -d` the service; the matching site block in `Caddyfile`
   already exists, so `https://<svc>.mccrea.link` lights up. (Unmigrated
   services keep their sidecar + IP access and just 502 through Caddy.)
