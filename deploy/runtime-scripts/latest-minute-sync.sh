#!/bin/sh
set -eu

APP=/data_n006/apps/mail-archive/app
LOG_DIR=/data_n006/apps/mail-archive/logs
LOCK=/tmp/nas-mail-latest.lock
WATCHDOG=/data_n006/apps/mail-archive/mail-health-watchdog.sh
TODAY=$(date '+%d-%b-%Y')

mkdir -p "$LOG_DIR"
exec 9>"$LOCK"
if ! flock -n 9; then
  exit 0
fi

if [ -x "$WATCHDOG" ]; then
  "$WATCHDOG" || {
    printf '[%s] skipped: watchdog repair failed\n' "$(date -Iseconds)" >> "$LOG_DIR/latest-minute.log"
    exit 1
  }
fi

if docker ps --format '{{.Names}}' | grep -Eq '^(nas-mail-slice-|nas-mail-sent)'; then
  printf '[%s] skipped: historical slice or sent sync active\n' "$(date -Iseconds)" >> "$LOG_DIR/latest-minute.log"
  exit 0
fi

cd "$APP"
set +e
timeout 20m docker compose run --rm --name nas-mail-latest-minute --entrypoint imapsync mail-sync \
  --host1 mail.ksomail.com \
  --user1 brian.lu@cimcwetrans.com \
  --passfile1 /run/secrets/wps_password \
  --ssl1 --port1 993 \
  --host2 127.0.0.1 \
  --user2 archive \
  --passfile2 /run/secrets/archive_password \
  --ssl2 --port2 993 \
  --automap \
  --syncinternaldates \
  --nofoldersizes \
  --nofoldersizesatend \
  --skipsize \
  --folder INBOX \
  --search "SINCE $TODAY" \
  --noreleasecheck \
  --logfile /var/log/mail-sync/latest-minute.log \
  >> "$LOG_DIR/latest-minute-runner.log" 2>&1
status=$?
set -e

if [ "$status" -ne 0 ]; then
  printf '[%s] latest INBOX sync failed: status=%s\n' "$(date -Iseconds)" "$status" >> "$LOG_DIR/latest-minute.log"
  docker rm -f nas-mail-latest-minute >/dev/null 2>&1 || true
  exit "$status"
fi
