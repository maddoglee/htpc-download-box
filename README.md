# Automated Media Downloader Stack

qBittorrent • Gluetun (ProtonVPN WireGuard + Port Forwarding) • Prowlarr • Sonarr • Radarr • Bazarr • autobrr • FlareSolverr • Jellyseerr • Profilarr

A Docker Compose-based stack for automated TV & movie downloads routed securely through a VPN. Torrent traffic is isolated via **Gluetun** (ProtonVPN WireGuard) with port forwarding and a firewall killswitch. Indexers are managed by **Prowlarr**, grabbing can be accelerated by **autobrr**, **FlareSolverr** bypasses Cloudflare for indexers, **Bazarr** handles subtitles, **Jellyseerr** provides user-friendly requests, and **Profilarr** helps fine-tune ARR profiles.

---

## Table of Contents

- #overview
- #included-services
- #architecture
- #requirements
- #directory-layout
- #environment-variables
- #quick-start
- #service-configuration
  - #gluetun-protonvpn-wireguard
  - #qbittorrent
  - #prowlarr
  - #autobrr
  - #flaresolverr
  - #sonarr
  - #radarr
  - #bazarr
  - #jellyseerr
  - #profilarr
- #maintenance
- #notes--tips
- #troubleshooting
- #license

---

## Overview

This repository deploys an automated torrent workflow where:

1. **Sonarr/Radarr** monitor series and movies.
2. **Prowlarr** aggregates torrent indexers and syncs them to Sonarr/Radarr.
3. **autobrr** grabs elite releases via IRC/RSS instantly.
4. **qBittorrent** downloads, fully routed through **Gluetun** (ProtonVPN WireGuard + port forwarding).
5. **FlareSolverr** solves Cloudflare on indexers when needed.
6. **Bazarr** automatically fetches subtitles.
7. **Jellyseerr** provides a modern request interface.
8. **Profilarr** helps optimize ARR profiles and settings.

Services that touch public torrent/indexers run *inside* the VPN network (via `network_mode: "service:gluetun"`). ARR apps and Jellyseerr run on the host network for easy LAN access.

---

## Included Services

| Service        | Purpose                                                | Network                          |
|----------------|--------------------------------------------------------|----------------------------------|
| Gluetun        | ProtonVPN WireGuard tunnel + firewall + port forward   | Host (exposes ports)             |
| qBittorrent    | Torrent client                                         | Through Gluetun                  |
| Prowlarr       | Indexer manager (feeds Sonarr/Radarr)                  | Through Gluetun                  |
| autobrr        | Real-time grabs via IRC/RSS                            | Through Gluetun                  |
| FlareSolverr   | Cloudflare solver for indexers                         | Through Gluetun                  |
| Sonarr         | TV automation                                          | Host network                     |
| Radarr         | Movie automation                                       | Host network                     |
| Bazarr         | Subtitle management                                    | Host network                     |
| Jellyseerr     | Requests portal                                        | Host network                     |
| Profilarr      | ARR profiles/quality optimization                      | Host network                     |

> **Not included on purpose:** Plex/Emby/Jellyfin, Usenet clients (NZBGet/SAB), Jackett, OpenVPN.

---

## Architecture

```
Sonarr ──┐
         ├── Prowlarr ── FlareSolverr ───┐
Radarr ──┘                                │
                                          ├── autobrr ── qBittorrent ── Gluetun (ProtonVPN WG + PF)
Bazarr (subtitles)                         │
                                           │
Jellyseerr (requests)                     ┘
Profilarr (ARR tuning)
```

- **VPN boundary:** qBittorrent, Prowlarr, autobrr, FlareSolverr are forced through Gluetun.
- **LAN boundary:** Sonarr/Radarr/Bazarr/Jellyseerr/Profilarr remain on host for stable local ports and file access.

---

## Requirements

- Docker & Docker Compose
- ProtonVPN account with **WireGuard** and **Port Forwarding** support
- A Linux server, mini PC, or SBC (e.g., Pi 4/5, Rock 4C+)
- Storage for media and configs
- Basic Docker volume/permissions knowledge

---

## Directory Layout

Recommended layout relative to the `docker-compose.yml`:

```
project-root/
├─ docker-compose.yml
├─ .env
├─ config/
│  ├─ gluetun/
│  ├─ qbittorrent/
│  ├─ prowlarr/
│  ├─ autobrr/
│  ├─ flaresolverr/
│  ├─ sonarr/
│  ├─ radarr/
│  ├─ bazarr/
│  ├─ jellyseer/
│  └─ profilarr/
└─ media/
   ├─ torrents/
   ├─ movies/
   ├─ tv/
   └─ trackerfiles/
```

