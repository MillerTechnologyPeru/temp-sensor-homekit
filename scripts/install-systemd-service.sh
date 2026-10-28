#!/usr/bin/env bash
# Installs temp-sensor-homekit as a systemd system service (Linux counterpart of
# install-launch-agent.sh). Run with sudo after building as your normal user:
#   swift build -c release --static-swift-stdlib && sudo scripts/install-systemd-service.sh
# The binary and its HomeKit configuration (pairing keys) are copied out of the
# repository so rebuilds or `git clean` cannot affect the running bridge.
set -euo pipefail

NAME="temp-sensor-homekit"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="/opt/$NAME"
STATE="/var/lib/$NAME"
UNIT="/etc/systemd/system/$NAME.service"
PORT="${PORT:-8000}"
SERVICE_USER="${SERVICE_USER:-$NAME}"
BATTERY="${BATTERY:-}"

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0"; exit 1; }

BINARY="$REPO/.build/release/$NAME"
[ -x "$BINARY" ] || { echo "Release build missing. As your normal user run: swift build -c release --static-swift-stdlib"; exit 1; }
# The service user cannot read a toolchain under someone's home directory
if ldd "$BINARY" | grep -Eq 'not found|/home/|swiftly|toolchain'; then
    echo "$BINARY links Swift runtime libraries from the toolchain:"; ldd "$BINARY" | grep -E 'not found|/home/|swiftly|toolchain'
    echo "Rebuild with: swift build -c release --static-swift-stdlib"; exit 1
fi

# Accept either a power_supply directory or its capacity file
if [ -n "$BATTERY" ]; then
    [ -d "$BATTERY" ] && BATTERY="$BATTERY/capacity"
    [ -r "$BATTERY" ] || { echo "Battery file not readable: $BATTERY"; exit 1; }
fi

if ! id "$SERVICE_USER" >/dev/null 2>&1; then
    useradd --system --no-create-home --home-dir "$STATE" --shell /usr/sbin/nologin "$SERVICE_USER"
fi

# Stop a previous install first so its own listener does not fail the port check
systemctl stop "$NAME" 2>/dev/null || true
if ss -Hltn "sport = :$PORT" | grep -q .; then
    echo "Port $PORT is already in use:"; ss -ltnp "sport = :$PORT"; exit 1
fi

install -d -m 755 "$PREFIX"
install -m 755 "$BINARY" "$PREFIX/$NAME"
install -d -m 700 -o "$SERVICE_USER" -g "$SERVICE_USER" "$STATE"
if [ ! -f "$STATE/configuration.json" ] && [ -f "$REPO/configuration.json" ]; then
    cp "$REPO/configuration.json" "$STATE/configuration.json"
fi
if [ -f "$STATE/configuration.json" ]; then
    chown "$SERVICE_USER:$SERVICE_USER" "$STATE/configuration.json"
    chmod 600 "$STATE/configuration.json"
fi

ARGS="--file $STATE/configuration.json --port $PORT"
[ -n "$BATTERY" ] && ARGS="$ARGS --battery $BATTERY"

cat > "$UNIT" <<EOF
[Unit]
Description=Bluetooth sensor HomeKit bridge
Wants=network-online.target avahi-daemon.service bluetooth.service
After=network-online.target avahi-daemon.service bluetooth.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$STATE
# Line-buffer stdout so print() reaches journald immediately
ExecStart=/usr/bin/stdbuf -oL $PREFIX/$NAME $ARGS
Restart=always
RestartSec=10
# Raw HCI sockets without running as root
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=$STATE

[Install]
WantedBy=multi-user.target
EOF
systemd-analyze verify "$UNIT"

systemctl daemon-reload
systemctl enable --now "$NAME"
echo "Installed $NAME on port $PORT. Logs: journalctl -u $NAME -f"
