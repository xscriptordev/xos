#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────
# XOs postinstall: branding + fondo + GDM + hooks
# ────────────────────────────────────────────────

# 0) Comprobar que /mnt es el sistema instalado
if ! mountpoint -q /mnt; then
  echo "[XOs] /mnt no está montado. ¿Terminó archinstall?"
  exit 1
fi

# 1) /etc/os-release propio (para que GNOME → Acerca de ponga XOs)
echo "[XOs] Escribiendo /mnt/etc/os-release…"
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

# (Opcional) lsb-release para compatibilidad
echo "[XOs] Escribiendo /mnt/etc/lsb-release…"
cat > /mnt/etc/lsb-release <<'EOF'
DISTRIB_ID=XOs
DISTRIB_RELEASE=rolling
DISTRIB_DESCRIPTION="XOs Linux"
EOF
chmod 0644 /mnt/etc/lsb-release

# 2) Assets (icono distributor-logo.svg y wallpaper)
ASSET_DIR="/root/xos-assets"
WALL="xos-wallpaper.png"   # mismo en claro/oscuro

echo "[XOs] Copiando assets…"
# Icono 'distributor-logo' (SVG) para GNOME → Acerca de y también para GDM
install -d /mnt/usr/share/icons/hicolor/scalable/apps
if [ -f "$ASSET_DIR/icons/distributor-logo.svg" ]; then
  install -m 0644 "$ASSET_DIR/icons/distributor-logo.svg" \
    /mnt/usr/share/icons/hicolor/scalable/apps/distributor-logo.svg
fi

# (Eliminado: cualquier copia de .png para logos)
# (Eliminado: /usr/local/share/pixmaps/xos-logo.png)

# Fondo(s) de pantalla (se mantiene tal cual)
install -d /mnt/usr/share/backgrounds/XOs
if [ -f "$ASSET_DIR/backgrounds/$WALL" ]; then
  install -m 0644 "$ASSET_DIR/backgrounds/$WALL" \
    /mnt/usr/share/backgrounds/XOs/$WALL
fi

# 3) Defaults de dconf (fondo por defecto y logo de GDM en SVG)
echo "[XOs] Ajustes dconf (fondo por defecto y logo GDM)…"
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

# Perfiles dconf para que se apliquen los defaults de /etc/dconf/db/*
install -d /mnt/etc/dconf/profile
cat > /mnt/etc/dconf/profile/user <<'EOF'
user-db:user
system-db:local
EOF
cat > /mnt/etc/dconf/profile/gdm <<'EOF'
user-db:user
system-db:gdm
EOF

# 4) Script + hook para mantener /etc/os-release tras updates
echo "[XOs] Instalando script y hook de pacman para /etc/os-release…"

# 4.1) Script que (re)escribe /etc/os-release
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

# 4.2) Hook de pacman que llama al script
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

# 5) Compilar dconf y refrescar caché de iconos en el sistema instalado
echo "[XOs] Compilando bases dconf y refrescando iconos…"
if command -v arch-chroot >/dev/null 2>&1; then
  arch-chroot /mnt sh -lc 'dconf update || true'
  arch-chroot /mnt sh -lc 'command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -f /usr/share/icons/hicolor || true'
fi

echo "[XOs] Todo listo: os-release, icono SVG, GDM y fondo por defecto aplicados."


# 6) GRUB: forzar "XOs Linux" en los títulos
echo "[XOs] Ajustando GRUB para mostrar 'XOs Linux'…"

# Asegurar que /boot esté montado dentro del target (necesario si hay ESP separada)
if ! mountpoint -q /mnt/boot; then
  echo "[XOs] Aviso: /mnt/boot no está montado. Intentando montar vía fstab dentro del chroot…"
  arch-chroot /mnt sh -lc 'mount -a || true'
fi

# Escribir/actualizar GRUB_DISTRIBUTOR directamente en /etc/default/grub
arch-chroot /mnt sh -lc '
  install -d -m 0755 /etc/default
  if [ -f /etc/default/grub ]; then
    sed -i "/^GRUB_DISTRIBUTOR=/d" /etc/default/grub
    printf "\nGRUB_DISTRIBUTOR=\"XOs Linux\"\n" >> /etc/default/grub
  else
    printf "GRUB_DISTRIBUTOR=\"XOs Linux\"\n" > /etc/default/grub
  fi