> Adjust to your own paths; match volumes in `docker-compose.yml`.

---

## Environment Variables

Create a `.env` file next to `docker-compose.yml`:

```env
TZ=Australia/Canberra
PUID=1000
PGID=1000

# Your media root (used by volumes)
DATA=/mnt/media

# ProtonVPN WireGuard private key (keep secret)
PROTONPRIVATE=YOUR_PROTONVPN_WG_PRIVATE_KEY
```

> Ensure the `PUID`/`PGID` user has read/write permissions on `config/` and your `${DATA}` paths.

---

## Quick Start

1. **Edit `.env`** with your timezone, user IDs, storage path, and **ProtonVPN WireGuard private key**.
2. **Ensure directory structure** exists and matches your volumes.
3. **Start the stack:**
   ```bash
   docker compose up -d
   ```
4. **Verify VPN is healthy** and port forwarding is active:
   ```bash
   docker compose logs -f gluetun
   ```
5. Visit service UIs (see ports below), configure indexers/clients, and enjoy.

> This README assumes the compose publishes:
> - Gluetun Control Panel/API: `8000`
> - qBittorrent Web: `8080`
> - Prowlarr: `9696`
> - FlareSolverr: `8191`
> - autobrr: `7474`
> - Sonarr: default `8989` (host network)
> - Radarr: default `7878` (host network)
> - Bazarr: default `6767` (host network)
> - Jellyseerr: `5055` (host network)
> - Profilarr: `6868` (host network)

---

## Service Configuration

### Gluetun (ProtonVPN WireGuard)

- Runs the VPN tunnel and firewall.
- **Port forwarding** enabled for better seeding and tracker connectivity.
- IPv6 is disabled to avoid leaks.
- DNS points to AdGuard (LAN) with Cloudflare fallback.
- Control API exposed on host port **8000**.

**Healthcheck note:** compose uses a curl check; logs may show health cycling until forwarding & connectivity stabilize.

**Files/Env highlights (from compose):**
- `VPN_SERVICE_PROVIDER=protonvpn`
- `VPN_TYPE=wireguard`
- `WIREGUARD_PRIVATE_KEY=${PROTONPRIVATE}`
- `SERVER_COUNTRIES=Australia`
- `SERVER_CITIES=Sydney`
- `VPN_PORT_FORWARDING=on`
- `VPN_PORT_FORWARDING_PROVIDER=protonvpn`
- `FIREWALL=on`
- `FIREWALL_OUTBOUND_SUBNETS=192.168.1.0/24`
- `VPN_DISABLE_IPV6=true`
- Volume: `./config/gluetun:/gluetun`

**Web/Control:** `http://<host>:8000`

---

### qBittorrent

- Runs **inside Gluetun** (`network_mode: "service:gluetun"`).
- Web UI: `http://<host>:8080`
- Volumes include:
  - `./config/qbittorrent:/config`
  - `${DATA}/torrents:/data/torrents`
  - `/home/lee/trackerfiles/:/trackerfiles`
  - `/home/lee/torrents:/torrents` (if you use it, map consistently across apps)

**Recommended qBittorrent settings:**
- Set `Downloads` to `/data/torrents` (or your mapped path)
- Web UI Port: `8080`
- Confirm **listening port** matches Gluetun forwarded port (Gluetun should handle updating)
- Enable `Anonymous Mode` and `Use different port on each startup = OFF` (to keep PF stable)

---

### Prowlarr

- Runs **inside Gluetun**.
- UI: `http://<host>:9696`
- Volume: `./config/prowlarr:/config`

**Setup steps:**
1. Add Indexers (public/private).
2. Configure **Proxy** to **FlareSolverr** (`http://flaresolverr:8191` if same network; if using Gluetun service-mode, use `http://localhost:8191` from Prowlarr’s perspective since it shares the network namespace).
3. Connect to **Sonarr** and **Radarr** so indexers sync downstream.
4. Map tracker categories (e.g., TV/Anime → Sonarr, Movies → Radarr).

---

### autobrr

- Runs **inside Gluetun**.
- UI: `http://<host>:7474`
- Volume: `./config/autobrr:/config`
- User: `1000:1000`

**Setup steps:**
1. Add **qBittorrent** client (host `localhost`, port `8080`, creds).
2. Add IRC or RSS sources for your trackers.
3. Create filters (resolutions, encoders, freeleech, scene/P2P, etc.).
4. Test announces and ensures they land in qBittorrent.

---

