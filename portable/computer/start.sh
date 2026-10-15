#!/bin/sh
set -eu
mkdir -p "$HOME/workspace" "$HOME/.config"
Xvfb :88 -screen 0 1280x800x24 -nolisten tcp &
i=0
until xdotool getdisplaygeometry >/dev/null 2>&1; do i=$((i+1)); [ "$i" -lt 50 ] || exit 1; sleep .2; done
openbox >/tmp/openbox.log 2>&1 &
x11vnc -storepasswd "$SHIRO_VNC_PASSWORD" /tmp/shiro-vnc-password >/dev/null
x11vnc -display :88 -rfbauth /tmp/shiro-vnc-password -forever -shared -localhost -rfbport 5900 >/tmp/vnc.log 2>&1 &
chromium --no-sandbox --user-data-dir="$HOME/.config/shiro-browser" --remote-debugging-port=9288 --remote-debugging-address=127.0.0.1 --no-first-run --disable-dev-shm-usage --window-size=1280,800 --start-maximized about:blank >/tmp/chromium.log 2>&1 &
exec websockify --web=/usr/share/novnc/ 6080 localhost:5900
