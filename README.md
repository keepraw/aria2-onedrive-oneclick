# Aria2 OneDrive One-Click

A minimal, public-IP-friendly Aria2 download box for Debian 13.

- One browser UI: AriaNg
- Download engine: P3TERX Aria2 Pro
- Automatic upload: the Aria2 completion hook calls rclone `move` to OneDrive
- No server management panel, no Portainer, no Homepage, no separate rclone UI
- One-line installer from GitHub

The installer uses Docker Compose and performs the initial rclone configuration interactively. It does not silently claim that Microsoft OAuth can be skipped: you authorize OneDrive once during installation.

## Install

On a fresh Debian 13 x86_64/arm64 VPS, run as root:

```bash
curl -fsSL https://raw.githubusercontent.com/keepraw/aria2-onedrive-oneclick/main/install.sh | bash
```

The installer installs Docker Engine if needed, creates a random Aria2 RPC secret, starts Aria2 Pro and AriaNg, then launches the rclone OneDrive setup. Follow the prompts and create an rclone remote named `onedrive`.

After installation:

- AriaNg: `http://VPS_IP:6880`
- Aria2 RPC: TCP `6800` (used by AriaNg)
- BitTorrent/DHT: TCP+UDP `6888`

In AriaNg, set the RPC host to `http://VPS_IP`, port `6800`, path `/jsonrpc`, and paste the generated RPC secret shown by the installer.

## OneDrive setup

When prompted, create an rclone remote named exactly `onedrive`, choose storage type `Microsoft OneDrive`, and follow rclone's headless authorization flow. On a Windows machine with rclone installed, run the exact `rclone authorize` command printed by the VPS, sign in to Microsoft, then paste the returned token JSON back into the VPS prompt.

The installer validates the remote and creates `onedrive:RemoteDownloads`. Aria2's completion hook then uploads completed files with `rclone move`: the VPS source is removed only after a successful transfer. Failed uploads remain on the VPS for retry.

## Ports and security

| Port | Purpose |
| --- | --- |
| 6880/TCP | AriaNg web UI |
| 6800/TCP | Aria2 JSON-RPC |
| 6888/TCP+UDP | BitTorrent/DHT |

The RPC port is protected by a randomly generated high-entropy secret. Do not replace it with a short password. This setup uses plain HTTP for bare-IP access; HTTP does not encrypt the RPC secret in transit. Use a trusted network/VPN or add a domain with HTTPS before using it over untrusted networks. Do not expose RPC without the secret.

## Data

Everything is stored under `/opt/aria2-onedrive`:

- `config/`: Aria2 configuration, session, rclone configuration and upload logs
- `downloads/`: temporary download data; successfully uploaded files are moved off the VPS

## Management

```bash
cd /opt/aria2-onedrive
docker compose ps
docker compose logs -f aria2
docker compose pull && docker compose up -d
```

The `upgrade.sh` helper performs the pull/recreate operation. The `uninstall.sh` helper removes containers but preserves downloaded data and configuration unless `--purge` is explicitly supplied.

## Scope

Aria2 handles HTTP/HTTPS/FTP, BitTorrent and magnet links. It is not a plugin-based file-hosting resolver like JDownloader; sites that require proprietary link extraction, browser sessions or captcha-solving may need a direct download URL.

## Credits

- [P3TERX/Aria2-Pro-Docker](https://github.com/P3TERX/Aria2-Pro-Docker)
- [P3TERX/aria2.conf](https://github.com/P3TERX/aria2.conf)
- [AriaNg](https://github.com/mayswind/AriaNg)
- [rclone](https://rclone.org/)

The project orchestrates upstream containers and scripts; it does not redistribute their images.
