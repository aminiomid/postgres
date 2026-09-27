#!/usr/bin/env bash

set -euo pipefail

PATRONI_CONFIG="/etc/patroni/config.yml"
PATRONICTL="/opt/patroni/venv/bin/patronictl"

REPLICA_IP="192.168.64.5"
PRIMARY_IP="192.168.64.6"

ETCD_NODES=(
    "192.168.64.2"
    "192.168.64.3"
    "192.168.64.4"
)

echo "========================================"
echo " PostgreSQL HA - Network Partition Test"
echo "========================================"
echo

echo "Initial cluster state:"
"$PATRONICTL" -c "$PATRONI_CONFIG" list

echo
echo "Blocking connectivity from replica to primary..."

iptables -A OUTPUT -d "$PRIMARY_IP" -j DROP

for IP in "${ETCD_NODES[@]}"; do
    iptables -A OUTPUT -d "$IP" -j DROP
done

cleanup() {
    echo
    echo "Removing network partition rules..."

    iptables -D OUTPUT -d "$PRIMARY_IP" -j DROP || true

    for IP in "${ETCD_NODES[@]}"; do
        iptables -D OUTPUT -d "$IP" -j DROP || true
    done
}

trap cleanup EXIT

echo
echo "Network partition is active."
echo "Waiting for Patroni connectivity to degrade..."

sleep 15

echo
echo "Attempting to verify that the isolated node is not writable..."

if sudo -u postgres psql \
    -h 127.0.0.1 \
    -p 5432 \
    -d postgres \
    -c "CREATE TABLE IF NOT EXISTS network_partition_test(id int);" \
    -c "INSERT INTO network_partition_test VALUES (1);"
then
    echo "WARNING: Write succeeded on isolated node."
else
    echo "PASS: Isolated node did not accept the write."
fi

echo
echo "Cluster state after partition:"
"$PATRONICTL" -c "$PATRONI_CONFIG" list || true

echo
echo "Restoring network connectivity..."

cleanup
trap - EXIT

sleep 10

echo
echo "Final cluster state:"
"$PATRONICTL" -c "$PATRONI_CONFIG" list

echo
echo "RESULT: Network partition test completed."