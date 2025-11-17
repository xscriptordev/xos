#!/usr/bin/env bash
# Auto-start Archinstall for XOs (interactivo, sin JSON)
# - No limpia el MOTD antes de lanzar archinstall
# - Cuenta atrás de 5s con opción a cancelar (Ctrl+C)
# - Ejecuta /root/xos-postinstall.sh al finalizar con éxito

set -eo pipefail

run_xos_postinstall() {
  if [ -x /root/xos-postinstall.sh ]; then
    echo
    echo "→ Ejecutando postinstalación XOs…"
    if /root/xos-postinstall.sh; then
      echo "→ Postinstalación XOs completada."
    else
      echo "[XOs] Postinstalación falló."
      return 1
    fi
  else
    echo "[XOs] Falta /root/xos-postinstall.sh o no es ejecutable."
  fi
}

# 0) Evitar ejecución durante mkarchiso (entorno de build)
if ! grep -q "/run/archiso/bootmnt" /proc/mounts 2>/dev/null; then
  echo "[XOs Build] Detectado entorno de compilación mkarchiso. No se autoinicia."
  return 0 2>/dev/null || exit 0
fi

# Permitir desactivar con variable de entorno
if [ "${XOS_NO_AUTO:-0}" = "1" ]; then
  echo "[XOs] Autostart deactivated (XOS_NO_AUTO=1)."
  return 0 2>/dev/null || exit 0
fi

# 1) Only on TTY1 (preserve MOTD)
if [ "$(tty)" = "/dev/tty1" ]; then
  echo
  echo "──────────────────────────────────────────"
  echo "   XOs Live – Archinstall will start in 5s"
  echo "   Press Ctrl+C to cancel."
  echo "──────────────────────────────────────────"

  # Countdown without clearing the screen
  for i in 5 4 3 2 1; do
    printf "\rStarting archinstall in %s s… (Press Ctrl+C to cancel) " "$i"
    sleep 1
  done
  echo

  # Always run customize script; mandatory
  CUST="/root/customize_airootfs.sh"
  if [ ! -f "$CUST" ]; then
    CUST=$(find /root -maxdepth 1 -name 'customize_airootfs*.sh' -print -quit 2>/dev/null)
  fi
  if [ -n "$CUST" ] && [ -f "$CUST" ]; then
    echo "→ Launching $(basename "$CUST") (automated configuration)…"
    bash "$CUST"
  else
    echo "[XOs] customize_airootfs.sh is mandatory and missing; not starting archinstall."
  fi
fi
