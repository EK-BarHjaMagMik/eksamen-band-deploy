# eksamen-band-deploy

Server target state for the Stügg band site (EKS-50). This repo is cloned to
**`/opt/stugg/`** on the server. It is fully isolated from any other stack on
the box: Compose gives this project its own network, its own named volumes,
its own `.env`, and its own backups. It does not touch, share, or depend on
anything else.

```
caddy (:80/:443)  ──►  frontend (:80, static)
        │
        └──/api/*──►   backend (:8080) ──► mysql (:3306, internal only)
```

The container images come from GHCR (built by the EKS-48 workflows). Caddy is
the public reverse proxy and terminates HTTPS via Let's Encrypt.

## First-time setup

1. **Clone to the server**
   ```bash
   sudo mkdir -p /opt/stugg && sudo chown "$USER" /opt/stugg
   git clone <repo-url> /opt/stugg && cd /opt/stugg
   ```
2. **Configure secrets**
   ```bash
   cp .env.example .env && nano .env   # set DB passwords, ACME_EMAIL, etc.
   ```
3. **Router** — forward external TCP **80 and 443** to this server's LAN IP
   (`192.168.8.198`). Nothing else is forwarded; SSH stays off the internet.
4. **DNS** — point `stugg.dk` (and `www`) at the connection's public IP.
   Because the IP is dynamic, move the zone to Cloudflare (DNS-only / grey
   cloud), create a scoped `Zone:DNS:Edit` token, put it in `.env` as
   `CF_API_TOKEN`, and run the DDNS updater (step 6). Registrar stays
   simply.com — only the nameservers change.
5. **Bring the stack up**
   ```bash
   docker compose pull
   docker compose up -d
   ```
   Caddy will obtain certificates automatically **once DNS resolves to the
   server and 80/443 are reachable** — until then HTTPS will not work, which
   is expected.
6. **Enable DDNS** (after DNS is on Cloudflare) — a standalone container,
   kept separate from the app stack on purpose:
   ```bash
   docker run -d --name stugg-ddns --restart unless-stopped --network host \
     -e CLOUDFLARE_API_TOKEN="$CF_API_TOKEN" \
     -e DOMAINS=stugg.dk -e PROXIED=false \
     favonia/cloudflare-ddns:latest
   ```
   (`--network host` so it can read the connection's real public IP.
   Post-exam hardening flips `PROXIED=true`.)

## Day-to-day

```bash
docker compose ps                 # status
docker compose logs -f caddy      # tail a service
docker compose pull && docker compose up -d   # update to newest images
docker compose down               # stop (data survives — named volumes)
```

## Backups & restore (EKS-202 / EKS-203)

`scripts/backup-db.sh` dumps the database and pushes it to a **dedicated**
Backblaze B2 bucket via its own rclone remote (not shared with anything else).

Set up the rclone remote once on the server (`rclone config`, B2 backend,
named to match `BACKUP_RCLONE_REMOTE` in `.env`), then add a cron entry:

```cron
# /opt/stugg own crontab — daily 03:30
30 3 * * * cd /opt/stugg && ./scripts/backup-db.sh >> /opt/stugg/backup.log 2>&1
```

**Restore procedure (tested):**

```bash
# 1. Pull the desired dump from B2
rclone copy stugg-b2:stugg-db-backups/stugg-db-YYYYMMDD-HHMMSS.sql.gz /tmp/

# 2. Stream it back into the running mysql container
gunzip -c /tmp/stugg-db-YYYYMMDD-HHMMSS.sql.gz \
  | docker compose exec -T mysql mysql -uroot -p"$DB_ROOT_PASSWORD"

# 3. Restart the backend so it picks up a clean connection pool
docker compose restart backend
```

## Known follow-ups (deliberately out of EKS-50 scope)

- **Per-IP rate limiting on `/api`.** Caddy's `request_body` size cap *is*
  configured (native, the main upload-abuse guard). Per-IP rate limiting needs
  a third-party module (custom `xcaddy` build), which would mean this stack
  can no longer just pull the official image. Left out to keep the exam
  deployment simple; add via a custom Caddy image when hardening.
- **Spring multipart limits.** EKS-17 must raise
  `spring.servlet.multipart.max-file-size` / `max-request-size` (Spring's
  defaults are tiny) for real photo uploads. App config — not this repo.

## Post-exam roadmap (not exam scope)

After the exam this becomes a real hosted site for the band. Planned hardening:
move Cloudflare DNS to **proxied** (orange-cloud — set `DDNS_PROXIED=true`) for
DDoS protection and a hidden origin IP, and switch photo uploads to
**presigned direct-to-storage** (B2/R2) so large/bulk uploads bypass the
proxy's request-body cap. Both are separate future stories; nothing here
needs to change for the exam.
