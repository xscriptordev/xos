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
echo "   Press Ctrl+C to cancel."
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

# Usar copia temporal para modificaciones, preservando el JSON original
CONF_RUN="$CONF_PATH"
if [ -f "$CONF_PATH" ]; then
  TMP_CONF=$(mktemp)
  cp "$CONF_PATH" "$TMP_CONF"
  CONF_RUN="$TMP_CONF"
fi

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
  echo "[XOs] No suitable target disk found; proceeding with config."
fi
if [ -n "$TARGET" ] && [ -f "$CONF_RUN" ]; then
  DEV="/dev/$TARGET"
  python3 - "$CONF_RUN" "$DEV" << 'PY'
import re,sys
p=sys.argv[1]; dev=sys.argv[2]
t=open(p,'r',encoding='utf-8').read()
t=re.sub(r'("device"\s*:\s*")([^"]+)(")', lambda m: m.group(1)+dev+m.group(3), t, count=1)
open(p,'w',encoding='utf-8').write(t)
PY
fi

if [ -f "$CONF_RUN" ]; then
  if command -v jq >/dev/null 2>&1; then
    # Leer índices/valores con jq pero escribir con awk/sed para preservar el formato original
    FIDX=$(jq -r '.disk_config.device_modifications[0].partitions | to_entries[] | select(.value.fs_type=="fat32") | .key' "$CONF_RUN" | head -n1)
    BIDX=$(jq -r '.disk_config.device_modifications[0].partitions | to_entries[] | select(.value.fs_type=="btrfs") | .key' "$CONF_RUN" | head -n1)

    # 1) Tamaño de /boot (fat32)
    if [ -n "$FIDX" ] && [ -n "${XOS_BOOT_SIZE_MIB:-}" ]; then
      BOOT_UNIT=$(jq -r ".disk_config.device_modifications[0].partitions[$FIDX].size.unit" "$CONF_RUN")
      case "$BOOT_UNIT" in
        MiB|MIB|MiB) NEW_BOOT_VAL=${XOS_BOOT_SIZE_MIB} ;;
        GiB|GIB|GiB) NEW_BOOT_VAL=$(( XOS_BOOT_SIZE_MIB / 1024 )) ;;
        B) NEW_BOOT_VAL=$(( XOS_BOOT_SIZE_MIB * 1048576 )) ;;
        *) NEW_BOOT_VAL=${XOS_BOOT_SIZE_MIB} ;;
      esac
      TMP=$(mktemp)
      TARGET_FS="fat32" SECTION="size" NEW_VAL="$NEW_BOOT_VAL" awk '
        BEGIN{in_part=0;in_section=0;unit_seen=0;skip_sub=0;sub_depth=0;replaced=0}
        {
          line=$0
          if ($0 ~ /"fs_type"[[:space:]]*:[[:space:]]*"/ && index($0, target_fs)) { in_part=1 }
          if (in_part && $0 ~ ("\"" section "\"[[:space:]]*:")) { in_section=1; unit_seen=0; skip_sub=0; sub_depth=0 }
          if (in_section) {
            if ($0 ~ /"sector_size"[[:space:]]*:/) { skip_sub=1; sub_depth=0 }
            if (skip_sub) {
              ob=gsub(/\{/, "", line); cb=gsub(/\}/, "", line); sub_depth += (ob - cb)
              if (sub_depth <= 0) { skip_sub=0 }
            } else {
              if ($0 ~ /"unit"[[:space:]]*:/) unit_seen=1
              if (unit_seen && $0 ~ /"value"[[:space:]]*:/ && replaced==0) {
                sub(/("value"[[:space:]]*:[[:space:]]*)[0-9]+/, "\\1" new_val)
                replaced=1; in_section=0; in_part=0; unit_seen=0
              }
            }
          }
          print
        }
      ' target_fs="$TARGET_FS" section="$SECTION" new_val="$NEW_VAL" "$CONF_RUN" > "$TMP" && mv "$TMP" "$CONF_RUN"
    fi

    # 2) Punto de inicio de btrfs (start.value)
    if [ -n "$BIDX" ] && [ -n "${XOS_BOOT_SIZE_MIB:-}" ]; then
      BSTART_UNIT=$(jq -r ".disk_config.device_modifications[0].partitions[$BIDX].start.unit" "$CONF_RUN")
      NEW_START_MIB=$(( XOS_BOOT_SIZE_MIB + 1 ))
      case "$BSTART_UNIT" in
        MiB|MIB|MiB) NEW_START_VAL=$NEW_START_MIB ;;
        GiB|GIB|GiB) NEW_START_VAL=$(( NEW_START_MIB / 1024 )) ;;
        B) NEW_START_VAL=$(( NEW_START_MIB * 1048576 )) ;;
        *) NEW_START_VAL=$NEW_START_MIB ;;
      esac
      TMP=$(mktemp)
      TARGET_FS="btrfs" SECTION="start" NEW_VAL="$NEW_START_VAL" awk '
        BEGIN{in_part=0;in_section=0;unit_seen=0;skip_sub=0;sub_depth=0;replaced=0}
        {
          line=$0
          if ($0 ~ /"fs_type"[[:space:]]*:[[:space:]]*"/ && index($0, target_fs)) { in_part=1 }
          if (in_part && $0 ~ ("\"" section "\"[[:space:]]*:")) { in_section=1; unit_seen=0; skip_sub=0; sub_depth=0 }
          if (in_section) {
            if ($0 ~ /"sector_size"[[:space:]]*:/) { skip_sub=1; sub_depth=0 }
            if (skip_sub) {
              ob=gsub(/\{/, "", line); cb=gsub(/\}/, "", line); sub_depth += (ob - cb)
              if (sub_depth <= 0) { skip_sub=0 }
            } else {
              if ($0 ~ /"unit"[[:space:]]*:/) unit_seen=1
              if (unit_seen && $0 ~ /"value"[[:space:]]*:/ && replaced==0) {
                sub(/("value"[[:space:]]*:[[:space:]]*)[0-9]+/, "\\1" new_val)
                replaced=1; in_section=0; in_part=0; unit_seen=0
              }
            }
          }
          print
        }
      ' target_fs="$TARGET_FS" section="$SECTION" new_val="$NEW_VAL" "$CONF_RUN" > "$TMP" && mv "$TMP" "$CONF_RUN"
    fi

    # 3) Tamaño de btrfs
    if [ -n "$BIDX" ]; then
      BUNIT=$(jq -r ".disk_config.device_modifications[0].partitions[$BIDX].size.unit" "$CONF_RUN")
      if [ "$BUNIT" = "Percent" ] && [ -n "${XOS_ROOT_PERCENT:-}" ]; then
        TMP=$(mktemp)
        TARGET_FS="btrfs" SECTION="size" NEW_VAL="$XOS_ROOT_PERCENT" awk '
          BEGIN{in_part=0;in_section=0;saw_unit=0;replaced=0}
          $0 ~ /"fs_type"[[:space:]]*:[[:space:]]*"/ && index($0, target_fs) { in_part=1 }
          in_part && $0 ~ ("\"" section "\"[[:space:]]*:") { in_section=1; saw_unit=0 }
          in_section && $0 ~ /"unit"[[:space:]]*:/ { saw_unit=1 }
          in_section && saw_unit && $0 ~ /"value"[[:space:]]*:/ && replaced==0 {
            sub(/("value"[[:space:]]*:[[:space:]]*)[0-9]+/, "\\1" new_val)
            replaced=1; in_section=0; in_part=0
          }
          { print }
        ' target_fs="$TARGET_FS" section="$SECTION" new_val="$NEW_VAL" "$CONF_RUN" > "$TMP" && mv "$TMP" "$CONF_RUN"
      else
        # Si no es Percent, calcular resto del disco y aplicar
        if [ -n "$TARGET" ]; then
          DISK_BYTES=$(blockdev --getsize64 "/dev/$TARGET" 2>/dev/null || echo 0)
        else
          DISK_BYTES=0
        fi
        if [ "$DISK_BYTES" -gt 0 ]; then
          SUNIT=$(jq -r ".disk_config.device_modifications[0].partitions[$BIDX].start.unit" "$CONF_RUN")
          SVAL=$(jq -r ".disk_config.device_modifications[0].partitions[$BIDX].start.value" "$CONF_RUN")
          case "$SUNIT" in
            MiB|MIB|MiB) START_BYTES=$(( SVAL * 1048576 )) ;;
            GiB|GIB|GiB) START_BYTES=$(( SVAL * 1073741824 )) ;;
            B) START_BYTES=$(( SVAL )) ;;
            *) START_BYTES=$(( SVAL * 1048576 )) ;;
          esac
          REST_BYTES=$(( DISK_BYTES - START_BYTES ))
          case "$BUNIT" in
            B) NEW_SIZE_VAL=$REST_BYTES ;;
            MiB|MIB|MiB) NEW_SIZE_VAL=$(( REST_BYTES / 1048576 )) ;;
            GiB|GIB|GiB) NEW_SIZE_VAL=$(( REST_BYTES / 1073741824 )) ;;
            *) NEW_SIZE_VAL=$(( REST_BYTES / 1048576 )) ;;
          esac
          TMP=$(mktemp)
          TARGET_FS="btrfs" SECTION="size" NEW_VAL="$NEW_SIZE_VAL" awk '
            BEGIN{in_part=0;in_section=0;unit_seen=0;skip_sub=0;sub_depth=0;replaced=0}
            {
              line=$0
              if ($0 ~ /"fs_type"[[:space:]]*:[[:space:]]*"/ && index($0, target_fs)) { in_part=1 }
              if (in_part && $0 ~ ("\"" section "\"[[:space:]]*:")) { in_section=1; unit_seen=0; skip_sub=0; sub_depth=0 }
              if (in_section) {
                if ($0 ~ /"sector_size"[[:space:]]*:/) { skip_sub=1; sub_depth=0 }
                if (skip_sub) {
                  ob=gsub(/\{/, "", line); cb=gsub(/\}/, "", line); sub_depth += (ob - cb)
                  if (sub_depth <= 0) { skip_sub=0 }
                } else {
                  if ($0 ~ /"unit"[[:space:]]*:/) unit_seen=1
                  if (unit_seen && $0 ~ /"value"[[:space:]]*:/ && replaced==0) {
                    sub(/("value"[[:space:]]*:[[:space:]]*)[0-9]+/, "\\1" new_val)
                    replaced=1; in_section=0; in_part=0; unit_seen=0
                  }
                }
              }
              print
            }
          ' target_fs="$TARGET_FS" section="$SECTION" new_val="$NEW_VAL" "$CONF_RUN" > "$TMP" && mv "$TMP" "$CONF_RUN"
        fi
      fi
    fi
  else
    # Fallback sin jq: asumir unidades MiB y aplicar cambios mínimos manteniendo formato
    if [ -n "${XOS_BOOT_SIZE_MIB:-}" ]; then
      TMP=$(mktemp)
      TARGET_FS="fat32" SECTION="size" NEW_VAL="$XOS_BOOT_SIZE_MIB" awk '
        BEGIN{in_part=0;in_section=0;unit_seen=0;skip_sub=0;sub_depth=0;replaced=0}
        {
          line=$0
          if ($0 ~ /"fs_type"[[:space:]]*:[[:space:]]*"/ && index($0, target_fs)) { in_part=1 }
          if (in_part && $0 ~ ("\"" section "\"[[:space:]]*:")) { in_section=1; unit_seen=0; skip_sub=0; sub_depth=0 }
          if (in_section) {
            if ($0 ~ /"sector_size"[[:space:]]*:/) { skip_sub=1; sub_depth=0 }
            if (skip_sub) {
              ob=gsub(/\{/, "", line); cb=gsub(/\}/, "", line); sub_depth += (ob - cb)
              if (sub_depth <= 0) { skip_sub=0 }
            } else {
              if ($0 ~ /"unit"[[:space:]]*:/) unit_seen=1
              if (unit_seen && $0 ~ /"value"[[:space:]]*:/ && replaced==0) {
                sub(/("value"[[:space:]]*:[[:space:]]*)[0-9]+/, "\\1" new_val)
                replaced=1; in_section=0; in_part=0; unit_seen=0
              }
            }
          }
          print
        }
      ' target_fs="$TARGET_FS" section="$SECTION" new_val="$NEW_VAL" "$CONF_RUN" > "$TMP" && mv "$TMP" "$CONF_RUN"

      TMP=$(mktemp)
      TARGET_FS="btrfs" SECTION="start" NEW_VAL="$(( XOS_BOOT_SIZE_MIB + 1 ))" awk '
        BEGIN{in_part=0;in_section=0;unit_seen=0;skip_sub=0;sub_depth=0;replaced=0}
        {
          line=$0
          if ($0 ~ /"fs_type"[[:space:]]*:[[:space:]]*"/ && index($0, target_fs)) { in_part=1 }
          if (in_part && $0 ~ ("\"" section "\"[[:space:]]*:")) { in_section=1; unit_seen=0; skip_sub=0; sub_depth=0 }
          if (in_section) {
            if ($0 ~ /"sector_size"[[:space:]]*:/) { skip_sub=1; sub_depth=0 }
            if (skip_sub) {
              ob=gsub(/\{/, "", line); cb=gsub(/\}/, "", line); sub_depth += (ob - cb)
              if (sub_depth <= 0) { skip_sub=0 }
            } else {
              if ($0 ~ /"unit"[[:space:]]*:/) unit_seen=1
              if (unit_seen && $0 ~ /"value"[[:space:]]*:/ && replaced==0) {
                sub(/("value"[[:space:]]*:[[:space:]]*)[0-9]+/, "\\1" new_val)
                replaced=1; in_section=0; in_part=0; unit_seen=0
              }
            }
          }
          print
        }
      ' target_fs="$TARGET_FS" section="$SECTION" new_val="$NEW_VAL" "$CONF_RUN" > "$TMP" && mv "$TMP" "$CONF_RUN"
    fi
    if [ -n "${XOS_ROOT_PERCENT:-}" ]; then
      TMP=$(mktemp)
      TARGET_FS="btrfs" SECTION="size" NEW_VAL="$XOS_ROOT_PERCENT" awk '
        BEGIN{in_part=0;in_section=0;saw_unit=0;replaced=0}
        $0 ~ /"fs_type"[[:space:]]*:[[:space:]]*"/ && index($0, target_fs) { in_part=1 }
        in_part && $0 ~ ("\"" section "\"[[:space:]]*:") { in_section=1; saw_unit=0 }
        in_section && $0 ~ /"unit"[[:space:]]*:/ { saw_unit=1 }
        in_section && saw_unit && $0 ~ /"value"[[:space:]]*:/ && replaced==0 {
          sub(/("value"[[:space:]]*:[[:space:]]*)[0-9]+/, "\\1" new_val)
          replaced=1; in_section=0; in_part=0
        }
        { print }
      ' target_fs="$TARGET_FS" section="$SECTION" new_val="$NEW_VAL" "$CONF_RUN" > "$TMP" && mv "$TMP" "$CONF_RUN"
    fi
  fi
fi

INSTALL_OK=0
echo "[XOs] Using config: $CONF_RUN"
if [ -f "$CREDS_PATH" ]; then
  echo "[XOs] Using creds: $CREDS_PATH"
  if archinstall --config "$CONF_RUN" --creds "$CREDS_PATH"; then INSTALL_OK=1; fi
else
  echo "[XOs] Credentials file not found at $CREDS_PATH, proceeding without creds."
  if archinstall --config "$CONF_RUN"; then INSTALL_OK=1; fi
fi

# Postinstall (branding xos)
if [ "$INSTALL_OK" = "1" ] && [ -f /root/xos-postinstall.sh ]; then
  bash /root/xos-postinstall.sh || true
else
  if [ "$INSTALL_OK" != "1" ]; then
    echo "[XOs] Archinstall failed. Check /var/log/archinstall/install.log for details." || true
  fi
fi
