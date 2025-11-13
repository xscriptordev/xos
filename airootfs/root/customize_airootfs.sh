#!/usr/bin/env bash
set -euo pipefail

# Dont excecute while building mkarchiso
grep -q "/run/archiso/bootmnt" /proc/mounts 2>/dev/null || { return 0 2>/dev/null || exit 0; }

# Allow deactivate
[ "${XOS_NO_AUTO:-0}" = "1" ] && { echo "[XOs] Autoinicio desactivado (XOS_NO_AUTO=1)."; return 0 2>/dev/null || exit 0; }

# Only on TTY1
[ "$(tty)" = "/dev/tty1" ] || { return 0 2>/dev/null || exit 0; }

echo
echo "──────────────────────────────────────────"
echo "   XOs Live – Archinstall will start in 5s"
echo "   Pulsa Ctrl+C para cancelar."
echo "──────────────────────────────────────────"

for i in 5 4 3 2 1; do
  printf "\rStarting archinstall in %s s… (Ctrl+C to cancel) " "$i"
  sleep 1
done
echo
echo "→ Starting archinstall (Automated with config)…"
echo

CONF_PATH="./user_configuration.json"
CREDS_PATH="./user_credentials.json"
[ -f "$CONF_PATH" ] || CONF_PATH="/root/user_configuration.json"
[ -f "$CREDS_PATH" ] || CREDS_PATH="/root/user_credentials.json"

ISO_SRC=$(findmnt -n -o SOURCE /run/archiso/bootmnt 2>/dev/null || true)
ISO_PK=""
[ -n "$ISO_SRC" ] && ISO_PK=$(lsblk -no PKNAME "$ISO_SRC" 2>/dev/null | head -n1)
CANDS=$(lsblk -dn -o NAME,TYPE,RM,RO | awk '$2=="disk" && $3=="0" && $4=="0" && $1 !~ /^sr/{print $1}')
MIN_SIZE=${XOS_MIN_SIZE_BYTES:-34359738368}
BEST_EMPTY=""
BEST_EMPTY_SIZE=0
BEST_ANY=""
BEST_ANY_SIZE=0
for n in $CANDS; do
  [ -n "$ISO_PK" ] && [ "$n" = "$ISO_PK" ] && continue
  SIZE=$(blockdev --getsize64 "/dev/$n" 2>/dev/null || echo 0)
  [ "$SIZE" -lt "$MIN_SIZE" ] && continue
  PARTS=$(lsblk -n "/dev/$n" -o TYPE | grep -c '^part$' || true)
  [ "$SIZE" -gt "$BEST_ANY_SIZE" ] && BEST_ANY="$n" && BEST_ANY_SIZE="$SIZE"
  if [ "$PARTS" -eq 0 ] && [ "$SIZE" -gt "$BEST_EMPTY_SIZE" ]; then
    BEST_EMPTY="$n"
    BEST_EMPTY_SIZE="$SIZE"
  fi