### FlareSolverr

- Runs **inside Gluetun**.
- No UI; listens on port `8191`.
- Used by Prowlarr to bypass Cloudflare for protected indexers.

**Setup in Prowlarr:**  
`Settings → Proxies → Add → FlareSolverr → http://localhost:8191` (same network namespace due to `service:gluetun`).

---

### Sonarr

- **Host network** (not behind VPN).
- Default UI: `http://<host>:8989`
- Volumes (example):
  - `./config/sonarr:/config`
  - `${DATA}:/data`
  - `/home/lee/torrents:/torrents` (if needed)

**Configure:**
- Root folder: `/data/tv`
- Completed downloads: `/torrents` or `/data/torrents` (match your actual mappings!)
- Add **qBittorrent** as a download client (host: `localhost`, port: `8080` from Sonarr’s network if qBittorrent shares host ports; otherwise use the exposed host IP/port).
- Add **Prowlarr** as an indexer source (preferred via sync).
- Enable Completed Download Handling; set `Remove` if you want Sonarr to remove finished torrents after import (optional).

---

### Radarr

- **Host network** (not behind VPN).
- Default UI: `http://<host>:7878`
- Volumes (example):
  - `./config/radarr:/config`
  - `${DATA}:/data`
  - `/home/lee/torrents:/torrents` (if needed)

**Configure:**
- Root folder: `/data/movies`
- Same download client/indexer approach as Sonarr.
- Enable import/rename preferences per your liking.

---

### Bazarr

- **Host network** (not behind VPN).
- Default UI: `http://<host>:6767`
- Volumes:
  - `./config/bazarr:/config`
  - `${DATA}/media:/data/media` (or map `/data/movies` and `/data/tv` separately, depending on your compose)

**Configure:**
- Connect to Sonarr & Radarr (API keys).
- Add subtitle providers (OpenSubtitles, Subscene, etc.).
- Set preferred languages and defaults.

---

### Jellyseerr

- **Host network** (not behind VPN).
- UI: `http://<host>:5055`
- Volume: `./config/jellyseer:/app/config`

**Configure:**
- Connect to Sonarr & Radarr.
- Configure libraries and request rules.
- Set user access and notifications.

---

### Profilarr

- **Host network** (not behind VPN).
- UI: `http://<host>:6868`
- Volume: `./config:/config` (as per your compose snippet for Profilarr)

**Configure:**
- Connect to Sonarr & Radarr.
- Apply/adjust streaming-target profiles, quality cutoffs, and rules.

---

## Maintenance

**Start:**
```bash
docker compose up -d
```

**Stop:**
```bash
docker compose down
```

**Update images:**
```bash
docker compose pull

docker compose up -d
```

**Follow logs (example):**
```bash
docker compose logs -f gluetun
```

**Prune old images:**
```bash
docker image prune -f
```

---

## Notes & Tips

- **Port Forwarding:** Gluetun with ProtonVPN PF is essential for healthy seeding and tracker connectivity.
- **Firewall:** With `FIREWALL=on`, containers using `service:gluetun` are protected from leaks if the VPN drops.
- **DNS:** AdGuard on LAN → Cloudflare fallback keeps lookups reliable.
- **Healthcheck:** The provided curl check verifies VPN PF state; short-term failures may occur during negotiation.
- **Permissions:** Match `PUID`/`PGID` and ensure your user owns the bind-mounted paths.
- **Paths:** Keep `/data` and `/torrents` paths consistent across all ARR apps and clients.

---

## Troubleshooting

- **qBittorrent not reachable?**  
  Confirm Gluetun is healthy, and that port `8080:8080` is published on **gluetun** (since qBittorrent shares its network namespace).

- **Indexers failing with Cloudflare?**  
  Ensure Prowlarr uses the **FlareSolverr** proxy URL reachable from within the same network namespace (often `http://localhost:8191` for services joined to Gluetun).

- **Sonarr/Radarr can’t access downloads for import:**  
  Verify both ARR apps and qBittorrent see the **same absolute paths** (e.g., `/data/torrents`), or configure Remote Path Mappings.

- **Port forwarding shows 0 or closed in logs:**  
  Make sure your ProtonVPN plan/endpoint supports PF and that `VPN_PORT_FORWARDING=on` is set. Try a different ProtonVPN city that supports PF.

- **Permissions errors on import/rename:**  
  Ensure `PUID`/`PGID` match your filesystem owner, and fix with `chown -R 1000:1000 <path>` if needed.

---

## License

This repository’s documentation is provided under the MIT License. Container images are licensed by their respective authors.

---
