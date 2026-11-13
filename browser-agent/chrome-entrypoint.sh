#!/bin/sh
# Start Xvfb, a window manager, VNC + noVNC, then Chromium in the foreground.
set -eu
export DISPLAY=:99
rm -f /data/profile/Singleton* /tmp/.X99-lock
Xvfb :99 -screen 0 1440x900x24 -nolisten tcp &
sleep 1
fluxbox >/dev/null 2>&1 &
mkdir -p /tmp/vnc
x11vnc -storepasswd "${VNC_PASSWORD:?set VNC_PASSWORD in .env}" /tmp/vnc/passwd >/dev/null
x11vnc -display :99 -rfbauth /tmp/vnc/passwd -forever -shared -localhost -rfbport 5900 -quiet >/dev/null 2>&1 &
websockify --web /usr/share/novnc 6080 127.0.0.1:5900 >/dev/null 2>&1 &
exec chromium "$@"
