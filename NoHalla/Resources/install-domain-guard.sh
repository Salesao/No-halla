#!/bin/bash
#
# Installs the No-halla domain guard (D32): a root LaunchDaemon that keeps the
# marked section of /etc/hosts in sync with the app's domain-guard.json.
#
# Usage: sudo bash "/Applications/No-halla.app/Contents/Resources/install-domain-guard.sh"
#        sudo bash install-domain-guard.sh /path/to/No-halla.app
#
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this installer with sudo: sudo bash \"$0\"" >&2
  exit 1
fi

RESOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${1:-$(cd "$RESOURCE_DIR/../.." && pwd)}"
GUARD_SOURCE="$APP_DIR/Contents/MacOS/NoHallaDomainGuard"
if [ ! -x "$GUARD_SOURCE" ]; then
  echo "NoHallaDomainGuard not found at $GUARD_SOURCE" >&2
  echo "Build the app first (./scripts/build.sh) or pass the .app path." >&2
  exit 1
fi

CONSOLE_USER="$(stat -f %Su /dev/console)"
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ]; then
  echo "Log in to the Mac first: the guard needs a console user." >&2
  exit 1
fi
USER_UID="$(id -u "$CONSOLE_USER")"
USER_HOME="$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory | awk '{print $2}')"
if [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ]; then
  echo "Cannot resolve the home directory of $CONSOLE_USER" >&2
  exit 1
fi

LABEL="dev.nohalla.NoHallaDomainGuard"
HELPER="/usr/local/libexec/nohalla-domain-guard"
CONF_DIR="/Library/Application Support/NoHalla"
CONF="$CONF_DIR/guard.plist"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

install -d -o root -g wheel -m 0755 /usr/local/libexec "$CONF_DIR"
install -o root -g wheel -m 0755 "$GUARD_SOURCE" "$HELPER"

cat > "$CONF" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>statePath</key><string>$USER_HOME/Library/Application Support/NoHalla/domain-guard.json</string>
  <key>hostsPath</key><string>/etc/hosts</string>
  <key>uid</key><integer>$USER_UID</integer>
  <key>pollSeconds</key><real>1</real>
</dict>
</plist>
PLIST

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$HELPER</string>
    <string>$CONF</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/var/log/nohalla-domain-guard.log</string>
  <key>StandardErrorPath</key><string>/var/log/nohalla-domain-guard.log</string>
</dict>
</plist>
PLIST

chown root:wheel "$CONF" "$PLIST"
chmod 0644 "$CONF" "$PLIST"

launchctl bootout "system/$LABEL" 2>/dev/null || true
launchctl bootstrap system "$PLIST"

echo "Installed $LABEL."
echo "State file: $USER_HOME/Library/Application Support/NoHalla/domain-guard.json"
echo "Uninstall: sudo bash \"$RESOURCE_DIR/uninstall-domain-guard.sh\""