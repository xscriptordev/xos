#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────
# XOs postinstall: branding + wallpaper + GDM + hooks
# ────────────────────────────────────────────────

# 0) Verify that /mnt is the installed system
if ! mountpoint -q /mnt; then
  echo "[XOs] /mnt is not mounted. Did archinstall finish?"
  exit 1
fi

# 1) Custom /etc/os-release (so GNOME → About shows XOs)
echo "[XOs] Writing /mnt/etc/os-release…"
install -d -m 0755 /mnt/etc
[ -f /mnt/etc/os-release ] && cp /mnt/etc/os-release /mnt/etc/os-release.arch.bak || true
cat > /mnt/etc/os-release <<'XEOF'
NAME="XOs"
PRETTY_NAME="XOs Linux"
ID=xos
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR="0;36"
HOME_URL="https://dev.xscriptor.com/xos"
DOCUMENTATION_URL="https://dev.xscriptor.com/xos/docs"
SUPPORT_URL="https://dev.xscriptor.com/xos/support"
BUG_REPORT_URL="https://github.com/xscriptordev/XOs"
LOGO=distributor-logo
XEOF
chmod 0644 /mnt/etc/os-release

# (Optional) lsb-release for compatibility
echo "[XOs] Writing /mnt/etc/lsb-release…"
cat > /mnt/etc/lsb-release <<'EOF'
DISTRIB_ID=XOs
DISTRIB_RELEASE=rolling
DISTRIB_DESCRIPTION="XOs Linux"
EOF
chmod 0644 /mnt/etc/lsb-release

# 2) Assets (distributor-logo.svg icon and wallpaper)
ASSET_DIR="/root/xos-assets"
WALL="xos-wallpaper.png"   # same for light/dark

echo "[XOs] Copying assets…"
# Icon 'distributor-logo' (SVG) for GNOME → About and also for GDM
install -d /mnt/usr/share/icons/hicolor/scalable/apps
if [ -f "$ASSET_DIR/icons/distributor-logo.svg" ]; then
  install -m 0644 "$ASSET_DIR/icons/distributor-logo.svg" \
    /mnt/usr/share/icons/hicolor/scalable/apps/distributor-logo.svg
fi

# (Removed: any .png copies for logos)
# (Removed: /usr/local/share/pixmaps/xos-logo.png)

# Wallpaper(s) (kept as-is)
install -d /mnt/usr/share/backgrounds/XOs
if [ -f "$ASSET_DIR/backgrounds/$WALL" ]; then
  install -m 0644 "$ASSET_DIR/backgrounds/$WALL" \
    /mnt/usr/share/backgrounds/XOs/$WALL
fi

