#!/usr/bin/env bash
# Installs temp-sensor-homekit as a per-user launch agent.
# The binary and its HomeKit configuration (pairing keys) are copied out of the
# repository so rebuilds or `git clean` cannot affect the running bridge.
set -euo pipefail

LABEL="com.millertechnology.temp-sensor-homekit"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SUPPORT="$HOME/Library/Application Support/temp-sensor-homekit"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
PORT="${PORT:-8000}"

BINARY="$REPO/.build/out/Products/Release/temp-sensor-homekit"
[ -x "$BINARY" ] || BINARY="$(cd "$REPO" && swift build -c release --show-bin-path)/temp-sensor-homekit"
[ -x "$BINARY" ] || { echo "Release build missing. Run: swift build -c release"; exit 1; }

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Port $PORT is already in use:"; lsof -nP -iTCP:"$PORT" -sTCP:LISTEN; exit 1
fi

mkdir -p "$SUPPORT" "$HOME/Library/LaunchAgents"
cp "$BINARY" "$SUPPORT/temp-sensor-homekit"
# Re-sign so the embedded Info.plist (Bluetooth usage description) is bound to the signature
codesign --force --sign - --identifier "$LABEL" "$SUPPORT/temp-sensor-homekit"
if [ ! -f "$SUPPORT/configuration.json" ] && [ -f "$REPO/configuration.json" ]; then
    cp -p "$REPO/configuration.json" "$SUPPORT/configuration.json"
fi
[ -f "$SUPPORT/configuration.json" ] && chmod 600 "$SUPPORT/configuration.json"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
        <string>$LABEL</string>
    <key>ProgramArguments</key>
        <array>
            <string>$SUPPORT/temp-sensor-homekit</string>
            <string>--file</string>
            <string>$SUPPORT/configuration.json</string>
            <string>--port</string>
            <string>$PORT</string>
        </array>
    <key>WorkingDirectory</key>
        <string>$SUPPORT</string>
    <key>RunAtLoad</key>
        <true/>
    <key>KeepAlive</key>
        <true/>
    <key>ThrottleInterval</key>
        <integer>10</integer>
    <key>StandardOutPath</key>
        <string>$SUPPORT/bridge.log</string>
    <key>StandardErrorPath</key>
        <string>$SUPPORT/bridge.log</string>
</dict>
</plist>
EOF
plutil -lint "$PLIST"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed $LABEL on port $PORT. Log: $SUPPORT/bridge.log"
