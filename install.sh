#!/usr/bin/env bash
set -Eeuo pipefail

REPO="keepraw/aria2-onedrive-oneclick"
BASE="/opt/aria2-onedrive"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash"
  exit 1
fi

. /etc/os-release
if [[ "${ID:-}" != "debian" || "${VERSION_ID:-}" != "13" ]]; then
  echo "This installer currently targets Debian 13. Detected: ${PRETTY_NAME:-unknown}"
  exit 1
fi

ARCH="$(dpkg --print-architecture)"
case "$ARCH" in amd64|arm64) ;; *) echo "Unsupported architecture: $ARCH"; exit 1;; esac

echo "[1/7] Installing prerequisites..."
apt-get update
apt-get install -y ca-certificates curl gnupg jq unzip openssl

if ! command -v docker >/dev/null 2>&1; then
  echo "[2/7] Installing Docker Engine from Docker's official Debian repository..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  cat >/etc/apt/sources.list.d/docker.sources <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: trixie
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker
if ! docker compose version >/dev/null 2>&1; then
  apt-get update
  apt-get install -y docker-compose-plugin
fi

echo "[3/7] Preparing persistent directories..."
mkdir -p "$BASE"/{config,downloads,caddy-data,caddy-config}
chmod 700 "$BASE" "$BASE/config" "$BASE/downloads"

if [[ -e "$BASE/.env" ]]; then
  echo "Existing installation detected. Keeping existing secrets and configuration."
else
  RPC_SECRET="$(openssl rand -hex 32)"
  cat >"$BASE/.env" <<EOF
ARIA2_RPC_SECRET=$RPC_SECRET
TZ=Asia/Shanghai
EOF
  chmod 600 "$BASE/.env"
fi

# Keep DOMAIN in .env across subsequent reruns.
if ! grep -q '^DOMAIN=' "$BASE/.env"; then
  printf '%s\n' 'DOMAIN=dl.557722.xyz' >> "$BASE/.env"
fi
chmod 600 "$BASE/.env"

HOST_RCLONE_CONFIG=""
RCLONE_REMOTE=""

# Prefer the already-working host rclone configuration. This is important
# because Docker containers cannot see /root/.config/rclone automatically.
if command -v rclone >/dev/null 2>&1; then
  HOST_RCLONE_CONFIG="$(rclone config file 2>/dev/null | tail -n 1 || true)"
  if [[ -n "$HOST_RCLONE_CONFIG" && -s "$HOST_RCLONE_CONFIG" ]] && rclone listremotes 2>/dev/null | grep -qx 'o:'; then
    if rclone lsd o: >/dev/null 2>&1; then
      RCLONE_REMOTE="o"
      echo "[4/7] Found working host remote o:. Reusing its configuration."
      install -m 600 "$HOST_RCLONE_CONFIG" "$BASE/config/rclone.conf"
    fi
  fi
fi

# If there is already a project-specific config, keep it and discover its remote.
if [[ -z "$RCLONE_REMOTE" && -s "$BASE/config/rclone.conf" ]]; then
  echo "[4/7] Reusing existing project rclone configuration."
  REMOTE_LIST="$(docker run --rm -e RCLONE_CONFIG=/config/rclone.conf -v "$BASE/config:/config" rclone/rclone:latest listremotes)"
  if grep -qx 'o:' <<<"$REMOTE_LIST"; then
    RCLONE_REMOTE="o"
  else
    REMOTE_COUNT="$(grep -c ':' <<<"$REMOTE_LIST" || true)"
    if [[ "$REMOTE_COUNT" -eq 1 ]]; then
      RCLONE_REMOTE="${REMOTE_LIST%:}"
    fi
  fi
fi

