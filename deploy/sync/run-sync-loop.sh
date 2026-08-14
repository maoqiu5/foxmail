#!/bin/sh
set -eu

LOG_DIR=/var/log/mail-sync
LOCK_FILE=/tmp/nas-mail-imapsync.lock
mkdir -p "$LOG_DIR"
exec 9>"$LOCK_FILE"

run_once() {
  timestamp=$(date -Iseconds)
  echo "[$timestamp] imapsync start"

  imapsync \
    --host1 mail.ksomail.com \
    --user1 brian.lu@cimcwetrans.com \
    --passfile1 /run/secrets/wps_password \
    --ssl1 \
    --port1 993 \
    --host2 127.0.0.1 \
    --user2 archive \
    --passfile2 /run/secrets/archive_password \
    --ssl2 \
    --port2 993 \
    --automap \
    --syncinternaldates \
    --nofoldersizes \
    --skipsize \
    --logfile "$LOG_DIR/imapsync.log"

  status=$?
  echo "[$(date -Iseconds)] imapsync exit=$status"
  return "$status"
}

while true; do
  if flock -n 9; then
    run_once || true
    flock -u 9
  else
    echo "[$(date -Iseconds)] previous imapsync run is still active or failed to lock"
  fi

  sleep 180
done
