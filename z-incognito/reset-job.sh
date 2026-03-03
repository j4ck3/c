#!/bin/sh
# Reset job: runs soft reset after idle timeout
# Clears browser data, clipboard, DNS cache - no container restart

NEKO_URL="http://localhost:8080/api/sessions"
NEKO_CLIPBOARD_URL="http://localhost:8080/api/room/clipboard"
CONTAINER_NAME="neko-incognito"
TIMEOUT_SECONDS=3600  # 1 hour
CHECK_INTERVAL=60     # Check every minute

last_activity=$(date +%s)

echo "Starting reset job (timeout: ${TIMEOUT_SECONDS}s)"
echo "Container: $CONTAINER_NAME"
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
            echo "$(date): Timeout reached (${idle_time}s >= ${TIMEOUT_SECONDS}s), performing soft reset"
            
            # Clear Neko room clipboard via API
            if curl -s -X POST "$NEKO_CLIPBOARD_URL" -H "Content-Type: application/json" -d '{"text":""}' -o /dev/null -w "%{http_code}" 2>/dev/null | grep -q '204\|200'; then
                echo "$(date): Cleared Neko clipboard"
            else
                echo "$(date): Note: Could not clear Neko clipboard via API (may need auth)"
            fi
            
            # Run soft reset inside container (clear X clipboard, DNS cache, browser data)
            if docker exec "$CONTAINER_NAME" sh /opt/soft-reset.sh 2>&1; then
                echo "$(date): Soft reset completed successfully"
                last_activity=$(date +%s)
                sleep 15
            else
                echo "$(date): ERROR: Soft reset failed"
            fi
        fi
    fi
done
