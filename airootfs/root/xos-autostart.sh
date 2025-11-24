#!/usr/bin/env bash
set -euo pipefail

grep -q "/run/archiso/bootmnt" /proc/mounts 2>/dev/null || { return 0 2>/dev/null || exit 0; }
[ "${XOS_NO_AUTO:-0}" = "1" ] && { echo "[XOs] Autostart disabled (XOS_NO_AUTO=1)."; return 0 2>/dev/null || exit 0; }
[ "$(tty)" = "/dev/tty1" ] || { :; }

echo
echo "──────────────────────────────────────────"
echo "   XOs Live – Archinstall will start in 5s"
echo "   Press Ctrl+C to cancel."
echo "──────────────────────────────────────────"
for i in 5 4 3 2 1; do
  printf "\rStarting archinstall in %s s… (Ctrl+C to cancel) " "$i"
  sleep 1
done
echo
echo "→ Starting archinstall (Automated with config)…"
echo

CONF_PATH="/root/user_configuration.json"
CREDS_PATH="/root/user_credentials.json"

INSTALL_OK=0
echo "[XOs] Using config: $CONF_PATH"
if [ -f "$CREDS_PATH" ]; then
  echo "[XOs] Using creds: $CREDS_PATH"
  if archinstall --config "$CONF_PATH" --creds "$CREDS_PATH"; then INSTALL_OK=1; fi
else
  echo "[XOs] Credentials file not found at $CREDS_PATH, proceeding without creds."
  if archinstall --config "$CONF_PATH"; then INSTALL_OK=1; fi
fi

if [ "$INSTALL_OK" = "1" ] && [ -f /root/xos-postinstall.sh ]; then
  bash /root/xos-postinstall.sh || true
  echo
  echo "──────────────────────────────────────────"
  echo "Please quit the installation media; the system will reboot."
  echo "──────────────────────────────────────────"
  for i in 5 4 3 2 1; do
    printf "\rRebooting in %s s… " "$i"
    sleep 1
  done
  echo
  systemctl reboot || reboot || echo "[XOs] Failed to trigger reboot. Please reboot manually."
fi