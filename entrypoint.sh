#!/bin/sh
set -e

# Load kernel modules required by strongSwan / IPsec.
modprobe af_key 2>/dev/null || true
modprobe ah4    2>/dev/null || true
modprobe esp4   2>/dev/null || true
modprobe ipcomp 2>/dev/null || true

# Enable IP forwarding so the VPN server can route traffic for clients.
sysctl -w net.ipv4.ip_forward=1          >/dev/null 2>&1 || true
sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1 || true

# Graceful shutdown: stop strongSwan when the container receives SIGTERM or SIGINT.
_stop() {
    echo "[entrypoint] Stopping strongSwan..."
    ipsec stop
    exit 0
}
trap _stop TERM INT

echo "[entrypoint] Starting strongSwan..."
# Start the IKE daemon in the foreground; --nofork keeps it attached to the terminal
# so Docker can observe the process and react to its exit.
ipsec start --nofork &
IPSEC_PID=$!

# Wait for the background process and relay its exit code.
wait "$IPSEC_PID"
