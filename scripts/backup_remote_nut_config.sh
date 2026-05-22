#!/bin/bash
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-10.19.87.6}"
REMOTE_USER="${REMOTE_USER:-root}"
REMOTE_PASSWORD="${REMOTE_PASSWORD:-}"
REMOTE_DIR="${REMOTE_DIR:-/etc/nut}"
OUT_ROOT="${OUT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)/docs/ups/snapshots}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$OUT_ROOT/$STAMP"

mkdir -p "$OUT_DIR"

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

if [[ -n "$REMOTE_PASSWORD" ]]; then
  if ! command -v sshpass >/dev/null 2>&1; then
    echo "[ups-backup] ERROR: sshpass not found" >&2
    exit 1
  fi
  SSH=(sshpass -p "$REMOTE_PASSWORD" ssh "${SSH_OPTS[@]}" "$REMOTE_USER@$REMOTE_HOST")
else
  SSH=(ssh "${SSH_OPTS[@]}" "$REMOTE_USER@$REMOTE_HOST")
fi

pull_file() {
  local src="$1"
  local dst="$2"
  "${SSH[@]}" "cat '$src'" > "$dst"
}

echo "[ups-backup] Saving NUT config snapshot from $REMOTE_USER@$REMOTE_HOST to $OUT_DIR"

pull_file "$REMOTE_DIR/nut.conf" "$OUT_DIR/nut.conf"
pull_file "$REMOTE_DIR/ups.conf" "$OUT_DIR/ups.conf"
pull_file "$REMOTE_DIR/upsd.conf" "$OUT_DIR/upsd.conf"

# redact password field in exported users file
"${SSH[@]}" "sed -E 's/(password\s*=\s*).+$/\1<redacted>/' '$REMOTE_DIR/upsd.users'" > "$OUT_DIR/upsd.users.redacted"

"${SSH[@]}" "systemctl is-enabled nut-driver@nutdev1.service nut-server.service 2>/dev/null || true; systemctl is-active nut-driver@nutdev1.service nut-server.service 2>/dev/null || true" > "$OUT_DIR/systemd-status.txt"
"${SSH[@]}" "upsc -l 2>/dev/null || true" > "$OUT_DIR/upsc-list.txt"
"${SSH[@]}" "upsc nutdev1@127.0.0.1 2>/dev/null || true" > "$OUT_DIR/upsc-nutdev1.txt"

cat > "$OUT_DIR/README.txt" <<TXT
Snapshot time: $(date -Iseconds)
Remote host: $REMOTE_HOST
Remote dir: $REMOTE_DIR
Contains redacted NUT users file and runtime status.
TXT

echo "[ups-backup] Done: $OUT_DIR"
