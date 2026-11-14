#!/usr/bin/env bash
set -Eeuo pipefail
BASE="/opt/aria2-onedrive"
cd "$BASE"
if ! grep -q '^DOMAIN=' .env; then
  printf '\nDOMAIN=dl.557722.xyz\n' >>.env
fi
mkdir -p caddy-data caddy-config
curl -fsSL https://raw.githubusercontent.com/keepraw/aria2-onedrive-oneclick/main/Caddyfile -o Caddyfile
curl -fsSL https://raw.githubusercontent.com/keepraw/aria2-onedrive-oneclick/main/docker-compose.yml -o docker-compose.yml
docker compose config --quiet
docker compose pull
docker compose up -d
docker image prune -f
echo "Upgrade complete. Data and rclone credentials were preserved."
