# fix for screen readers
if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

~/.automated_script.sh

if [ -f /root/customize_airootfs.sh ]; then
    bash /root/customize_airootfs.sh
else
    CUST=$(ls /root/customize_airootfs*.sh 2>/dev/null | head -n 1)
    [ -n "$CUST" ] && bash "$CUST"
fi