'

# Regenerar la config de GRUB (inyectando también la variable por entorno por máxima compatibilidad)
if arch-chroot /mnt command -v grub-mkconfig >/dev/null 2>&1; then
  arch-chroot /mnt env GRUB_DISTRIBUTOR="XOs Linux" grub-mkconfig -o /boot/grub/grub.cfg || true
elif [ -f /mnt/boot/grub/grub.cfg ]; then
  # Fallback de emergencia si no hay grub-mkconfig aún instalado:
  echo "[XOs] grub-mkconfig no está disponible. Parcheando títulos provisionalmente…"
  sed -i "s/menuentry 'Arch Linux'/menuentry 'XOs Linux'/g" /mnt/boot/grub/grub.cfg || true
fi

# (Opcional) Mostrar la primera entrada para comprobar el nombre
arch-chroot /mnt sh -lc 'grep -m1 "^menuentry " /boot/grub/grub.cfg || true'


# 7) Instalación de herramientas base XOs
echo "[XOs] Instalando herramientas base (CLI y Dev)..."

arch-chroot /mnt sh -lc '
  set -euo pipefail
  echo "[XOs] Actualizando base de paquetes..."
  pacman -Sy --noconfirm

  echo "[XOs] Instalando paquetes principales..."
  pacman -S --noconfirm --needed \
    git \
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
    docker \
    docker-compose \
    base-devel \
    code

  echo "[XOs] Habilitando docker..."
  systemctl enable docker.service || true

  echo "[XOs] Herramientas instaladas correctamente."
'

# 8) apps customization installation

echo "[XOs] Aplicando configuración personalizada de XOs..."

# Detectar primer usuario real en /mnt/home
USER_DIR=$(find /mnt/home -mindepth 1 -maxdepth 1 -type d | head -n 1)
if [ -n "$USER_DIR" ]; then
  USER_NAME=$(basename "$USER_DIR")
  echo "[XOs] Usuario detectado: $USER_NAME"

  # Lista de carpetas que deseas sincronizar
  CONFIG_DIRS=("kitty" "helix" "yazi" "zellij" "fastfetch")

  # Asegurar existencia de ~/.config
  install -d -m 0700 "$USER_DIR/.config"

  for dir in "${CONFIG_DIRS[@]}"; do
    if [ -d "/root/xos-assets/skel/.config/$dir" ]; then
      echo "[XOs] → Actualizando configuración: $dir"
      rsync -avh /root/xos-assets/skel/.config/$dir/ "$USER_DIR/.config/$dir/"
    fi
  done

  chroot /mnt chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.config"
  echo "[XOs] Configuración personalizada aplicada sin eliminar contenido adicional."
else
  echo "[XOs] No se detectó ningún usuario en /mnt/home. Saltando copia de configuración."
fi

# Copiar también a /etc/skel (sin borrar)
install -d -m 0755 /mnt/etc/skel/.config
rsync -avh /root/xos-assets/skel/.config/ /mnt/etc/skel/.config/


## 9) vscode extensions

echo "[XOs] Instalando extensiones de Visual Studio Code..."

# Detectar qué binario usar (code o code-oss)
if arch-chroot /mnt command -v code >/dev/null 2>&1; then
  CODE_CMD="code"
elif arch-chroot /mnt command -v code-oss >/dev/null 2>&1; then
  CODE_CMD="code-oss"
else
  echo "[XOs] No se encontró VS Code ni Code OSS. Saltando instalación de extensiones."
  CODE_CMD=""
fi

if [ -n "$CODE_CMD" ]; then
  echo "[XOs] → Instalando Xscriptor Themes..."
  arch-chroot /mnt $CODE_CMD --install-extension xscriptor.xscriptor-themes || true

  echo "[XOs] → Instalando XGlass..."
  arch-chroot /mnt $CODE_CMD --install-extension xscriptor.xglass || true

  echo "[XOs] → Instalando X Dark Colors..."
  arch-chroot /mnt $CODE_CMD --install-extension xscriptor.x-dark-colors || true

  echo "[XOs] Extensiones de VS Code instaladas correctamente."
fi
