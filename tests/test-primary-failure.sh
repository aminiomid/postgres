#!/usr/bin/env bash

set -euo pipefail

PATRONI_CONFIG="/etc/patroni/config.yml"
PATRONICTL="/opt/patroni/venv/bin/patronictl"

PRIMARY="postgres-1"
EXPECTED_NEW_PRIMARY="postgres-2"

echo "========================================"
echo " PostgreSQL HA - Primary Failure Test"
echo "========================================"
echo

echo "Current cluster state:"
"$PATRONICTL" -c "$PATRONI_CONFIG" list

echo
echo "Stopping Patroni on $PRIMARY..."

systemctl stop patroni

START_TIME=$(date +%s)

echo "Waiting for failover..."

while true; do
    CURRENT_LEADER=$(
        "$PATRONICTL" -c "$PATRONI_CONFIG" list 2>/dev/null |
        awk -F'|' '$4 ~ /Leader/ {gsub(/ /, "", $2); print $2}'
    )

    if [ "$CURRENT_LEADER" = "$EXPECTED_NEW_PRIMARY" ]; then
        break
    fi

    if [ $(( $(date +%s) - START_TIME )) -ge 60 ]; then
        echo "FAIL: Failover did not complete within 60 seconds."
        exit 1
    fi

    sleep 1
done

FAILOVER_TIME=$(( $(date +%s) - START_TIME ))

echo
echo "New leader detected: $CURRENT_LEADER"
echo "Failover time: ${FAILOVER_TIME}s"

echo
echo "Cluster state after failover:"
"$PATRONICTL" -c "$PATRONI_CONFIG" list

echo
echo "Restarting Patroni on $PRIMARY..."

systemctl start patroni

echo
echo "Waiting for $PRIMARY to rejoin as replica..."

for _ in {1..60}; do
    if "$PATRONICTL" -c "$PATRONI_CONFIG" list 2>/dev/null |
        grep -E "\|[[:space:]]*$PRIMARY[[:space:]]*\|" |
        grep -q "Replica"
    then
        break
    fi

    sleep 1
done

echo
echo "Final cluster state:"
"$PATRONICTL" -c "$PATRONI_CONFIG" list

echo
echo "RESULT: Primary failure test completed."
echo "New primary: $EXPECTED_NEW_PRIMARY"
echo "Failover time: ${FAILOVER_TIME}s"