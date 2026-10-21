#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/docker-compose.yml"
ENV_FILE="$REPO_ROOT/.env"

read_default() {
  local prompt="$1"
  local default="$2"
  local answer
  read -r -p "$prompt [$default]: " answer
  printf '%s' "${answer:-$default}"
}

confirm() {
  local prompt="$1"
  local default="${2:-yes}"
  local suffix='[Y/n]'
  [[ "$default" == 'no' ]] && suffix='[y/N]'
  local answer
  read -r -p "$prompt $suffix: " answer
  answer="${answer,,}"
  if [[ -z "$answer" ]]; then
    [[ "$default" == 'yes' ]]
  else
    [[ "$answer" == 'y' || "$answer" == 'yes' ]]
  fi
}

dotenv_quote() {
  local value="$1"
  if [[ "$value" == *$'\n'* || "$value" == *"'"* ]]; then
    printf 'Values cannot contain newlines or single quotes.\n' >&2
    return 1
  fi
  printf "'%s'" "$value"
}

get_env_value() {
  local name="$1"
  local default="$2"
  local line=''
  if [[ -f "$ENV_FILE" ]]; then
    line="$(grep -m1 -E "^${name}=" "$ENV_FILE" || true)"
  fi
  if [[ -z "$line" ]]; then
    printf '%s' "$default"
    return
  fi
  local value="${line#*=}"
  value="${value#\'}"
  value="${value%\'}"
  value="${value#\"}"
  value="${value%\"}"
  printf '%s' "$value"
}

compose() {
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

printf '\nHome Media Server setup wizard\n'
printf '%s\n' '--------------------------------'

if ! command -v docker >/dev/null 2>&1; then
  printf 'Docker was not found. Install Docker Engine with the Compose v2 plugin.\n' >&2
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  printf 'Docker Compose v2 is not available.\n' >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  printf 'The Docker daemon is not running or is not accessible.\n' >&2
  exit 1
fi
if ! command -v nvidia-smi >/dev/null 2>&1; then
  printf 'Warning: no NVIDIA tooling was detected. Remove the Jellyfin/Plex GPU reservation blocks before starting on a CPU-only host.\n' >&2
fi

DEFAULT_DATA_ROOT="$(cd -- "$REPO_ROOT/.." && pwd)/home-media-server-data"
REUSE_ENV='no'
if [[ -f "$ENV_FILE" ]] && confirm 'An existing .env was found. Reuse it?' yes; then
  REUSE_ENV='yes'
fi

if [[ "$REUSE_ENV" == 'yes' ]]; then
  SERVER_ROOT="$(get_env_value SERVER_ROOT "$DEFAULT_DATA_ROOT")"
  DATA_ROOT="$(get_env_value DATA_ROOT "$SERVER_ROOT")"
  printf 'Using existing private settings from %s\n' "$ENV_FILE"
else
  SERVER_ROOT="$(read_default 'Configuration and stack directory' "$DEFAULT_DATA_ROOT")"
  DATA_ROOT="$(read_default 'Media and download data directory' "$SERVER_ROOT/data")"
  TIMEZONE="$(read_default 'IANA timezone' 'Etc/UTC')"
  PUID_VALUE="$(read_default 'Container PUID' "$(id -u)")"
  PGID_VALUE="$(read_default 'Container PGID' "$(id -g)")"
  TRANSMISSION_USER_VALUE="$(read_default 'Transmission username' 'media')"
  read -r -s -p 'Transmission password (leave blank to generate one): ' TRANSMISSION_PASS_VALUE
  printf '\n'
  if [[ -z "$TRANSMISSION_PASS_VALUE" ]]; then
    TRANSMISSION_PASS_VALUE="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
    printf 'Generated a random Transmission password and stored it only in .env.\n'
  fi

  if [[ -f "$ENV_FILE" ]]; then
    BACKUP_PATH="$ENV_FILE.$(date +%Y%m%d-%H%M%S).bak"
    cp -- "$ENV_FILE" "$BACKUP_PATH"
    printf 'Backed up the previous .env to %s\n' "$BACKUP_PATH"
  fi

  {
    printf 'COMPOSE_PROJECT_NAME=home-media-server\n'
    printf 'SERVER_ROOT=%s\n' "$(dotenv_quote "$SERVER_ROOT")"
    printf 'DATA_ROOT=%s\n' "$(dotenv_quote "$DATA_ROOT")"
    printf 'PUID=%s\n' "$PUID_VALUE"
    printf 'PGID=%s\n' "$PGID_VALUE"
    printf 'TZ=%s\n' "$(dotenv_quote "$TIMEZONE")"
    printf 'TRANSMISSION_USER=%s\n' "$(dotenv_quote "$TRANSMISSION_USER_VALUE")"
    printf 'TRANSMISSION_PASS=%s\n' "$(dotenv_quote "$TRANSMISSION_PASS_VALUE")"
  } > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  printf 'Created private settings at %s\n' "$ENV_FILE"
fi

CONFIG_DIRECTORIES=(
  configs/traefik configs/jackett configs/prowlarr configs/sonarr
  configs/radarr configs/lidarr configs/bazarr configs/jellyfin
  configs/plex configs/seerr configs/heimdall
  configs/transmission watch
)
for relative_path in "${CONFIG_DIRECTORIES[@]}"; do
  mkdir -p -- "$SERVER_ROOT/$relative_path"
done
DATA_DIRECTORIES=(
  media/movies media/music media/tv
  torrents/incomplete torrents/movies torrents/music torrents/tv
)
for relative_path in "${DATA_DIRECTORIES[@]}"; do
  mkdir -p -- "$DATA_ROOT/$relative_path"
done
printf 'Created configuration directories under %s\n' "$SERVER_ROOT"
printf 'Created media and download directories under %s\n' "$DATA_ROOT"

compose config --quiet
printf 'Compose configuration is valid.\n'

printf '\nChoose the next action:\n'
printf '  1. Finish after validation\n'
printf '  2. Pull container images\n'
printf '  3. Pull images and start the stack\n'
printf '  4. Stop the stack\n'
SELECTION="$(read_default 'Selection' '1')"

case "$SELECTION" in
  1) printf 'Setup complete. No containers were changed.\n' ;;
  2)
    compose pull
    printf 'Images downloaded. Run docker compose up -d when ready.\n'
    ;;
  3)
    compose pull
    compose up -d
    compose ps
    ;;
  4)
    if confirm 'Stop all services in this stack?' no; then
      compose down
    fi
    ;;
  *)
    printf 'Unknown selection: %s\n' "$SELECTION" >&2
    exit 1
    ;;
esac
