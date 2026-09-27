#!/usr/bin/env bash

set -euo pipefail

PATRONI_CONFIG="/etc/patroni/config.yml"
PATRONICTL="/opt/patroni/venv/bin/patronictl"

REPLICA="postgres-1"

echo "========================================"
echo " PostgreSQL HA - Replica Failure Test"
echo "========================================"
echo

echo "Initial cluster state:"
"$PATRONICTL" -c "$PATRONI_CONFIG" list

echo
echo "Stopping Patroni on replica: $REPLICA"

systemctl stop patroni

sleep 5

echo
echo "Cluster state while replica is down:"
"$PATRONICTL" -c "$PATRONI_CONFIG" list

echo
echo "Verifying that a leader still exists..."

LEADER_COUNT=$(
    "$PATRONICTL" -c "$PATRONI_CONFIG" list 2>/dev/null |
    grep -E '\|[[:space:]]*Leader[[:space:]]*\|' |
    wc -l
)

if [ "$LEADER_COUNT" -ne 1 ]; then
    echo "FAIL: Expected exactly one leader."
    exit 1
fi

echo "PASS: Primary remains available."

echo
echo "Restarting Patroni on replica..."

systemctl start patroni

echo
echo "Waiting for replica to return..."

for _ in {1..60}; do
    if "$PATRONICTL" -c "$PATRONI_CONFIG" list 2>/dev/null |
        grep -E "\|[[:space:]]*$REPLICA[[:space:]]*\|" |
        grep -q "streaming"
    then
        break
    fi

    sleep 1
done

echo
echo "Final cluster state:"
"$PATRONICTL" -c "$PATRONI_CONFIG" list

echo
echo "RESULT: Replica failure test completed."