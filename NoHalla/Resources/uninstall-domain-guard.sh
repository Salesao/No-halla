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
CONF="$CONF_DIR/guard.plist"
MANIFEST="$CONF_DIR/proxy-restore.json"
STATUS="$CONF_DIR/guard-status.json"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

launchctl bootout "system/$LABEL" 2>/dev/null || true

# The helper owns the restore logic; fall back to the manifest when it is
# missing, so an uninstall never leaves 127.0.0.1 in the system proxy.
restored=0
if [ -x "$HELPER" ] && [ -f "$CONF" ]; then
  if "$HELPER" --restore; then
    restored=1
  fi
fi
if [ "$restored" -eq 0 ] && [ -f "$MANIFEST" ]; then
  index=0
  failed=0
  while name=$(plutil -extract "services.$index.name" raw -o - "$MANIFEST" 2>/dev/null); do
    for kind in web secure; do
      enabled=$(plutil -extract "services.$index.${kind}Enabled" raw -o - "$MANIFEST" 2>/dev/null || echo false)
      server=$(plutil -extract "services.$index.${kind}Server" raw -o - "$MANIFEST" 2>/dev/null || echo "")
      port=$(plutil -extract "services.$index.${kind}Port" raw -o - "$MANIFEST" 2>/dev/null || echo 0)
      if [ "$enabled" = "true" ] && [ -n "$server" ] && [ "$port" != "0" ]; then
        if [ "$kind" = "web" ]; then
          /usr/sbin/networksetup -setwebproxy "$name" "$server" "$port" || failed=1
          /usr/sbin/networksetup -setwebproxystate "$name" on || failed=1
        else
          /usr/sbin/networksetup -setsecurewebproxy "$name" "$server" "$port" || failed=1
          /usr/sbin/networksetup -setsecurewebproxystate "$name" on || failed=1
        fi
      else
        if [ "$kind" = "web" ]; then
          /usr/sbin/networksetup -setwebproxystate "$name" off || failed=1
        else
          /usr/sbin/networksetup -setsecurewebproxystate "$name" off || failed=1
        fi
      fi
    done
    index=$((index + 1))
  done
  if [ "$index" -eq 0 ]; then
    echo "Cannot read $MANIFEST. Restore the system proxy manually before removing it." >&2
    exit 1
  fi
  if [ "$failed" -ne 0 ]; then
    echo "Could not restore every proxy from $MANIFEST; keeping it." >&2
    exit 1
  fi
fi

rm -f "$PLIST" "$HELPER" "$CONF" "$MANIFEST" "$STATUS"
rmdir "$CONF_DIR" 2>/dev/null || true

if grep -q "# >>> No-halla domain guard >>>" /etc/hosts 2>/dev/null; then
  sed -i '' '/# >>> No-halla domain guard >>>/,/# <<< No-halla domain guard <<</d' /etc/hosts
fi

echo "Removed $LABEL, restored the system proxy, and removed the /etc/hosts block."