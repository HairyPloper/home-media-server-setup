# Home Media Server

A Docker Compose media stack for Windows with Docker Desktop or a native Linux Docker host. It combines media management, indexers, request tools, download management, dashboards, and NVIDIA-enabled media servers behind Traefik.

## Services

| Service | Purpose | Local port |
|---|---|---:|
| Traefik | Reverse proxy and dashboard | 8080, 8443, 8888 |
| Jackett | Indexer proxy | 8081 |
| Prowlarr | Indexer manager | 8082 |
| Sonarr | TV library manager | 8083 |
| Radarr | Movie library manager | 8084 |
| Lidarr | Music library manager | 8085 |
| Bazarr | Subtitle manager | 8086 |
| Jellyfin | Media server | 8087 |
| Plex | Media server | 8088 |
| Ombi | Media request manager | 8089 |
| Overseerr | Plex request manager | 8090 |
| FlareSolverr | Proxy for supported indexers | 8093 |
| Heimdall | Application dashboard | 8094 |
| Transmission | BitTorrent client | 9095, 51414 |

All images use explicit stable tags for repeatable deployments. Jellyfin is deliberately pinned to its Ubuntu 24.04 build for conservative NVIDIA compatibility.

## Requirements

- Docker Engine with the Compose v2 plugin, or Docker Desktop on Windows
- At least 4 GB RAM; 8 GB or more is recommended
- Sufficient storage for media and downloads
- Optional: an NVIDIA GPU, current host driver, and NVIDIA Container Toolkit on native Linux

Do not expose these application ports directly to the public internet. The included Traefik configuration is intended for a trusted home network and local `*.local` hostnames.

## Quick setup wizard

1. Clone the repository and enter it:

   ```bash
   git clone https://github.com/HairyPloper/home-media-server-setup.git
   cd home-media-server-setup
   ```

2. Run the wizard for your platform.

   Windows PowerShell:

   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\scripts\setup.ps1
   ```

   Linux:

   ```bash
   chmod +x scripts/setup.sh
   ./scripts/setup.sh
   ```

The wizard:

- checks Docker, Compose v2, and the Docker daemon;
- asks where application data should live;
- creates every config, media, torrent, and watch directory;
- creates the ignored `.env` file and can generate a random Transmission password;
- validates the rendered Compose configuration; and
- offers to finish, pull images, start the stack, or stop it.

Existing `.env` settings are reused by default. Reconfiguring creates a timestamped, Git-ignored backup first. PowerShell automation can start immediately with `scripts\setup.ps1 -Start` or perform a non-interactive check of existing settings with `scripts\setup.ps1 -ValidateOnly`.

## Manual setup

1. Copy the environment template:

   ```bash
   cp .env.example .env
   ```

   In PowerShell:

   ```powershell
   Copy-Item .env.example .env
   ```

2. Edit `.env`:

   - Set `SERVER_ROOT` to an absolute host path.
   - Set `TZ` to an IANA timezone such as `Europe/Budapest`.
   - Set a unique Transmission username and a long random password.
   - On native Linux, set `PUID` and `PGID` to the account that owns the data directories. Find them with `id`.

3. Create the storage layout under `SERVER_ROOT`:

   ```text
   SERVER_ROOT/
   ├── configs/
   ├── media/
   │   ├── movies/
   │   ├── music/
   │   └── tv/
   ├── torrents/
   │   └── incomplete/
   └── watch/
   ```

   Each container creates its own folder below `configs` when first started.

4. Validate and start:

   ```bash
   docker compose config --quiet
   docker compose pull
   docker compose up -d
   docker compose ps
   ```

5. Open the services using the ports in the table, for example `http://localhost:8083` for Sonarr.

## Local Traefik names

The stack includes routes such as `sonarr.local` and `radarr.local`. To use them, point those names at the Docker host with local DNS or add entries to your hosts file. Examples:

```text
127.0.0.1 jackett.local prowlarr.local sonarr.local radarr.local lidarr.local
127.0.0.1 bazarr.local jellyfin.local plex.local ombi.local overseerr.local
127.0.0.1 flaresolverr.local heimdall.local transmission.local
```

With the supplied port mapping, HTTP routes are reached through `http://SERVICE.local:8080`.

## Application integration

Containers on the Compose network can reach one another by service name and internal port. Prefer these addresses when connecting applications:

- Sonarr: `http://sonarr:8989`
- Radarr: `http://radarr:7878`
- Lidarr: `http://lidarr:8686`
- Prowlarr: `http://prowlarr:9696`
- Transmission: `http://transmission:9091`
- FlareSolverr: `http://flaresolverr:8191`

Use `/data/media` for libraries and `/data/torrents` for downloads inside Sonarr, Radarr, Lidarr, Bazarr, and Transmission. Keeping the same container paths allows reliable imports and hard links where the host filesystem supports them.

## NVIDIA acceleration

Jellyfin and Plex request all available NVIDIA GPUs. Confirm GPU access with:

```bash
docker compose run --rm jellyfin nvidia-smi
```

If the host has no NVIDIA GPU, remove the `deploy.resources.reservations.devices` blocks from Jellyfin and Plex and remove the `NVIDIA_*` environment entries from Plex.

## Updating safely

Back up `SERVER_ROOT/configs` before changing image versions. Then:

```bash
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100
```

Review upstream release notes before changing major versions or the Jellyfin operating-system suffix. Avoid floating `latest` tags when repeatable rollbacks matter.

## Backups and recovery

The repository contains no application data. Back up the entire `configs` directory separately while the containers are stopped:

```bash
docker compose down
# Back up SERVER_ROOT/configs with your preferred tool.
docker compose up -d
```

Media and torrent data can be backed up independently according to your storage requirements.

## Security notes

- `.env` is ignored by Git and must never be committed.
- Change the example Transmission credentials before startup.
- Treat API keys generated by Sonarr, Radarr, Lidarr, Prowlarr, Bazarr, Ombi, and Overseerr as secrets.
- Do not commit anything from `SERVER_ROOT/configs`; it contains databases, tokens, logs, and account details.
- Restrict host firewall access to trusted LAN devices or place remote access behind authenticated HTTPS or a VPN.
