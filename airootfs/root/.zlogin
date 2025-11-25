if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

[ -x /root/.automated_script.sh ] && /root/.automated_script.sh
[ -f /root/xos-autostart.sh ] && bash /root/xos-autostart.sh
[ -f /root/xos-autostart.sh ] && bash /root/xos-autostart.sh
