#!/bin/bash
# Build "GPU Monitor.app" into /Applications and start it (plus the gpumon.py backend) at login.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$DIR/hosts.json" ] || echo "[]" > "$DIR/hosts.json"   # add servers from the widget's + button
APP="/Applications/GPU Monitor.app"
LA="$HOME/Library/LaunchAgents"
PY="$(command -v python3)"
UID_=$(id -u)
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

echo "Building…"
swiftc -O "$DIR/GPUMonitor.swift" -o "$BUILD/GPUMonitor"

# App icon: render 1024px PNG from the app itself, then make an .icns.
"$BUILD/GPUMonitor" --icon "$BUILD/icon.png"
mkdir "$BUILD/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$BUILD/icon.png" --out "$BUILD/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$BUILD/icon.png" --out "$BUILD/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUILD/AppIcon.icns"

# Stop the running copy before replacing it.
for l in local.gpumon.bar local.gpumon.app; do
  launchctl bootout "gui/$UID_/$l" 2>/dev/null || true
  rm -f "$LA/$l.plist"
done
pkill -x GPUMonitor 2>/dev/null || true
rm -rf "$HOME/Applications/GPUBar.app" "$APP"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$LA"
cp "$BUILD/GPUMonitor" "$APP/Contents/MacOS/GPUMonitor"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.gpumon.app</string>
  <key>CFBundleName</key><string>GPU Monitor</string>
  <key>CFBundleDisplayName</key><string>GPU Monitor</string>
  <key>CFBundleExecutable</key><string>GPUMonitor</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
touch "$APP"

agent() { # label, keepalive-plist-fragment, program args...
  local label=$1 keep=$2; shift 2
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    echo "<plist version=\"1.0\"><dict>"
    echo "  <key>Label</key><string>$label</string>"
    echo "  <key>ProgramArguments</key><array>"
    for a in "$@"; do echo "    <string>$a</string>"; done
    echo "  </array>"
    echo "  <key>RunAtLoad</key><true/>$keep"
    echo "  <key>StandardOutPath</key><string>/tmp/$label.log</string>"
    echo "  <key>StandardErrorPath</key><string>/tmp/$label.log</string>"
    echo "</dict></plist>"
  } > "$LA/$label.plist"
  launchctl bootout "gui/$UID_/$label" 2>/dev/null || true
  for _ in $(seq 20); do launchctl print "gui/$UID_/$label" >/dev/null 2>&1 || break; sleep 0.25; done
  launchctl bootstrap "gui/$UID_" "$LA/$label.plist"
}

# Backend always restarts; the app restarts only after a crash, so "Quit" really quits.
agent local.gpumon.server "<key>KeepAlive</key><true/>" "$PY" "$DIR/gpumon.py"
agent local.gpumon.app "<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>" "$APP/Contents/MacOS/GPUMonitor"
echo "Installed: $APP (starts at login). Web dashboard: http://localhost:8765"
