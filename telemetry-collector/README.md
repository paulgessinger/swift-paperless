# telemetry-collector

Counter-only collector for Swift Paperless's opt-in telemetry. It accepts two
pings, `POST /t/health` and `POST /t/feature`, splits each into independent
per-field counters, and stores nothing else. The same package and image also
run a read-only, OIDC-protected analytics dashboard as a separate process
(see [Dashboard](#dashboard)). The design and privacy model are
in `plans/privacy-preserving-telemetry.md`; the user-facing description is
`docs/telemetry.md`.

`telemetry-schema.json` is the shared contract with the app: channels, bucket
values, device/auth values, feature names and error names. The collector loads
it at startup and builds its validation from it.

## Run locally

```sh
cd telemetry-collector
uv sync
uv run pytest

# Lint and type-check (config in pyproject.toml); all must be clean.
uv run ruff check
uv run ruff format --check   # `uv run ruff format` applies it
uv run pyright

# Dev mode: serves /docs.
TELEMETRY_DEV=1 TELEMETRY_DB_PATH=/tmp/telemetry.sqlite3 uv run telemetry-collector-serve

# `day` must be a past UTC day; yesterday works (BSD or GNU date).
DAY=$(date -u -v-1d +%F 2>/dev/null || date -u -d yesterday +%F)
curl -i -X POST http://127.0.0.1:8000/t/feature -H 'content-type: application/json' \
  -d '{"channel":"dev","day":"'"$DAY"'","features":{"search":"1"},"available":["search"],"errors":["tls"]}'

# Report (read-only).
uv run telemetry-report --db /tmp/telemetry.sqlite3 --days 7

# Dashboard without sign-in (only possible together with TELEMETRY_DEV=1).
TELEMETRY_ROLE=dashboard TELEMETRY_DEV=1 DASHBOARD_AUTH=off \
  TELEMETRY_DB_PATH=/tmp/telemetry.sqlite3 TELEMETRY_PORT=8001 uv run telemetry-collector-serve
```

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `TELEMETRY_DB_PATH` | `telemetry.sqlite3` (`/data/telemetry.sqlite3` in the image) | SQLite database |
| `TELEMETRY_SCHEMA_PATH` | `telemetry-schema.json` next to the package source | Shared schema |
| `TELEMETRY_DEV` | off | Enables `/docs`, `/openapi.json` |
| `TELEMETRY_HOST` / `TELEMETRY_PORT` | `127.0.0.1` / `$PORT` or `8000` | API listener (the image sets `0.0.0.0` and `PORT=5000`, Dokku's convention) |
| `METRICS_HOST` / `METRICS_PORT` | `127.0.0.1` / unset | Prometheus listener; disabled unless `METRICS_PORT` is set |
| `TELEMETRY_ROLE` | `collector` | `collector` or `dashboard` |

Every schema channel is accepted, `dev` included: debug builds send to the
production collector, and the dashboard shows each channel separately.

Settings are read with pydantic-settings (`config.py`), from these exact
variable names only. There is no `.env` file support, so a stray file is never
picked up. Lists are comma-separated. An invalid value (e.g.
`TELEMETRY_DEV=maybe`) stops start-up with an error naming the variable.

## API behaviour

- `204` on success, with an empty body. The ping's counters are already
  written when the response is sent.
- `503` with an empty body if the database write fails; nothing from that
  ping is written.
- `400` with an empty body for malformed JSON, unknown fields, wrong types,
  values outside the schema (buckets, device, auth, channel, version formats),
  or a feature ping `day` out of range.
  `app` must look like `1.11` or `1.11.2`, `ios` like `18.3`, `lang` 2-3
  lowercase letters, `backend` `major.minor.patch` or `other`.
- Unknown feature names (in `features` or `available`) and unknown error names
  are dropped one by one; the rest of the ping is kept.
- `413` for bodies over 4 KiB. `features`, `available` and `errors` are
  limited to 64 entries of at most 64 characters.
- Required health fields: `channel app ios device lang client_cert
  custom_headers servers active_days_30 install_age`. Optional (omitted when
  unknown): `auth backend api docs`. Health pings carry no `errors`; a health
  ping with that field is rejected like any other unknown field.
- A feature ping reports exactly one completed UTC day. It requires `channel
  day features available` (`features` and `available` may be empty) and may
  carry `errors`, that day's setup error classes.
- `day` is `YYYY-MM-DD`, a real date strictly before the server's current UTC
  day and at most 30 days before it. Today, future days, older days and
  malformed dates are rejected with `400`.

## Storage

One table, `counters(day, channel, ping, field, value, count)`. Each accepted
ping adds one increment per field value. Health pings: `_pings/total` and every
scalar field (`client_cert` as `true`/`false`, `api` as its integer string).
Feature pings: `_pings/total`, `feature:<name>` with its bucket as value,
`available:<name>` with value `true`, and one `errors` row per distinct error.
Health counters are filed under the server's UTC receive day; feature counters
under the ping's `day`. Feature and error counts for recent days therefore keep
growing as installs report them when the app is next opened.

Each accepted ping's increments are written in one transaction (an UPSERT per
counter) before the response is sent; nothing is held in memory. The database
uses WAL mode with `secure_delete=ON`, and after each write the WAL is
checkpointed with `TRUNCATE`, so the write moves into the database file and
the WAL is emptied. If a dashboard read is in progress the checkpoint can stop
short, and the next write's checkpoint completes it.

## Reporting

`telemetry-report` prints, per day and channel, every field's value
counts (no small-count suppression; error classes appear under the feature
ping), `used/available` per feature, a warning
when feature pings exceed health pings by more than 1.5x, and an MAU estimate:
the sum over the last 30 days of health pings weighted by
`1 / midpoint(active_days_30)` (midpoints in `report.py`).

On the Dokku host (`enter` runs inside the live container; the report opens the
database read-only):

```sh
dokku enter telemetry web telemetry-report --days 14
```

## Deploy (Dokku)

The app is built from `Dockerfile` with `telemetry-collector/` as the build
directory, and Dokku's default nginx proxy sits in front of it. Replace
`telemetry`, the domain, the email address and the Tailscale IP:

```sh
dokku apps:create telemetry
dokku builder:set telemetry build-dir telemetry-collector
dokku ports:set telemetry http:80:5000

# Database volume. The container runs as uid 10001.
dokku storage:ensure-directory telemetry-data
sudo chown 10001:10001 /var/lib/dokku/data/storage/telemetry-data
dokku storage:mount telemetry /var/lib/dokku/data/storage/telemetry-data:/data

dokku config:set --no-restart telemetry \
  METRICS_HOST=0.0.0.0 METRICS_PORT=9100

dokku ps:scale telemetry web=1
# Old container stops before the new one starts, so two containers never clash
# on the published metrics port; costs a few seconds of downtime per deploy.
dokku checks:disable telemetry

# Metrics on the Tailscale address only.
dokku docker-options:add telemetry deploy "-p 100.x.y.z:9100:9100"

# Edge logging and body cap.
dokku nginx:set telemetry access-log-path off
dokku nginx:set telemetry error-log-path /dev/null
dokku nginx:set telemetry client-max-body-size 4k

# Per-IP rate limit (in-memory nginx zone): http-context zone + server-context limit.
sudo cp deploy/nginx-ratelimit.conf /etc/nginx/conf.d/telemetry-ratelimit.conf
sudo -u dokku mkdir -p /home/dokku/telemetry/nginx.conf.d
sudo -u dokku cp deploy/nginx.conf.d/ratelimit.conf /home/dokku/telemetry/nginx.conf.d/

dokku domains:set telemetry t.example.org
git push dokku main            # from a machine with the dokku remote
dokku letsencrypt:set telemetry email you@example.org
dokku letsencrypt:enable telemetry
dokku proxy:build-config telemetry
```

- The rate limit is 20 requests per minute per IP with a burst of 5, answered
  with 429. Dokku's default template defines no `limit_req` of its own, so its
  locations inherit the server-level one from `nginx.conf.d`. The zone file
  must exist before the app's nginx config is built, or `nginx -t` fails.
- Run nothing in front of nginx (no CDN or tunnel); it would see client IPs.
- Deploy collector updates (new feature or error names in the schema) before
  the app release that sends them; until then those names are dropped.
- Back up `/var/lib/dokku/data/storage/telemetry-data`, ideally with
  `sqlite3 .backup`.

### Resources

Measured idle RSS of the collector process: about 53 MB (Linux container,
`/proc/1/status`), about 37 MiB cgroup memory per `docker stats`. To cap it:
`dokku resource:limit --memory 128m telemetry`.

### Metrics

Prometheus metrics are served by a second listener inside the same process
(`prometheus_client`'s HTTP server thread) when `METRICS_PORT` is set. The
public app never serves `/metrics` (it 404s through nginx). Publish the port on
the Tailscale address only, as above, and scrape it from the tailnet.

Exported: request counts by endpoint (`health`/`feature`) and outcome
(`accepted`, `rejected_400`, `too_large`), write transactions by result
(`telemetry_writes_total`, `ok`/`error`), write duration including the
checkpoint, rows written, last write time, DB file size, and the default
process/Python metrics. Requests rejected by nginx (rate limit, body size)
never reach the collector and are not counted here.

## Dashboard

A read-only web view of the counters. It is the same image, run as a
second Dokku app with `TELEMETRY_ROLE=dashboard`, and serves no ingest routes.
The public collector serves no dashboard routes. It shows, per channel and for
a 7/30/90-day range:

- daily active installs (health pings) and a bar chart with implausible days
  highlighted
- an MAU estimate from `active_days_30`, using the same midpoints as the report
- installs under 7 and 30 days old on the latest day
- install-days per feature (used, available, ratio, bucket breakdown, and a
  "no use in range" flag)
- completion rates for `*_started` pairs
- error classes, as a share of feature pings

Feature pings report a day when the install next opens the app, so the feature
and error sections note that the last 7 days are still filling in, the feature
ratio chart draws those days dashed, and the feature-ping card shows the day
before the latest.
- every environment field's distribution

For optional fields (`auth`, `backend`, `api`, `docs`), an `unknown` row is
derived as health pings minus that field's counts; clients never send it. The
latest day can be partial.

The dashboard opens the database read-only (`mode=ro`) on each request. SQLite
WAL readers still need the `-shm` file, so the storage mount stays read-write.

### Rendering

Pages are Jinja2 templates (`src/telemetry_collector/templates/`) with
autoescaping on. Python only builds plain data for them.

The two charts use Chart.js: daily active installs, and each feature's
used/available ratio per day. The chart data is a JSON data block
(`<script type="application/json">`), read by `static/dashboard.js`. The
channel and range switches are plain links.

The Content-Security-Policy is `default-src 'none'; script-src 'self';
style-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'`.
There is no inline script or style, and no `unsafe-*` source.

Static files are served by the dashboard app only, behind sign-in. Their URLs
carry a content hash (`?v=…`), so they are sent with
`Cache-Control: private, max-age=31536000, immutable`. Pages are `no-store`.

**Vendored Chart.js:**

- Version 4.6.1, UMD build `dist/chart.umd.min.js`, from the npm package
  <https://www.npmjs.com/package/chart.js/v/4.6.1>, fetched with
  `npm pack chart.js@4.6.1`.
- The tarball's integrity matched the registry's `dist.integrity`
  (`sha512-hJyniucsFmq//EvXYvJ6c6mahPoI3kaxdjVH8awTaJ/fDNWeSqqqArixMJWkWNN6fcYvPU3HneSANFNYtRi61g==`).
- File SHA-256: `87364cc2b2a76a6684929e7d6b80b18a897794db38400caff1fcf1791c6925d2`.
- Stored unmodified at `static/vendor/chartjs/` with its `LICENSE.md` (MIT).
- To update: repeat with the new version and replace both files.

### Authentication

The dashboard uses the OIDC authorization code flow with PKCE (S256), as a
confidential client. The protocol and cryptography come from maintained
libraries:

- **Authlib** (Starlette client) handles discovery from `OIDC_ISSUER`,
  `state`, `nonce`, PKCE, the token request, JWKS fetching, and ID token
  validation: signature (algorithms advertised by the provider), `iss`,
  `aud`, `exp` and `nonce`.
- **Starlette's `SessionMiddleware`** keeps the login transaction and, after
  sign-in, the user, in an itsdangerous-signed `__Host-session` cookie
  (HttpOnly, Secure, SameSite=Lax, `Max-Age` 2 h). The session holds only
  `sub`, `email`, `groups` and an expiry.

Our own code is policy only:

- the allow-list and group check;
- the 2-hour expiry, checked server-side as well;
- the start-up refusals;
- the open-redirect guard on `next`;
- requiring the issuer in the discovery document to equal `OIDC_ISSUER`.

Every page except `/login`, `/auth/callback` and `POST /logout` redirects to
sign-in without a valid session.

Access requires every configured constraint to hold:

- `OIDC_REQUIRED_GROUP`, if set, must be in the token's `groups` claim;
- if `OIDC_ALLOWED_SUBJECTS` or `OIDC_ALLOWED_EMAILS` is set, the `sub` or a
  verified `email` must be listed.

The dashboard refuses to start with none of these set.

`DASHBOARD_AUTH=off` disables sign-in, and only together with `TELEMETRY_DEV=1`.
Otherwise the dashboard refuses to start.

| Variable | Meaning |
|---|---|
| `TELEMETRY_ROLE` | `dashboard` |
| `OIDC_ISSUER` | Issuer URL, e.g. `https://id.example.org` (must match discovery exactly) |
| `OIDC_CLIENT_ID` / `OIDC_CLIENT_SECRET` | Client credentials |
| `OIDC_REDIRECT_URI` | `https://dash.example.org/auth/callback` (must be https) |
| `OIDC_REQUIRED_GROUP` | Group name required in the `groups` claim |
| `OIDC_ALLOWED_SUBJECTS` / `OIDC_ALLOWED_EMAILS` | Comma-separated allow-lists |
| `DASHBOARD_SESSION_SECRET` | At least 32 characters, e.g. `openssl rand -hex 32` |
| `DASHBOARD_AUTH` | `oidc` (default) or `off` (dev mode only) |

**Pocket ID client:**

1. Create an OIDC client named e.g. "Telemetry dashboard". Make it a
   confidential client, not public, so it gets a client secret.
2. Set the callback URL to `https://dash.example.org/auth/callback`: the
   proxy's name, as browsers on the tailnet reach it. It must equal
   `OIDC_REDIRECT_URI`.
3. Enable PKCE if the client offers the option.
4. Create a group (e.g. `telemetry`), add yourself, and set
   `OIDC_REQUIRED_GROUP` to the group's name, not its friendly name. Pocket
   ID's own per-client allowed-groups restriction can be used in addition.

The dashboard requests the scopes `openid email profile groups`.

### Deploy (Dokku, Tailscale only)

```sh
dokku apps:create telemetry-dashboard
dokku builder:set telemetry-dashboard build-dir telemetry-collector
dokku ports:set telemetry-dashboard http:80:5000
# Same storage as the collector.
dokku storage:mount telemetry-dashboard /var/lib/dokku/data/storage/telemetry-data:/data
dokku config:set --no-restart telemetry-dashboard TELEMETRY_ROLE=dashboard \
  OIDC_ISSUER=https://id.example.org OIDC_CLIENT_ID=... OIDC_CLIENT_SECRET=... \
  OIDC_REDIRECT_URI=https://dash.example.org/auth/callback OIDC_REQUIRED_GROUP=telemetry \
  DASHBOARD_SESSION_SECRET="$(openssl rand -hex 32)"
dokku ps:scale telemetry-dashboard web=1

# Listen on the Tailscale addresses only (`tailscale ip -4` / `tailscale ip -6`).
dokku nginx:set telemetry-dashboard bind-address-ipv4 100.x.y.z
dokku nginx:set telemetry-dashboard bind-address-ipv6 fd7a:115c:a1e0::xxxx
dokku nginx:set telemetry-dashboard access-log-path off
dokku nginx:set telemetry-dashboard error-log-path /dev/null

dokku domains:set telemetry-dashboard dash.example.org
git push dokku-dashboard main   # a second git remote for this app
dokku proxy:build-config telemetry-dashboard
```

- **TLS** is terminated by the separate internal reverse proxy that holds the
  wildcard certificate. Dokku serves the dashboard over plain HTTP on the
  Tailscale address only; the hop from the proxy travels inside the tailnet.
  The proxy must forward `Host: dash.example.org` (the name in
  `domains:set`).
- **Tailscale ACLs:** allow port 80 on the Dokku VM's Tailscale address only
  from the proxy's node, so nothing else on the tailnet can bypass the proxy.
- **Issuer reachability:** the Dokku VM must reach `OIDC_ISSUER` directly, at
  exactly the issuer URL Pocket ID advertises in its discovery document. The
  dashboard fetches discovery, JWKS and tokens server-side and refuses an
  issuer mismatch.
- **Redirect URI:** `OIDC_REDIRECT_URI` is the proxy's name as reached on the
  tailnet (`https://dash.example.org/auth/callback`), not the Dokku VM's
  address.
- **Cookies** are always `Secure`. That works because browsers only talk
  HTTPS to the proxy; the app doesn't need to know about the proxy.
- **Check the bind:** `bind-address-ipv6` defaults to `::` (all addresses). If
  it is not set, the dashboard also listens publicly on IPv6. After
  `proxy:build-config`, check the generated `listen` lines with
  `dokku nginx:show-config telemetry-dashboard`. The IPv6 value is given
  without brackets; the template adds them.
- **Requests to the public IP:** a request there with
  `Host: dash.example.org` is served by the public listener's default server.
  The dashboard server block is not on that address, so the dashboard is not
  reachable there.
- **Zero-downtime deploys:** the dashboard never writes, so they can stay
  enabled for it; `checks:disable` is not needed.

**Boot order.** If a Tailscale address does not exist yet when nginx starts,
binding to it fails and the host's single nginx does not start, which takes
the public collector down too. (nginx binds only the wildcard socket when
another server on the same port listens on all addresses, as the collector
does, but do not rely on that.) Allow binding to addresses that are not up
yet (recommended):

```sh
printf 'net.ipv4.ip_nonlocal_bind = 1\nnet.ipv6.ip_nonlocal_bind = 1\n' \
  | sudo tee /etc/sysctl.d/99-nonlocal-bind.conf
sudo sysctl --system
```

The alternative is a systemd drop-in ordering `nginx.service` with
`After=tailscaled.service` and `Wants=tailscaled.service`. That orders the
start but does not wait until the address is assigned.

### Resources

Idle RSS of the dashboard process is about 69 MB (Linux container, with
Authlib, cryptography, httpx and Jinja2 loaded), and about 72 MB after
rendering pages. The collector process stays at about 53 MB, because the
collector role never imports the dashboard's dependencies; a test checks this.
The image is about 61 MB of content. A 90-day page renders in a few milliseconds
from about 45 days of seeded data. To cap it:
`dokku resource:limit --memory 128m telemetry-dashboard`.

## Privacy properties

- The app reads no request headers except `Content-Length` (for the body
  cap). It never reads the client address, runs uvicorn with
  `proxy_headers=False` and no access log, and routes only the two ingest
  paths; everything else returns an empty 404.
- Accepted trade-off of using Dokku's default nginx template: nginx does
  forward `X-Forwarded-For` (the client IP), `User-Agent` and
  `Accept-Language` to the app. They are not stripped at the edge; the app
  ignores them and never logs or stores them. (`nginx:set x-forwarded-for-value`
  can change but not remove the header; an empty value reverts to
  `$remote_addr`, so it is not relied on.)
- nginx access and per-app error logs are off (`access-log-path off`,
  `error-log-path /dev/null`), since nginx error lines include client IPs.
  The host's global `/var/log/nginx/error.log` still receives errors that
  happen before a server block is chosen (e.g. failed TLS handshakes); point
  `error_log` in `/etc/nginx/nginx.conf` at `/dev/null` if that matters.
- The only deliberate use of the client IP is nginx's in-memory `limit_req`
  zone, which is neither logged nor persisted.
- Request bodies are never logged or echoed. Error responses have empty
  bodies; FastAPI's validation handler is replaced.
- A feature ping's `day` reveals how long ago the install was last active
  (one to 30 days before the ping arrives). It is used only to choose the day
  the counters are filed under and is not stored on its own; the stored day
  carries the same information in aggregate.
- Only per-field counters per day and channel are stored, never a report, and
  nothing in storage joins a health ping to a feature ping. Each ping is
  written as it arrives, so two copies of the database taken one ping apart
  differ by that ping's counters, and in a small group (TestFlight, or a rare
  value) a day's counters can amount to a single install's report. This is
  accepted because pings carry only coarse values from a fixed list. Whoever
  controls the live server sees each payload, and that both pings come from
  the same IP, while receiving them.
- `/docs`, `/redoc` and `/openapi.json` are disabled in production.
- Metrics are operational only: no metric or label is derived from payload
  content, and there is no channel label, since a scraped content counter
  would be a per-request time series of payload values; a test enforces this.
- The dashboard is a separate process that only reads the counters
  (read-only connection). It is reachable only over Tailscale and behind OIDC.
  Its session cookie holds the subject, email, groups and an expiry, signed
  but not encrypted. Tokens are never logged or stored.
