# caddy — ingress for `*.mccrea.link`

Single Tailscale ingress node terminating a wildcard `*.mccrea.link` cert and
reverse-proxying to every service by Docker container name over the external
`proxy` bridge. Implements `caddy-url-access-plan.md`.

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
3. **Build + start** (Caddy + sidecar only; oauth2-proxy stays dormant):
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

## Forward-auth (sonarr / radarr / prowlarr / sabnzbd) — NOT YET WORKING

The guarded blocks and the `oauth2-proxy` service are scaffolded but disabled
(`profiles: ["auth"]`, blocks commented in `Caddyfile`). Two things must be
resolved first:

1. **tsidp client.** Register `oauth2-proxy` as an OIDC client in tsidp; put the
   client id/secret + a generated `OAUTH2_COOKIE_SECRET` into `.env`.

2. **⚠ Back-channel DNS (open design issue).** oauth2-proxy makes *server-side*
   calls to the issuer `https://tsidp.tailfab2f.ts.net` (OIDC discovery, JWKS,
   token exchange) from inside a container. That is exactly the in-container
   `ts.net` resolution path the plan documents as broken under the AdGuard
   global-override DNS config. The plan's "only the browser needs tsidp" note
   covers the front-channel but not this back-channel. Options to evaluate:
   - `extra_hosts: ["tsidp.tailfab2f.ts.net:<tsidp tailnet IP>"]` on
     oauth2-proxy, and confirm the proxy bridge can route to 100.x (host IP
     forwarding / tailscale masquerade);
   - give oauth2-proxy its own thin Tailscale sidecar (adds a 3rd tailnet node);
   - front tsidp with a `*.mccrea.link` name too and point the issuer there
     (changes the issuer URL — affects existing Immich registration).

   Resolve this, then `docker compose --profile auth up -d` and uncomment the
   `(guarded)` snippet + the four host blocks in `Caddyfile`.
