# Complete Setup Guide

This guide takes the stack from a fresh Docker host to a working media workflow. It is adapted to this repository from [farhantahir's self-hosted media-server guide](https://www.reddit.com/r/selfhosted/comments/pqt5yv/the_complete_guide_to_building_your_personal_self/) and updated for Docker Compose v2, pinned images, Prowlarr, Transmission, Traefik, and NVIDIA NVENC.

Use the services only with media and indexers you are legally authorized to access. This repository does not configure or recommend specific torrent indexers.

## 1. Understand the workflow

```text
Ombi / Overseerr
        |
        v
Sonarr / Radarr / Lidarr <---- Prowlarr or Jackett ----> indexers
        |                              |
        v                              +----> FlareSolverr when required
  Transmission
        |
        v
DATA_ROOT/torrents ---- hard link/import ----> DATA_ROOT/media
                                                |
                                                v
                                        Jellyfin / Plex
```

- Prowlarr manages indexers and synchronizes them to the *arr applications.
- Sonarr, Radarr, and Lidarr send downloads to Transmission and import completed files.
- Bazarr watches the Sonarr and Radarr libraries and adds subtitles.
- Jellyfin and Plex serve the completed libraries.
- Ombi or Overseerr provides a simpler request interface for other household users.
- Heimdall provides shortcuts to all web interfaces.
- Traefik provides memorable local hostnames.

Jackett overlaps with Prowlarr, and Ombi overlaps with Overseerr. They are all included so you can choose; most installations do not need both tools in either pair.

## 2. Prepare the host

### Windows

Install Docker Desktop, enable its WSL 2 backend, and make sure Linux containers are selected. Share or grant Docker access to the drives used by `SERVER_ROOT` and `DATA_ROOT`.

Jellyfin's own documentation does not officially support containerized Jellyfin hardware acceleration on Windows or macOS hosts. For the most predictable GPU transcoding, use a native Linux Docker host.

### Linux

Install Docker Engine and the Compose v2 plugin using the current [official Docker installation guide](https://docs.docker.com/engine/install/). Do not follow the Reddit post's old standalone `docker-compose` v1 installation commands.

After installation, verify the host:

```bash
docker version
docker compose version
docker run --rm hello-world
```

If you allow a non-root user to access Docker, understand that membership in the `docker` group is effectively root-level access. Follow Docker's [Linux post-installation guidance](https://docs.docker.com/engine/install/linux-postinstall/).

## 3. Clone and run the wizard

```bash
git clone https://github.com/HairyPloper/home-media-server-setup.git
cd home-media-server-setup
```

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

The wizard creates a private `.env`, builds the directory layout, validates Compose, and optionally pulls and starts the stack. The real `.env` is ignored by Git.

## 4. Storage layout and hard links

Keep `DATA_ROOT/media` and `DATA_ROOT/torrents` on the same filesystem. Sonarr, Radarr, and Lidarr receive the whole `DATA_ROOT` as `/data`, allowing imports to use hard links instead of storing a second full copy.

```text
SERVER_ROOT/
|-- configs/
|   |-- bazarr/
|   |-- jellyfin/
|   |-- plex/
|   `-- ...
`-- watch/

DATA_ROOT/
|-- media/
|   |-- movies/
|   |-- music/
|   `-- tv/
`-- torrents/
    |-- incomplete/
    |-- movies/
    |-- music/
    `-- tv/
```

On Linux, make the configured `PUID` and `PGID` own these directories:

```bash
sudo chown -R "$(id -u):$(id -g)" /path/to/SERVER_ROOT /path/to/DATA_ROOT
```

Do not run this command against `/`, your home directory, or an unverified path.

## 5. Start and inspect the stack

```bash
docker compose config --quiet
docker compose pull
docker compose up -d
docker compose ps
```

If a container is unhealthy or restarting:

```bash
docker compose logs --tail=100 SERVICE_NAME
```

Use the published localhost/LAN ports from the main README during initial configuration. Inside the Compose network, always prefer service names such as `http://sonarr:8989` instead of the host IP.

## 6. Configure Transmission first

1. Open `http://SERVER_IP:9095` and sign in with `TRANSMISSION_USER` and `TRANSMISSION_PASS` from your private `.env`.
2. Set the main download directory to `/data/torrents`.
3. Set incomplete downloads to `/data/torrents/incomplete`.
4. Confirm the peer port is `51413` inside the container; the host publishes it as `51414`.
5. Do not expose the Web UI to the internet.

The LinuxServer Transmission image reads its Web UI credentials from the `USER` and `PASS` environment variables. Change them in `.env`, then recreate the container with `docker compose up -d transmission`.

## 7. Configure Prowlarr or Jackett

### Recommended: Prowlarr

1. Open `http://SERVER_IP:8082`.
2. Add only indexers you are permitted to use and test each one.
3. Open **Settings > Apps** and add:

   | Application | Internal URL |
   |---|---|
   | Sonarr | `http://sonarr:8989` |
   | Radarr | `http://radarr:7878` |
   | Lidarr | `http://lidarr:8686` |

4. Copy each application's API key from its **Settings > General** page.
5. Test and save every connection. Prowlarr will synchronize compatible indexers.

### Alternative: Jackett

Open `http://SERVER_IP:8081`, configure an authorized indexer, and copy its Torznab feed URL and Jackett API key into each *arr application's **Settings > Indexers** page.

### FlareSolverr

Use FlareSolverr only for an indexer integration that explicitly supports it. Its internal URL is `http://flaresolverr:8191`. A successful test does not guarantee that every site challenge can be solved.

## 8. Configure Sonarr, Radarr, and Lidarr

Repeat these steps in each application:

1. Open its web interface.
2. In **Settings > Download Clients**, add Transmission:

   | Setting | Value |
   |---|---|
   | Host | `transmission` |
   | Port | `9091` |
   | Username | value of `TRANSMISSION_USER` |
   | Password | value of `TRANSMISSION_PASS` |

3. Test and save the download client.
4. Add the library root:

   | Application | Root folder |
   |---|---|
   | Sonarr | `/data/media/tv` |
   | Radarr | `/data/media/movies` |
   | Lidarr | `/data/media/music` |

5. Enable completed-download handling.
6. Enable hard links instead of copies in media-management settings.
7. Set a suitable quality profile and naming format before adding a large library.

The *arr applications and Transmission see downloads under the identical `/data/torrents` path. Do not add a remote-path mapping for this Compose deployment.

## 9. Configure Bazarr

Open `http://SERVER_IP:8086`, then connect:

| Application | Host | Port |
|---|---|---:|
| Sonarr | `sonarr` | 8989 |
| Radarr | `radarr` | 7878 |

Copy the corresponding API keys from Sonarr and Radarr. Select languages, providers, and subtitle profiles, then test with one known movie and episode before launching a full-library search.

## 10. Configure Jellyfin and Plex

### Jellyfin

1. Open `http://SERVER_IP:8087` and complete the administrator wizard.
2. Add libraries using these container paths:

   - Movies: `/data/media/movies`
   - Shows: `/data/media/tv`
   - Music: `/data/media/music`

3. Create separate non-administrator accounts for viewers.
4. Test direct playback before enabling transcoding.

For NVIDIA acceleration, install the host driver and NVIDIA Container Toolkit on native Linux, then verify:

```bash
docker compose exec jellyfin nvidia-smi
```

In Jellyfin's playback/transcoding settings, select **NVIDIA NVENC** and enable only codecs supported by the GPU. Follow Jellyfin's current [NVIDIA acceleration guide](https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/nvidia/) rather than the Reddit post's Intel VA-API example.

### Plex

Open `http://SERVER_IP:8088/web`, claim the server, and add the same `/data/media/...` library paths. If remote access is enabled, review the router and Plex security settings carefully rather than exposing unrelated stack ports.

You can operate Jellyfin, Plex, or both. Running both increases memory usage and duplicates library scans.

## 11. Configure requests

### Overseerr

Open `http://SERVER_IP:8090`, sign in with Plex, and connect Sonarr and Radarr using their internal service names, ports, and API keys.

### Ombi

Open `http://SERVER_IP:8089` and follow its wizard to connect Jellyfin or Plex plus Sonarr and Radarr.

Choose one request application for household users unless you have a specific reason to maintain both. Overseerr's upstream project and LinuxServer image are deprecated, so treat Ombi or a planned migration to Jellyseerr as the longer-term path.

## 12. Configure Heimdall and Traefik

Open `http://SERVER_IP:8094` and add tiles for the services you actually use.

The Compose labels also define `*.lan` Traefik routes. Add the hostnames from the main README to local DNS or the client hosts file, then access them through port 8080, for example:

```text
http://sonarr.lan:8080
http://jellyfin.lan:8080
```

The included dashboard uses Traefik's insecure local API and is published on port 8888. Keep it restricted to a trusted LAN. Before any internet exposure, disable the insecure dashboard, configure authenticated HTTPS, and prefer VPN access.

## 13. Validate the finished system

- Every container shows `Up` in `docker compose ps`.
- Prowlarr or Jackett can test an authorized indexer.
- Each *arr application can test Transmission and its indexers.
- A test download appears below `/data/torrents`.
- Import creates a file below the matching `/data/media` library.
- On Linux, `ls -li` shows the same inode for hard-linked download and library files.
- Bazarr can read the Sonarr and Radarr libraries.
- Jellyfin or Plex can scan and play the imported item.
- GPU monitoring shows activity during a forced transcode, if acceleration is enabled.

## 14. Back up and update

Back up `SERVER_ROOT/configs` before updates. Stop the stack for a consistent filesystem-level backup:

```bash
docker compose down
# Back up SERVER_ROOT/configs with your normal backup tool.
docker compose up -d
```

For routine image updates:

```bash
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100
```

This repository uses explicit image tags. Review upstream release notes and update the pins deliberately instead of switching to floating `latest` tags. Use `docker image prune` for dangling images; avoid broad destructive prune commands unless you have reviewed exactly what Docker will delete.

## What differs from the source guide

- Docker Compose v2 replaces the obsolete standalone Compose v1 installation.
- Transmission replaces qBittorrent/qFlood.
- Prowlarr is the recommended indexer manager; Jackett remains optional.
- Traefik is included for local routing.
- Images are pinned rather than using floating tags.
- NVIDIA NVENC instructions replace the source guide's Intel VA-API example.
- AdGuard Home and Readarr are not included in this stack.
- Remote access guidance favors a VPN or authenticated HTTPS instead of raw port forwarding.
