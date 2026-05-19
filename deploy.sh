#!/usr/bin/env bash
# Forced deploy command (EKS-49).
#
# The CI key in the server's authorized_keys is pinned to ONLY this script via
#   command="/opt/stugg/deploy.sh"
# so even a leaked key can never run arbitrary commands — it can only trigger
# a deploy. Whatever the CI `script:` sends is ignored; sshd runs this instead.
set -euo pipefail

cd /opt/stugg

echo "[$(date -Is)] pulling images…"
docker compose pull --quiet

echo "[$(date -Is)] restarting services…"
docker compose up -d --remove-orphans

echo "[$(date -Is)] pruning old images…"
docker image prune -f >/dev/null

# Health gate (EKS-191): the deploy is only "ok" once the frontend container
# reports healthy. Fail loudly otherwise so the CI job goes red.
echo "[$(date -Is)] waiting for frontend health…"
cid="$(docker compose ps -q frontend)"
for _ in $(seq 1 30); do
	state="$(docker inspect -f '{{.State.Health.Status}}' "$cid" 2>/dev/null || true)"
	if [ "$state" = "healthy" ]; then
		echo "[$(date -Is)] deploy OK — frontend healthy"
		exit 0
	fi
	sleep 5
done

echo "[$(date -Is)] DEPLOY FAILED — frontend not healthy after ~150s" >&2
docker compose ps >&2
exit 1
