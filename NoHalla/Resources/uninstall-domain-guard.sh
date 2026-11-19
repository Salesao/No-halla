#!/bin/bash
#
# Removes the No-halla domain guard LaunchDaemon, its helper, and the marked
# /etc/hosts section. Usage: sudo bash uninstall-domain-guard.sh
#
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this uninstaller with sudo: sudo bash \"$0\"" >&2
  exit 1
fi

LABEL="dev.nohalla.NoHallaDomainGuard"
HELPER="/usr/local/libexec/nohalla-domain-guard"
CONF_DIR="/Library/Application Support/NoHalla"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -f "$PLIST" "$HELPER" "$CONF_DIR/guard.plist"
rmdir "$CONF_DIR" 2>/dev/null || true

if grep -q "# >>> No-halla domain guard >>>" /etc/hosts 2>/dev/null; then
  sed -i '' '/# >>> No-halla domain guard >>>/,/# <<< No-halla domain guard <<</d' /etc/hosts
fi

echo "Removed $LABEL and the /etc/hosts block."