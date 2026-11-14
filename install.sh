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
mkdir -p "$BASE"/{config,downloads}
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

if [[ ! -f "$BASE/config/rclone.conf" ]]; then
  echo "[4/7] Configure OneDrive (one-time OAuth)."
  echo "Create an rclone remote named exactly: onedrive"
  echo "Choose Microsoft OneDrive. For headless authorization, follow rclone's"
  echo "on-screen instructions and run the displayed 'rclone authorize' command"
  echo "on your Windows PC, then paste the returned token JSON when prompted."
  docker run --rm -it -e RCLONE_CONFIG=/config/rclone.conf -v "$BASE/config:/config" rclone/rclone:latest config
  if [[ ! -s "$BASE/config/rclone.conf" ]]; then
    echo "rclone.conf was not created. Re-run this installer after completing OAuth."
    exit 1
  fi
fi

cat >"$BASE/config/script.conf" <<'EOF'
drive-name=onedrive
drive-dir=/RemoteDownloads
upload-log=/config/upload.log
delete-empty-dir=true
delete-dot-aria2=true
delete-dot-torrent=true
EOF
cat >"$BASE/config/rclone.env" <<'EOF'
RCLONE_CONFIG=/config/rclone.conf
RCLONE_TRANSFERS=2
RCLONE_RETRIES=3
RCLONE_RETRIES_SLEEP=10s
EOF
chmod 600 "$BASE/config/rclone.conf" "$BASE/config/script.conf" "$BASE/config/rclone.env"

echo "[5/7] Validating OneDrive remote..."
docker run --rm -v "$BASE/config:/config" rclone/rclone:latest   lsd onedrive: >/dev/null
docker run --rm -v "$BASE/config:/config" rclone/rclone:latest   mkdir onedrive:RemoteDownloads

echo "[6/7] Installing Compose project..."
curl -fsSL "https://raw.githubusercontent.com/$REPO/main/docker-compose.yml" -o "$BASE/docker-compose.yml"
cd "$BASE"
docker compose pull
docker compose up -d

RPC_SECRET="$(sed -n 's/^ARIA2_RPC_SECRET=//p' "$BASE/.env")"
PUBLIC_IP="$(curl -4fsS --max-time 8 https://api.ipify.org || true)"

echo "[7/7] Done."
echo
echo "AriaNg: http://${PUBLIC_IP:-YOUR_VPS_IP}:6880"
echo "Aria2 RPC: http://${PUBLIC_IP:-YOUR_VPS_IP}:6800/jsonrpc"
echo "RPC secret: $RPC_SECRET"
echo
echo "In AriaNg set RPC port 6800, path /jsonrpc, and paste the RPC secret."
echo "Open TCP 6880, TCP 6800, and TCP+UDP 6888 in your VPS firewall."
echo "IMPORTANT: HTTP does not encrypt the RPC secret. Use only on trusted networks,"
echo "or put the UI/RPC behind HTTPS/VPN before using it over an untrusted network."
