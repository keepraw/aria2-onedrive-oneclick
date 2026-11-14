#!/usr/bin/env bash
set -Eeuo pipefail
BASE="/opt/aria2-onedrive"
cd "$BASE"
curl -fsSL https://raw.githubusercontent.com/keepraw/aria2-onedrive-oneclick/main/docker-compose.yml -o docker-compose.yml
docker compose pull
docker compose up -d
docker image prune -f
echo "Upgrade complete. Data and rclone credentials were preserved."
