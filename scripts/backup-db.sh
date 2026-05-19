#!/usr/bin/env bash
# Daily MySQL backup → Backblaze B2 (EKS-202).
# Deliberately SEPARATE from the hobby stack's backup-to-b2.sh: its own
# rclone remote and its own bucket. Run from cron (see README).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

# Load .env without exporting it into anything else.
set -a; . ./.env; set +a

TS="$(date +%Y%m%d-%H%M%S)"
DUMP="/tmp/stugg-db-${TS}.sql.gz"
REMOTE="${BACKUP_RCLONE_REMOTE:-stugg-b2}"
BUCKET="${BACKUP_BUCKET:-stugg-db-backups}"
RETENTION="${BACKUP_RETENTION_DAYS:-14}"

cleanup() { rm -f "$DUMP"; }
trap cleanup EXIT

echo "[$(date -Is)] dumping ${DB_NAME}…"
docker compose exec -T mysql \
	mysqldump -uroot -p"${DB_ROOT_PASSWORD}" \
	--single-transaction --quick --databases "${DB_NAME}" \
	| gzip > "$DUMP"

echo "[$(date -Is)] uploading to ${REMOTE}:${BUCKET}/…"
rclone copy "$DUMP" "${REMOTE}:${BUCKET}/" --b2-hard-delete

echo "[$(date -Is)] pruning backups older than ${RETENTION}d…"
rclone delete "${REMOTE}:${BUCKET}/" --min-age "${RETENTION}d" --b2-hard-delete

echo "[$(date -Is)] backup ok: $(basename "$DUMP")"
