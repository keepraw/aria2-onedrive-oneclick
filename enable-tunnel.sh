#!/usr/bin/env bash
set -Eeuo pipefail

BASE="/opt/aria2-onedrive"
RAW="https://raw.githubusercontent.com/keepraw/aria2-onedrive-oneclick/fix/cloudflare-tunnel-ghost-safe"
DOMAIN="dl.557722.xyz"

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root."
  exit 1
fi

if [[ ! -s "$BASE/.env" || ! -s "$BASE/config/rclone.conf" ]]; then
  echo "Existing Aria2 installation not found or incomplete. Stop; do not change Ghost."
  exit 1
fi

echo "Create a Cloudflare Tunnel for this VPS in Cloudflare Zero Trust."
echo "Use a published application route:"
echo "  Hostname: $DOMAIN"
echo "  Service:  http://caddy:8080"
echo "Copy the tunnel TOKEN only (not the entire Docker command)."
if [[ ! -r /dev/tty ]]; then
  echo "Interactive terminal required."
  exit 1
fi
read -r -s -p "Cloudflare Tunnel token (hidden): " TOKEN </dev/tty
echo

if [[ ! "$TOKEN" =~ ^[A-Za-z0-9._=-]{32,}$ ]]; then
  echo "Token format is not recognized. Aborting."
  exit 1
fi

umask 077
if grep -q '^CLOUDFLARE_TUNNEL_TOKEN=' "$BASE/.env"; then
  sed -i "s|^CLOUDFLARE_TUNNEL_TOKEN=.*$|CLOUDFLARE_TUNNEL_TOKEN=$TOKEN|" "$BASE/.env"
else
  printf '\nCLOUDFLARE_TUNNEL_TOKEN=%s\n' "$TOKEN" >> "$BASE/.env"
fi
chmod 600 "$BASE/.env"
unset TOKEN

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "$RAW/Caddyfile" -o "$TMP/Caddyfile"
curl -fsSL "$RAW/docker-compose.yml" -o "$TMP/docker-compose.yml"

( cd "$BASE" && docker compose --env-file "$BASE/.env" -f "$TMP/docker-compose.yml" --profile tunnel config --quiet )

cp "$TMP/Caddyfile" "$BASE/Caddyfile"
cp "$TMP/docker-compose.yml" "$BASE/docker-compose.yml"
cd "$BASE"
docker compose --profile tunnel pull
docker compose --profile tunnel up -d

echo
echo "Tunnel started: https://$DOMAIN"
echo "Cloudflare published route must point to http://caddy:8080."
echo "AriaNg RPC: WSS, host $DOMAIN, port 443, path /jsonrpc, existing RPC secret."
echo "This project binds no host TCP 80/443 and does not modify Ghost."
echo "Logs: docker compose --profile tunnel logs --tail=80 cloudflared"
