#!/bin/sh
# Monitor Neko for inactivity and restart container after timeout
# Integrated with Docker API

NEKO_URL="http://localhost:8080/api/sessions"
CONTAINER_NAME="neko-incognito"
TIMEOUT_SECONDS=3600  # 1 hour
CHECK_INTERVAL=60     # Check every minute

last_activity=$(date +%s)

echo "Starting inactivity monitor (timeout: ${TIMEOUT_SECONDS}s)"
echo "Monitoring container: $CONTAINER_NAME"
echo "API endpoint: $NEKO_URL"

# Wait for neko container to be ready
echo "Waiting for neko container to be ready..."
max_wait=300
waited=0
while [ $waited -lt $max_wait ]; do
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Container $CONTAINER_NAME is running"
        break
    fi
    sleep 5
    waited=$((waited + 5))
done

if [ $waited -ge $max_wait ]; then
    echo "ERROR: Container $CONTAINER_NAME not found after ${max_wait}s"
    exit 1
fi

while true; do
    sleep $CHECK_INTERVAL
    
    # Verify container is still running
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "$(date): WARNING: Container $CONTAINER_NAME is not running, skipping check"
        sleep $CHECK_INTERVAL
        continue
    fi
    
    # Check if any sessions are connected using curl (more reliable than wget)
    sessions=0
    if command -v curl >/dev/null 2>&1; then
        response=$(curl -s -f "$NEKO_URL" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$response" ]; then
            sessions=$(echo "$response" | grep -c '"id"' || echo "0")
        fi
    elif command -v wget >/dev/null 2>&1; then
        response=$(wget -q -O - "$NEKO_URL" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$response" ]; then
            sessions=$(echo "$response" | grep -c '"id"' || echo "0")
        fi
    else
        echo "$(date): ERROR: Neither curl nor wget available, cannot check sessions"
        sleep $CHECK_INTERVAL
        continue
    fi
    
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
            echo "$(date): Timeout reached (${idle_time}s >= ${TIMEOUT_SECONDS}s), restarting $CONTAINER_NAME"
            
            # Use docker restart with proper error handling
            if docker restart "$CONTAINER_NAME" >/dev/null 2>&1; then
                echo "$(date): Container $CONTAINER_NAME restarted successfully"
                last_activity=$(date +%s)
                
                # Wait for container to be ready before resuming checks
                echo "Waiting for container to be ready after restart..."
                sleep 10
            else
                echo "$(date): ERROR: Failed to restart container $CONTAINER_NAME"
                # Try to get more info
                docker ps -a --filter "name=$CONTAINER_NAME" --format "{{.Status}}" 2>/dev/null || true
            fi
        fi
    fi
done