# 3) dconf defaults (default wallpaper and GDM logo in SVG)
echo "[XOs] dconf settings (default wallpaper and GDM logo)…"
install -d /mnt/etc/dconf/db/local.d
cat > /mnt/etc/dconf/db/local.d/00-xos <<EOF
[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/XOs/$WALL'
picture-uri-dark='file:///usr/share/backgrounds/XOs/$WALL'
picture-options='zoom'
primary-color='#000000'
secondary-color='#000000'
EOF

install -d /mnt/etc/dconf/db/gdm.d
cat > /mnt/etc/dconf/db/gdm.d/00-xos <<'EOF'
[org/gnome/login-screen]
logo='/usr/share/icons/hicolor/scalable/apps/distributor-logo.svg'
EOF

# dconf profiles so defaults from /etc/dconf/db/* apply
install -d /mnt/etc/dconf/profile
cat > /mnt/etc/dconf/profile/user <<'EOF'
user-db:user
system-db:local
EOF
cat > /mnt/etc/dconf/profile/gdm <<'EOF'
user-db:user
system-db:gdm
EOF

# 4) Script + pacman hook to keep /etc/os-release after updates
echo "[XOs] Installing script and pacman hook for /etc/os-release…"

# 4.1) Script that (re)writes /etc/os-release
install -d /mnt/usr/local/sbin
cat > /mnt/usr/local/sbin/xos-keep-os-release.sh <<'EOS'
#!/bin/sh
set -eu
cat >/etc/os-release <<'XEOF'
NAME="XOs"
PRETTY_NAME="XOs Linux"
ID=xos
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR="0;36"
HOME_URL="https://dev.xscriptor.com/xos"
DOCUMENTATION_URL="https://dev.xscriptor.com/xos/docs"
SUPPORT_URL="https://dev.xscriptor.com/xos/support"
BUG_REPORT_URL="https://github.com/xscriptordev/XOs"
LOGO=distributor-logo
XEOF
EOS
chmod 0755 /mnt/usr/local/sbin/xos-keep-os-release.sh

# 4.2) pacman hook that calls the script
install -d /mnt/etc/pacman.d/hooks
cat > /mnt/etc/pacman.d/hooks/zz-xos-os-release.hook <<'EOS'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = filesystem

[Action]
Description = Keep XOs /etc/os-release
When = PostTransaction
Exec = /usr/local/sbin/xos-keep-os-release.sh
EOS
chmod 0644 /mnt/etc/pacman.d/hooks/zz-xos-os-release.hook

# 5) Compile dconf and refresh icon cache in the installed system
echo "[XOs] Compiling dconf databases and refreshing icons…"
if command -v arch-chroot >/dev/null 2>&1; then
  arch-chroot /mnt sh -lc 'dconf update || true'
  arch-chroot /mnt sh -lc 'command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -f /usr/share/icons/hicolor || true'
fi

echo "[XOs] All set: os-release, SVG icon, GDM and default wallpaper applied."


# 6) GRUB: force "XOs Linux" in menu titles
echo "[XOs] Adjusting GRUB to show 'XOs Linux'…"

# Ensure /boot is mounted inside the target (needed if there's a separate ESP)
if ! mountpoint -q /mnt/boot; then
  echo "[XOs] Notice: /mnt/boot is not mounted. Trying to mount via fstab inside the chroot…"
  arch-chroot /mnt sh -lc 'mount -a || true'
fi

# Write/update GRUB_DISTRIBUTOR directly in /etc/default/grub
arch-chroot /mnt sh -lc '
  install -d -m 0755 /etc/default
  if [ -f /etc/default/grub ]; then
    sed -i "/^GRUB_DISTRIBUTOR=/d" /etc/default/grub
    printf "\nGRUB_DISTRIBUTOR=\"XOs Linux\"\n" >> /etc/default/grub
  else
    printf "GRUB_DISTRIBUTOR=\"XOs Linux\"\n" > /etc/default/grub
  fi
'

# Regenerate GRUB config (also inject the variable via env for maximum compatibility)
if arch-chroot /mnt command -v grub-mkconfig >/dev/null 2>&1; then
  arch-chroot /mnt env GRUB_DISTRIBUTOR="XOs Linux" grub-mkconfig -o /boot/grub/grub.cfg || true
elif [ -f /mnt/boot/grub/grub.cfg ]; then
  # Emergency fallback if grub-mkconfig is not yet installed:
  echo "[XOs] grub-mkconfig is not available. Patching titles temporarily…"
  sed -i "s/menuentry 'Arch Linux'/menuentry 'XOs Linux'/g" /mnt/boot/grub/grub.cfg || true
fi

# (Optional) Show the first entry to verify the name
arch-chroot /mnt sh -lc 'grep -m1 "^menuentry " /boot/grub/grub.cfg || true'


# 7) Install XOs base tools
echo "[XOs] Installing base tools (CLI and Dev)..."

arch-chroot /mnt sh -lc '
  set -euo pipefail
  echo "[XOs] Updating package database..."
  pacman -Sy --noconfirm

  echo "[XOs] Installing main packages..."
  pacman -S --noconfirm --needed \
    git \
    wget \
    kitty \
    curl \
    helix \
    ptyxis \
    zellij \
    yazi \
    starship \
    nodejs \
    npm \
    pnpm \
    btop \
    fastfetch \
    zsh \
    docker \
    docker-compose \
    base-devel \
    code

  echo "[XOs] Enabling docker..."
  systemctl enable docker.service || true

  echo "[XOs] Tools installed successfully."
'

# 8) Apps customization installation

echo "[XOs] Applying XOs custom configuration..."

# Detect first real user in /mnt/home
USER_DIR=$(find /mnt/home -mindepth 1 -maxdepth 1 -type d | head -n 1)
if [ -n "$USER_DIR" ]; then
  USER_NAME=$(basename "$USER_DIR")
  echo "[XOs] Detected user: $USER_NAME"

  # List of folders to sync
  CONFIG_DIRS=("kitty" "helix" "yazi" "zellij" "fastfetch")

  # Ensure ~/.config exists
  install -d -m 0700 "$USER_DIR/.config"

  for dir in "${CONFIG_DIRS[@]}"; do
    if [ -d "/root/xos-assets/skel/.config/$dir" ]; then
      echo "[XOs] → Updating configuration: $dir"
      rsync -avh /root/xos-assets/skel/.config/$dir/ "$USER_DIR/.config/$dir/"
    fi
  done

  chroot /mnt chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.config"
  echo "[XOs] Custom configuration applied without removing additional content."
else
  echo "[XOs] No user detected in /mnt/home. Skipping configuration copy."
fi

# Also copy to /etc/skel (without deleting)
install -d -m 0755 /mnt/etc/skel/.config
rsync -avh /root/xos-assets/skel/.config/ /mnt/etc/skel/.config/


# 9) Script de post-reboot para primer inicio de sesión (solo una vez)
echo "[XOs] Instalando script de primer inicio (oneshot)…"
install -d -m 0755 /mnt/etc/profile.d
cat > /mnt/etc/profile.d/xos-first-login.sh <<'EOS'
#!/bin/sh
# Only act in interactive shells; otherwise, become a no-op
case "$-" in *i*) ;; *) return 0 2>/dev/null || : ;; esac
# Run-once per user in interactive shells
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/xos"
STATE="$STATE_DIR/firstlogin-shell.done"
[ -d "$STATE_DIR" ] || mkdir -p "$STATE_DIR" 2>/dev/null || :
[ -f "$STATE" ] && return 0 2>/dev/null || :
if [ -x /usr/local/sbin/xos-first-login-actions.sh ]; then
  /usr/local/sbin/xos-first-login-actions.sh || :
