#!/bin/sh
# Monitor Neko for inactivity and restart container after timeout

NEKO_URL="http://localhost:8080/api/sessions"
CONTAINER_NAME="neko-incognito"
TIMEOUT_SECONDS=3600  # 1 hour
CHECK_INTERVAL=60     # Check every minute

last_activity=$(date +%s)

echo "Starting inactivity monitor (timeout: ${TIMEOUT_SECONDS}s)"

while true; do
    sleep $CHECK_INTERVAL
    
    # Check if any sessions are connected
    sessions=$(wget -q -O - "$NEKO_URL" 2>/dev/null | grep -c '"id"' || echo "0")
    
    if [ "$sessions" -gt 0 ]; then
        # Active sessions, reset timer
        last_activity=$(date +%s)
        echo "$(date): Active sessions: $sessions"
    else
        # No sessions, check if timeout reached
        now=$(date +%s)
        idle_time=$((now - last_activity))
        echo "$(date): No sessions, idle for ${idle_time}s"
        
        if [ $idle_time -ge $TIMEOUT_SECONDS ]; then
            echo "$(date): Timeout reached, restarting $CONTAINER_NAME"
            docker restart "$CONTAINER_NAME"
            last_activity=$(date +%s)
            echo "$(date): Container restarted, timer reset"
        fi
    fi
done


