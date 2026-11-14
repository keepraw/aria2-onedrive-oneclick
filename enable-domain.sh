#!/usr/bin/env bash
set -Eeuo pipefail

BASE="/opt/aria2-onedrive"
REPO="keepraw/aria2-onedrive-oneclick"
DOMAIN="${1:-dl.557722.xyz}"

if [[ "$EUID" -ne 0 ]]; then
  echo "Run as root."
  exit 1
fi
if [[ ! -f "$BASE/.env" ]]; then
  echo "No existing installation at $BASE; use install.sh first."
  exit 1
fi
if ! [[ "$DOMAIN" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]]; then
  echo "Invalid domain: $DOMAIN"
  exit 1
fi

mkdir -p "$BASE"/{caddy-data,caddy-config}
umask 077
if grep -q '^DOMAIN=' "$BASE/.env"; then
  sed -i "s/^DOMAIN=.*/DOMAIN=$DOMAIN/" "$BASE/.env"
else
  printf '\nDOMAIN=%s\n' "$DOMAIN" >> "$BASE/.env"
fi

curl -fsSL "https://raw.githubusercontent.com/$REPO/main/Caddyfile" -o "$BASE/Caddyfile"
curl -fsSL "https://raw.githubusercontent.com/$REPO/main/docker-compose.yml" -o "$BASE/docker-compose.yml"

cd "$BASE"
docker compose config --quiet
docker compose pull
docker compose up -d

echo
echo "Domain gateway configured: https://$DOMAIN"
echo "The Caddy container must be able to listen on public TCP 80 and 443."
echo "Cloudflare DNS: dl -> VPS IP (Proxied/orange). SSL/TLS mode: Full (strict)."
echo "Check TLS issuance and startup with: docker compose logs --tail=100 caddy"
echo "AriaNg RPC: WebSocket, SSL enabled, host $DOMAIN, port 443, path /jsonrpc."
echo "Keep the existing Aria2 RPC secret in $BASE/.env."
echo "Previous 6800/6880 public port mappings are now removed."
