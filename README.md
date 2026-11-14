# Aria2 OneDrive One-Click

A minimal Aria2 download box for Debian 13, designed for a single public browser UI and automatic OneDrive offload.

- One WebUI: AriaNg on TCP 6880
- Download engine: P3TERX Aria2 Pro
- HTTP/HTTPS/FTP, BitTorrent and magnet links
- Automatic completion hook: rclone `move` to OneDrive
- No 1Panel, Portainer, Homepage, JDownloader or separate rclone UI
- One-line installer

## Install

Run as root on a fresh Debian 13 VPS (amd64 or arm64):

```bash
curl -fsSL https://raw.githubusercontent.com/keepraw/aria2-onedrive-oneclick/main/install.sh | bash
```

The installer installs Docker if needed, creates a random RPC secret, detects and reuses the existing host rclone configuration (including a remote named `o`), validates the selected remote, then starts the containers. If no host rclone configuration exists, it guides the one-time Microsoft OAuth setup.

For headless OAuth, rclone will print the exact `rclone authorize` command. Run it on a Windows PC with rclone installed, sign in to Microsoft, and paste the returned token JSON into the VPS prompt. No token is stored in this repository.

## Access

- AriaNg UI: `http://VPS_IP:6880`
- Aria2 RPC: `http://VPS_IP:6800/jsonrpc` (used by AriaNg; protected by a random 256-bit secret)
- BitTorrent/DHT: TCP+UDP `6888`

In AriaNg, configure RPC host `http://VPS_IP`, port `6800`, path `/jsonrpc`, and the RPC secret printed by the installer.

Open these ports in the VPS provider firewall and host firewall: TCP 6880, TCP 6800, TCP+UDP 6888.

**Security:** This bare-IP setup uses HTTP, not HTTPS. The RPC secret is not encrypted in transit. Do not use it over untrusted/public Wi-Fi. For stronger protection, use a VPN or later put the UI and RPC behind HTTPS with a domain. Never run Aria2 RPC without its random secret.

## Automatic OneDrive upload

The upstream Aria2 Pro image has a built-in `SPECIAL_MODE=rclone` completion hook. This project configures it to upload to `onedrive:RemoteDownloads` using `rclone move`.

- The source file is removed only after rclone reports successful transfer.
- Failed transfers remain on the VPS.
- The upstream upload hook retries failed transfers.
- Aria2 downloads directly to the VPS; rclone uploads directly from VPS to OneDrive.

The installer prefers the remote named `o` when present. Otherwise, it automatically selects the only configured remote, or asks you to choose when multiple remotes exist. It creates `RemoteDownloads` automatically.

## Persistent data

All persistent data is under `/opt/aria2-onedrive`:

- `config/`: Aria2 state, rclone credentials, upload scripts and logs
- `downloads/`: active and completed downloads awaiting upload
- `.env`: random Aria2 RPC secret

Protect this directory. It contains the Microsoft refresh token and RPC credential.

## Management

View status/logs:

```bash
cd /opt/aria2-onedrive
docker compose ps
docker compose logs -f aria2
```

Upgrade:

```bash
curl -fsSL https://raw.githubusercontent.com/keepraw/aria2-onedrive-oneclick/main/upgrade.sh | bash
```

Uninstall containers but preserve data:

```bash
curl -fsSL https://raw.githubusercontent.com/keepraw/aria2-onedrive-oneclick/main/uninstall.sh | bash
```

To also delete all downloads, configuration and OAuth credentials, run the downloaded uninstall script with `--purge` after reviewing it.

## Limitations

Aria2 supports direct HTTP/HTTPS/FTP URLs, BitTorrent and magnet links. It does not include JDownloader-style plugins for extracting links from every file-hosting website or handling arbitrary login/captcha workflows.

## Upstream projects

- [P3TERX/Aria2-Pro-Docker](https://github.com/P3TERX/Aria2-Pro-Docker) (MIT)
- [P3TERX/aria2.conf](https://github.com/P3TERX/aria2.conf) (MIT; upload hook)
- [AriaNg](https://github.com/mayswind/AriaNg)
- [rclone](https://rclone.org/)

This repository orchestrates upstream components and does not redistribute their source code.
