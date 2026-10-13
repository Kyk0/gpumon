#!/bin/bash
# Stop and remove the login agents and the app. Your hosts.json is kept.
for l in local.gpumon.app local.gpumon.bar local.gpumon.server; do
  launchctl bootout "gui/$(id -u)/$l" 2>/dev/null
  rm -f "$HOME/Library/LaunchAgents/$l.plist"
done
rm -rf "/Applications/GPU Monitor.app" "$HOME/Applications/GPUBar.app"
echo "Removed."
