#!/bin/sh
set -eu

APP=/data_n006/apps/mail-archive/app
LOG_DIR=/data_n006/apps/mail-archive/logs
LOCK=/tmp/nas-mail-watchdog.lock

mkdir -p "$LOG_DIR"

log() {
  printf '[%s] %s\n' "$(date -Iseconds)" "$*" >> "$LOG_DIR/mail-health-watchdog.log"
}

has_container() {
  docker ps -a --format '{{.Names}}' | grep -qx "$1"
}

has_running_container() {
  docker ps --format '{{.Names}}' | grep -qx "$1"
}

top_ok() {
  docker top "$1" >/dev/null 2>&1
}

exec 8>"$LOCK"
if ! flock -n 8; then
  exit 0
fi

if has_running_container nas-mail-latest-minute && ! top_ok nas-mail-latest-minute; then
  log "removing stale nas-mail-latest-minute: docker task is missing"
  docker rm -f nas-mail-latest-minute >/dev/null 2>&1 || true
fi

if has_running_container nas-mail-sent-latest && ! top_ok nas-mail-sent-latest; then
  log "removing stale nas-mail-sent-latest: docker task is missing"
  docker rm -f nas-mail-sent-latest >/dev/null 2>&1 || true
fi

tailscale_ok=false
dovecot_ok=false

if has_container nas-mail-tailscale && top_ok nas-mail-tailscale; then
  tailscale_ok=true
fi

if has_container nas-mail-dovecot && top_ok nas-mail-dovecot; then
  dovecot_ok=true
fi

if [ "$tailscale_ok" = true ] && [ "$dovecot_ok" = true ]; then
  exit 0
fi

if docker ps --format '{{.Names}}' | grep -Eq '^nas-mail-slice-'; then
  log "support containers unhealthy but historical slice is active; leaving it untouched"
  exit 0
fi

if docker ps --format '{{.Names}}' | grep -Eq '^(nas-mail-latest-minute|nas-mail-sent-latest)$'; then
  log "support containers unhealthy but a live latest sync is active; leaving it untouched"
  exit 0
fi

log "repairing support containers: tailscale_ok=$tailscale_ok dovecot_ok=$dovecot_ok"
cd "$APP"
docker compose up -d --force-recreate tailscale dovecot >> "$LOG_DIR/mail-health-watchdog.log" 2>&1

i=0
while [ "$i" -lt 30 ]; do
  if top_ok nas-mail-tailscale && top_ok nas-mail-dovecot; then
    log "repair complete: tailscale and dovecot docker tasks are healthy"
    exit 0
  fi
  i=$((i + 1))
  sleep 2
done

log "repair failed: docker task still unhealthy after waiting"
exit 1
