#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CFG_DIR="${CFG_DIR:-$ROOT_DIR/docs/ups/nut-host-config/srv-small-2}"

REMOTE_HOST="${REMOTE_HOST:-10.19.87.6}"
REMOTE_USER="${REMOTE_USER:-root}"
REMOTE_PASSWORD="${REMOTE_PASSWORD:-}"
REMOTE_DIR="${REMOTE_DIR:-/etc/nut}"

NUT_EXPORTER_PASSWORD="${NUT_EXPORTER_PASSWORD:-}"

if [[ -z "$NUT_EXPORTER_PASSWORD" ]]; then
  echo "[ups-apply] ERROR: NUT_EXPORTER_PASSWORD is empty" >&2
  echo "[ups-apply] Example: REMOTE_PASSWORD='***' NUT_EXPORTER_PASSWORD='***' ./scripts/apply_remote_nut_config.sh" >&2
  exit 1
fi

for f in nut.conf ups.conf upsd.conf upsd.users.example; do
  [[ -f "$CFG_DIR/$f" ]] || { echo "[ups-apply] ERROR: missing $CFG_DIR/$f" >&2; exit 1; }
done

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
if [[ -n "$REMOTE_PASSWORD" ]]; then
  if ! command -v sshpass >/dev/null 2>&1; then
    echo "[ups-apply] ERROR: sshpass not found" >&2
    exit 1
  fi
  SSH=(sshpass -p "$REMOTE_PASSWORD" ssh "${SSH_OPTS[@]}" "$REMOTE_USER@$REMOTE_HOST")
  SCP=(sshpass -p "$REMOTE_PASSWORD" scp "${SSH_OPTS[@]}")
else
  SSH=(ssh "${SSH_OPTS[@]}" "$REMOTE_USER@$REMOTE_HOST")
  SCP=(scp "${SSH_OPTS[@]}")
fi

TMP_LOCAL="$(mktemp -d)"
trap 'rm -rf "$TMP_LOCAL"' EXIT

cp "$CFG_DIR/nut.conf" "$TMP_LOCAL/nut.conf"
cp "$CFG_DIR/ups.conf" "$TMP_LOCAL/ups.conf"
cp "$CFG_DIR/upsd.conf" "$TMP_LOCAL/upsd.conf"
cp "$CFG_DIR/upsd.users.example" "$TMP_LOCAL/upsd.users"
sed -i "s#<set-via-secret-or-local-file>#$NUT_EXPORTER_PASSWORD#g" "$TMP_LOCAL/upsd.users"

echo "[ups-apply] Uploading config files to $REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR"
"${SCP[@]}" "$TMP_LOCAL/nut.conf" "$TMP_LOCAL/ups.conf" "$TMP_LOCAL/upsd.conf" "$TMP_LOCAL/upsd.users" "$REMOTE_USER@$REMOTE_HOST:/tmp/"

"${SSH[@]}" "set -euo pipefail;
  install -m 0640 -o root -g nut /tmp/nut.conf $REMOTE_DIR/nut.conf;
  install -m 0640 -o root -g nut /tmp/ups.conf $REMOTE_DIR/ups.conf;
  install -m 0640 -o root -g nut /tmp/upsd.conf $REMOTE_DIR/upsd.conf;
  install -m 0640 -o root -g nut /tmp/upsd.users $REMOTE_DIR/upsd.users;
  rm -f /tmp/nut.conf /tmp/ups.conf /tmp/upsd.conf /tmp/upsd.users;
  usermod -aG dialout nut || true;
  systemctl daemon-reload;
  systemctl enable nut-driver@nutdev1.service nut-server.service >/dev/null;
  systemctl restart nut-driver@nutdev1.service;
  systemctl restart nut-server.service;
  sleep 1;
  upsc -l | grep -q nutdev1;
  upsc nutdev1@127.0.0.1 | grep -q '^ups.status:';
  systemctl is-active --quiet nut-driver@nutdev1.service;
  systemctl is-active --quiet nut-server.service;
"

echo "[ups-apply] NUT config applied and verified on $REMOTE_HOST"