done
TARGET="${BEST_EMPTY:-$BEST_ANY}"
if [ -n "${XOS_TARGET_DEVICE:-}" ]; then
  case "${XOS_TARGET_DEVICE}" in
    /dev/*) TARGET="${XOS_TARGET_DEVICE#/dev/}" ;;
    *) TARGET="${XOS_TARGET_DEVICE}" ;;
  esac
fi
if [ -n "$TARGET" ]; then
  echo "[XOs] Target disk selected: /dev/$TARGET"
else
  echo "[XOs] No suitable target disk found, falling back to interactive Archinstall."
fi
if [ -n "$TARGET" ] && [ -f "$CONF_PATH" ]; then
  DEV="/dev/$TARGET"
  if command -v jq >/dev/null 2>&1; then
    TMP=$(mktemp)
    jq '.disk_config.device_modifications[0].device = "'"$DEV"'"' "$CONF_PATH" > "$TMP" && mv "$TMP" "$CONF_PATH"
  else
    sed -i -E '0,/\"device\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/s//\"device\": \"'"$DEV"'\"/' "$CONF_PATH"
  fi
fi

if [ -f "$CONF_PATH" ] && command -v jq >/dev/null 2>&1; then
  BIDX=$(jq -r '.disk_config.device_modifications[0].partitions | to_entries[] | select(.value.fs_type=="btrfs") | .key' "$CONF_PATH" | head -n1)
  if [ -n "$BIDX" ]; then
    ROOT_PCT=${XOS_ROOT_PERCENT:-100}
    TMP=$(mktemp)
    jq ".disk_config.device_modifications[0].partitions[$BIDX].size = {\"sector_size\": {\"unit\": \"B\", \"value\": 512}, \"unit\": \"Percent\", \"value\": $ROOT_PCT}" "$CONF_PATH" > "$TMP" && mv "$TMP" "$CONF_PATH"
  fi
  FIDX=$(jq -r '.disk_config.device_modifications[0].partitions | to_entries[] | select(.value.fs_type=="fat32") | .key' "$CONF_PATH" | head -n1)
  if [ -n "$FIDX" ] && [ -n "${XOS_BOOT_SIZE_MIB:-}" ]; then
    TMP=$(mktemp)
    jq ".disk_config.device_modifications[0].partitions[$FIDX].size = {\"sector_size\": {\"unit\": \"B\", \"value\": 512}, \"unit\": \"MiB\", \"value\": ${XOS_BOOT_SIZE_MIB}}" "$CONF_PATH" > "$TMP" && mv "$TMP" "$CONF_PATH"
  fi

  if [ -n "$BIDX" ] && [ -n "$FIDX" ]; then
    BOOT_UNIT=$(jq -r ".disk_config.device_modifications[0].partitions[$FIDX].size.unit" "$CONF_PATH")
    BOOT_VALUE=$(jq -r ".disk_config.device_modifications[0].partitions[$FIDX].size.value" "$CONF_PATH")
    BOOT_MIB=$BOOT_VALUE
    case "$BOOT_UNIT" in
      GiB|GIB|GiB) BOOT_MIB=$(( BOOT_VALUE * 1024 )) ;;
      MiB|MIB|MiB) BOOT_MIB=$(( BOOT_VALUE )) ;;
      B) BOOT_MIB=$(( BOOT_VALUE / 1048576 )) ;;
      *) BOOT_MIB=$(( BOOT_VALUE )) ;;
    esac
    ROOT_START_MIB=$(( BOOT_MIB + 1 ))
    TMP=$(mktemp)
    jq ".disk_config.device_modifications[0].partitions[$BIDX].start = {\"sector_size\": {\"unit\": \"B\", \"value\": 512}, \"unit\": \"MiB\", \"value\": ${ROOT_START_MIB}}" "$CONF_PATH" > "$TMP" && mv "$TMP" "$CONF_PATH"
  fi
fi

INSTALL_OK=0
RUN_CONFIG=0
[ -f "$CONF_PATH" ] && [ -n "$TARGET" ] && RUN_CONFIG=1
if [ "$RUN_CONFIG" = "1" ]; then
  if [ -f "$CREDS_PATH" ]; then
    if archinstall --config "$CONF_PATH" --creds "$CREDS_PATH"; then INSTALL_OK=1; fi
  else
    if archinstall --config "$CONF_PATH"; then INSTALL_OK=1; fi
  fi
else
  if archinstall; then INSTALL_OK=1; fi
fi

# Postinstall (branding xos)
if [ "$INSTALL_OK" = "1" ] && [ -f /root/xos-postinstall.sh ]; then
  bash /root/xos-postinstall.sh || true
else
  if [ "$INSTALL_OK" != "1" ]; then
    echo "[XOs] Archinstall failed. Check /var/log/archinstall/install.log for details." || true
  fi
fi
