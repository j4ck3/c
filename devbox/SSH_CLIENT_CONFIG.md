# SSH Client Configuration for Devbox

To prevent "Connection reset by peer" errors when using SUPER+N to quickly open SSH connections, configure SSH connection multiplexing on your **client machine** (not in the container).

## Add to your `~/.ssh/config`:

```ssh-config
Host devbox localhost
    HostName localhost
    Port 2222
    User dev
    # Enable connection multiplexing - reuse existing connections
    ControlMaster auto
    ControlPath ~/.ssh/control-%r@%h:%p
    ControlPersist 10m
    # Retry connection attempts
    ServerAliveInterval 60
    ServerAliveCountMax 3
    # Reduce connection timeout
    ConnectTimeout 5
```

## Benefits:

1. **Connection Reuse**: When you press SUPER+N multiple times quickly, SSH will reuse the existing connection instead of creating new ones
2. **Faster Connections**: Subsequent connections are instant (no handshake needed)
3. **Reduced Server Load**: Fewer connection attempts = less chance of connection resets
4. **Automatic Retry**: If a connection fails, SSH will retry automatically

## After adding this config:

1. Create the control directory:
   ```bash
   mkdir -p ~/.ssh
   ```

2. Test the connection:
   ```bash
   ssh devbox
   ```

3. Try SUPER+N multiple times quickly - it should work smoothly now!

## Alternative: Add a small delay

If you can't modify SSH config, you can add a small delay in your SUPER+N shortcut command:

```bash
# Instead of: ssh dev@localhost -p 2222
# Use: sleep 0.2 && ssh dev@localhost -p 2222
```

This gives SSH a moment to handle each connection before the next one arrives.
