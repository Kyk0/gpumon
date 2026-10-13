#!/bin/bash
# Build GPUBar.app and register both the backend and the menu bar app as login agents.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$DIR/hosts.json" ] || echo "[]" > "$DIR/hosts.json"   # add servers later from the dashboard
APP="$HOME/Applications/GPUBar.app"
LA="$HOME/Library/LaunchAgents"
PY="$(command -v python3)"
UID_=$(id -u)

mkdir -p "$APP/Contents/MacOS" "$LA"
swiftc -O "$DIR/GPUBar.swift" -o "$APP/Contents/MacOS/GPUBar"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.gpumon.bar</string>
  <key>CFBundleName</key><string>GPUBar</string>
  <key>CFBundleExecutable</key><string>GPUBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
EOF
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

agent() { # label, program args...
  local label=$1; shift
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    echo "<plist version=\"1.0\"><dict>"
    echo "  <key>Label</key><string>$label</string>"
    echo "  <key>ProgramArguments</key><array>"
    for a in "$@"; do echo "    <string>$a</string>"; done
    echo "  </array>"
    echo "  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>"
    echo "  <key>StandardOutPath</key><string>/tmp/$label.log</string>"
    echo "  <key>StandardErrorPath</key><string>/tmp/$label.log</string>"
    echo "</dict></plist>"
  } > "$LA/$label.plist"
  launchctl bootout "gui/$UID_/$label" 2>/dev/null || true
  for _ in $(seq 20); do launchctl print "gui/$UID_/$label" >/dev/null 2>&1 || break; sleep 0.25; done
  launchctl bootstrap "gui/$UID_" "$LA/$label.plist"
}

agent local.gpumon.server "$PY" "$DIR/gpumon.py"
agent local.gpumon.bar "$APP/Contents/MacOS/GPUBar"
echo "Installed. Dashboard: http://localhost:8765  (menu bar: cpu icon)"
