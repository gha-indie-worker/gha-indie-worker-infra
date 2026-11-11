#!/usr/bin/env bash
# User LaunchAgents: no tokens or tunnel credentials appear in plists.
set -Eeuo pipefail
umask 077
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
launch_dir="$HOME/Library/LaunchAgents"
logs="$HOME/.local/share/indiebuild/logs"
node_bin="$(command -v node)"
[[ "$node_bin" == /* ]] || { echo 'Node must be installed.' >&2; exit 2; }
mkdir -p "$launch_dir" "$logs"
install_agent() {
  local label="$1" interval="$2" args="$3" plist="$launch_dir/$1.plist"
  if launchctl print "system/$label" >/dev/null 2>&1; then
    printf 'Boot-managed service already installed: %s\n' "$label"
    return
  fi
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>$label</string>
<key>ProgramArguments</key><array>$args</array>
<key>EnvironmentVariables</key><dict><key>HOME</key><string>$HOME</string><key>PATH</key><string>/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
<key>RunAtLoad</key><true/>$interval
<key>ThrottleInterval</key><integer>30</integer>
<key>StandardOutPath</key><string>$logs/$label.log</string>
<key>StandardErrorPath</key><string>$logs/$label.log</string>
</dict></plist>
PLIST
  /usr/bin/plutil -lint "$plist"
  if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then launchctl bootout "gui/$(id -u)/$label"; fi
  launchctl bootstrap "gui/$(id -u)" "$plist"
}
install_agent dev.indiebuild.status-refresh '<key>StartInterval</key><integer>30</integer>' "<string>$node_bin</string><string>$root/scripts/ci/refresh-local-status.mjs</string>"
install_agent dev.indiebuild.status-tunnel '<key>KeepAlive</key><true/>' "<string>/opt/homebrew/bin/cloudflared</string><string>tunnel</string><string>--config</string><string>$HOME/.config/indiebuild-status/cloudflared.yml</string><string>--no-autoupdate</string><string>--metrics</string><string>127.0.0.1:20392</string><string>run</string>"
while IFS= read -r repo; do
  label="dev.indiebuild.runner.${repo##*/}"
  install_agent "$label" '<key>KeepAlive</key><true/>' "<string>/bin/bash</string><string>$root/scripts/ci/run-local-runner.sh</string><string>$repo</string>"
done < <(/opt/homebrew/bin/jq -r '.[]' "$root/config/macbook-ci-repositories.json")