# Only ask for OAuth if neither host nor project config can be reused.
if [[ -z "$RCLONE_REMOTE" ]]; then
  echo "[4/7] No usable existing rclone remote found. Starting first-time setup."
  docker run --rm -it -e RCLONE_CONFIG=/config/rclone.conf -v "$BASE/config:/config" rclone/rclone:latest config </dev/tty
  REMOTE_LIST="$(docker run --rm -e RCLONE_CONFIG=/config/rclone.conf -v "$BASE/config:/config" rclone/rclone:latest listremotes)"
  if grep -qx 'o:' <<<"$REMOTE_LIST"; then
    RCLONE_REMOTE="o"
  else
    REMOTE_COUNT="$(grep -c ':' <<<"$REMOTE_LIST" || true)"
    if [[ "$REMOTE_COUNT" -eq 1 ]]; then
      RCLONE_REMOTE="${REMOTE_LIST%:}"
    else
      echo "Available remotes:"
      printf '%s\\n' "$REMOTE_LIST"
      read -r -p "Enter remote name (without colon): " RCLONE_REMOTE </dev/tty
    fi
  fi
fi

if [[ -z "$RCLONE_REMOTE" ]]; then
  echo "No rclone remote selected."
  exit 1
fi

REMOTE_LIST="$(docker run --rm -e RCLONE_CONFIG=/config/rclone.conf -v "$BASE/config:/config" rclone/rclone:latest listremotes)"
if ! grep -Fqx "${RCLONE_REMOTE}:" <<<"$REMOTE_LIST"; then
  echo "Remote '$RCLONE_REMOTE' is not present in the copied rclone configuration."
  exit 1
fi

# Validate actual access before enabling automatic deletion after upload.
docker run --rm -e RCLONE_CONFIG=/config/rclone.conf -v "$BASE/config:/config" rclone/rclone:latest lsd "${RCLONE_REMOTE}:" >/dev/null

printf 'drive-name=%s\\ndrive-dir=/RemoteDownloads\\nupload-log=/config/upload.log\\ndelete-empty-dir=true\\ndelete-dot-aria2=true\\ndelete-dot-torrent=true\\n' "$RCLONE_REMOTE" >"$BASE/config/script.conf"
cat >"$BASE/config/rclone.env" <<'EOF'
RCLONE_CONFIG=/config/rclone.conf
RCLONE_TRANSFERS=2
RCLONE_RETRIES=3
RCLONE_RETRIES_SLEEP=10s
EOF
chmod 600 "$BASE/config/rclone.conf" "$BASE/config/script.conf" "$BASE/config/rclone.env"

echo "[5/7] Validating OneDrive remote..."
docker run --rm -e RCLONE_CONFIG=/config/rclone.conf -v "$BASE/config:/config" rclone/rclone:latest lsd "${RCLONE_REMOTE}:" >/dev/null
docker run --rm -e RCLONE_CONFIG=/config/rclone.conf -v "$BASE/config:/config" rclone/rclone:latest mkdir "${RCLONE_REMOTE}:RemoteDownloads"

echo "[6/7] Installing Compose project..."
if ss -ltn 2>/dev/null | grep -Eq '(:80|:443)[[:space:]]' && ! docker ps --format '{{.Names}}' | grep -qx aria2-caddy; then
  echo "WARNING: port 80 or 443 appears to be in use. Caddy may fail to start."
fi
curl -fsSL "https://raw.githubusercontent.com/$REPO/main/Caddyfile" -o "$BASE/Caddyfile"
curl -fsSL "https://raw.githubusercontent.com/$REPO/main/docker-compose.yml" -o "$BASE/docker-compose.yml"
cd "$BASE"
docker compose pull
docker compose up -d

RPC_SECRET="$(sed -n 's/^ARIA2_RPC_SECRET=//p' "$BASE/.env")"
PUBLIC_IP="$(curl -4fsS --max-time 8 https://api.ipify.org || true)"

echo "[7/7] Done."
echo
echo "AriaNg: https://$(sed -n 's/^DOMAIN=//p' "$BASE/.env")"
echo "Aria2 RPC: wss://$(sed -n 's/^DOMAIN=//p' "$BASE/.env")/jsonrpc"
echo "RPC secret: $RPC_SECRET"
echo
echo "In AriaNg choose WebSocket (WSS), host dl.557722.xyz, port 443, path /jsonrpc, then paste the RPC secret."
echo "Create a Cloudflare-proxied A record for dl.557722.xyz pointing to this VPS."\necho "Open TCP 80/443 and TCP+UDP 6888; close previous direct TCP 6800/6880."
echo "IMPORTANT: HTTP does not encrypt the RPC secret. Use only on trusted networks,"
echo "or put the UI/RPC behind HTTPS/VPN before using it over an untrusted network."
