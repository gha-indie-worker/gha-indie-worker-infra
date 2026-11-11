#!/usr/bin/env bash
# Run once with sudo; all public-facing processes still run as the normal user.
set -Eeuo pipefail
[[ "$(uname -s)" == Darwin ]] || { echo 'macOS is required.' >&2; exit 2; }
[[ "$(id -u)" == 0 && -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]] || { echo 'Run: sudo bash scripts/ci/install-boot-services.sh' >&2; exit 2; }
app_user="$SUDO_USER"
app_uid="$(id -u "$app_user")"
app_home="$(dscl . -read "/Users/$app_user" NFSHomeDirectory | cut -d ' ' -f 2-)"
[[ "$app_home" == /Users/* && "$app_home" != *'<'* && "$app_home" != *'&'* ]] || { echo 'Unexpected home path.' >&2; exit 2; }
labels=(dev.indiebuild.web dev.indiebuild.status-tunnel dev.bretelle.macbook.app dev.bretelle.macbook.control dev.bretelle.macbook.gateway dev.bretelle.macbook.agent dev.bretelle.macbook.tunnel)
backup="$app_home/.config/indiebuild-boot/login-agents"
mkdir -p "$backup"
chown "$app_user" "$backup"
chmod 700 "$backup"
# Preflight every source before changing any service.
for label in "${labels[@]}"; do
  source="$app_home/Library/LaunchAgents/$label.plist"
  [[ -f "$source" ]] || source="$backup/$label.plist"
  [[ -f "$source" ]] || { echo "Missing prepared service: $label" >&2; exit 2; }
  /usr/bin/plutil -lint "$source"
done
for label in "${labels[@]}"; do
  source="$app_home/Library/LaunchAgents/$label.plist"
  [[ -f "$source" ]] || source="$backup/$label.plist"
  destination="/Library/LaunchDaemons/$label.plist"
  cp "$source" "$destination"
  /usr/libexec/PlistBuddy -c "Delete :UserName" "$destination" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :UserName string $app_user" "$destination"
  /usr/libexec/PlistBuddy -c 'Delete :LimitLoadToSessionType' "$destination" 2>/dev/null || true
  chown root:wheel "$destination"
  chmod 644 "$destination"
  /usr/bin/plutil -lint "$destination"
  launchctl bootout "gui/$app_uid/$label" 2>/dev/null || true
  launchctl bootout "system/$label" 2>/dev/null || true
  # Move the login plist away to prevent duplicate services after next login.
  if [[ -f "$app_home/Library/LaunchAgents/$label.plist" ]]; then
    mv "$app_home/Library/LaunchAgents/$label.plist" "$backup/$label.plist"
    chown "$app_user" "$backup/$label.plist"
  fi
  for attempt in 1 2 3 4 5; do
    if launchctl bootstrap system "$destination"; then break; fi
    [[ "$attempt" != 5 ]] || exit 1
    sleep 1
  done
  echo "Installed boot service: $label (runs as $app_user)"
done
echo 'Boot services installed. FileVault disk unlock is still required before macOS can boot.'
echo 'GitHub runners/status refresh remain login services because gh uses the login Keychain.'