fi
date -Is > "$STATE" 2>/dev/null || :
chmod 0644 "$STATE" 2>/dev/null || :
:
EOS
chmod 0755 /mnt/etc/profile.d/xos-first-login.sh

echo "[XOs] Installing first boot customization service..."
arch-chroot /mnt sh -lc '
  set -eu
  install -d -m 0755 /usr/local/sbin
  cat > /usr/local/sbin/xos-firstboot.sh << "EOS"
#!/bin/sh
set -eu
# Inform the user on first boot
echo "──────────────────────────────────────────"
echo "The system is finalizing its configuration."
echo "Do not close this window until it finishes."
echo "Log in if necessary to allow networking."
echo "When it completes, reboot to apply the last changes."
echo "──────────────────────────────────────────"
STATE="/var/lib/xos/firstboot.done"
mkdir -p /var/lib/xos
[ -f "$STATE" ] && exit 0
if command -v systemctl >/dev/null 2>&1; then
  systemctl --quiet is-active network-online.target || systemctl --wait is-active network-online.target || true
fi
i=0
until curl -fsSL -o /dev/null https://raw.githubusercontent.com/xscriptor/X/main/x/x.sh; do
  i=$((i+1))
  [ "$i" -ge 30 ] && break
  sleep 2
done
cd /root 2>/dev/null || cd /tmp
curl -sLO https://raw.githubusercontent.com/xscriptor/X/main/x/x.sh || exit 0
chmod +x x.sh || true
./x.sh || true
touch "$STATE"
exit 0
EOS
  chmod 0755 /usr/local/sbin/xos-firstboot.sh
  install -d -m 0755 /etc/systemd/system
  cat > /etc/systemd/system/xos-firstboot.service << "EOS"
[Unit]
Description=XOs first boot customization
Wants=network-online.target
After=network-online.target
ConditionPathExists=!/var/lib/xos/firstboot.done

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/xos-firstboot.sh

[Install]
WantedBy=multi-user.target
EOS
  # xos-firstboot.service not enabled; GNOME autostart will handle first-run
'

# First terminal open hook (per-user, self-delete)
echo "[XOs] Installing first terminal run hook..."
arch-chroot /mnt sh -lc '
  set -eu
  install -d -m 0755 /usr/local/bin
  cat > /usr/local/bin/xos-first-terminal.sh << "EOS"
#!/bin/sh
set -eu
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/xos"
STATE="$STATE_DIR/firstterminal.done"
mkdir -p "$STATE_DIR"
[ -f "$STATE" ] && exit 0
printf "\n──────────────────────────────────────────\n"
printf "Finalizing system configuration...\n"
printf "──────────────────────────────────────────\n\n"
cd "$HOME" 2>/dev/null || cd /tmp
curl -sLO https://raw.githubusercontent.com/xscriptor/X/main/x/x.sh || exit 0
chmod +x x.sh || true
./x.sh || true
touch "$STATE"
rm -f "$HOME/.config/xos/first-terminal.rc"
exit 0
EOS
  chmod 0755 /usr/local/bin/xos-first-terminal.sh
'
if [ -n "$USER_DIR" ]; then
  install -d -m 0755 "$USER_DIR/.config/xos"
  cat > "$USER_DIR/.config/xos/first-terminal.rc" << 'EOS'
# XOs: first terminal run hook
case "$-" in *i*)
  /usr/local/bin/xos-first-terminal.sh
  ;;
esac
EOS
  for rc in ".bashrc" ".zshrc"; do
    if [ -f "$USER_DIR/$rc" ]; then
      if ! grep -q 'first-terminal.rc' "$USER_DIR/$rc" 2>/dev/null; then
        echo '[ -f "$HOME/.config/xos/first-terminal.rc" ] && . "$HOME/.config/xos/first-terminal.rc"' >> "$USER_DIR/$rc"
      fi
    else
      echo '[ -f "$HOME/.config/xos/first-terminal.rc" ] && . "$HOME/.config/xos/first-terminal.rc"' > "$USER_DIR/$rc"
    fi
  done
  chroot /mnt chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.config/xos"
fi
install -d -m 0755 /mnt/etc/skel/.config/xos
cat > /mnt/etc/skel/.config/xos/first-terminal.rc << 'EOS'
# XOs: first terminal run hook
case "$-" in *i*)
  /usr/local/bin/xos-first-terminal.sh
  ;;
esac
EOS
for rc in ".bashrc" ".zshrc"; do
  if [ -f "/mnt/etc/skel/$rc" ]; then
    if ! grep -q 'first-terminal.rc' "/mnt/etc/skel/$rc" 2>/dev/null; then
      echo '[ -f "$HOME/.config/xos/first-terminal.rc" ] && . "$HOME/.config/xos/first-terminal.rc"' >> "/mnt/etc/skel/$rc"
    fi
  else
    echo '[ -f "$HOME/.config/xos/first-terminal.rc" ] && . "$HOME/.config/xos/first-terminal.rc"' > "/mnt/etc/skel/$rc"
  fi
done


