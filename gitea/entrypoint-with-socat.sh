#!/bin/sh
# Listen on 3002 inside the container and forward to 3000, so LOCAL_ROOT_URL=http://127.0.0.1:3002/
# works for both (1) registry token and (2) git shell callback.
socat TCP-LISTEN:3002,fork,reuseaddr TCP:127.0.0.1:3000 &
exec /usr/bin/entrypoint "$@"
