#!/bin/sh
# Keep npm_services (172.25.0.0/16) container-to-container traffic off
# Netbird's FORWARD rebuilds. With br_netfilter=1, Caddy→Trilium is
# forwarded through host iptables; peer churn rewrites those rules and
# the hop dies (502 dial timeout / no route to host).
set -eu
INTERVAL="${INTERVAL:-5}"

ensure_sysctl() {
	if [ -w /proc/sys/net/bridge/bridge-nf-call-iptables ]; then
		echo 0 > /proc/sys/net/bridge/bridge-nf-call-iptables || true
		echo 0 > /proc/sys/net/bridge/bridge-nf-call-ip6tables || true
	fi
}

ensure_forward_accept() {
	# Must stay first. Netbird inserts its wt0 rules at the top on reconcile.
	first="$(iptables -S FORWARD 2>/dev/null | awk 'NR==2')"
	case "$first" in
	*"-s 172.25.0.0/16 -d 172.25.0.0/16 -j ACCEPT"*)
		return 0
		;;
	esac
	iptables -D FORWARD -s 172.25.0.0/16 -d 172.25.0.0/16 -j ACCEPT 2>/dev/null || true
	iptables -I FORWARD 1 -s 172.25.0.0/16 -d 172.25.0.0/16 -j ACCEPT
}

while true; do
	ensure_sysctl
	ensure_forward_accept
	sleep "$INTERVAL"
done
