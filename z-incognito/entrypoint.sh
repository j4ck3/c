#!/bin/sh
# Clear stale X server lock/socket so X can start after container restarts.
# Without this, x-server fails with "Server is already active for display 99".
num="${DISPLAY#:}"
num="${num%%.*}"
if [ -n "$num" ]; then
  [ -f "/tmp/.X${num}-lock" ] && rm -f "/tmp/.X${num}-lock"
  [ -S "/tmp/.X11-unix/X${num}" ] && rm -f "/tmp/.X11-unix/X${num}"
fi
exec /usr/bin/supervisord -c /etc/neko/supervisord.conf
