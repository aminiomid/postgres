#!/usr/bin/env bash

set -euo pipefail

PATRONI_CONFIG="/etc/patroni/config.yml"
PATRONICTL="/opt/patroni/venv/bin/patronictl"

PRIMARY_IP="192.168.64.6"
REPLICA_IP="192.168.64.5"

echo "========================================"
echo " PostgreSQL HA - Replication Failure Test"
echo "========================================"
echo

echo "Initial cluster state:"
"$PATRONICTL" -c "$PATRONI_CONFIG" list

echo
echo "Blocking PostgreSQL replication traffic..."

iptables -A OUTPUT -p tcp -d "$PRIMARY_IP" --dport 5432 -j DROP
iptables -A INPUT  -p tcp -s "$PRIMARY_IP" --dport 5432 -j DROP

cleanup() {
    echo
    echo "Removing replication firewall rules..."

    iptables -D OUTPUT -p tcp -d "$PRIMARY_IP" --dport 5432 -j DROP || true
    iptables -D INPUT  -p tcp -s "$PRIMARY_IP" --dport 5432 -j DROP || true
}

trap cleanup EXIT

echo
echo "Replication connection is blocked."
echo "Waiting for replication to stop..."

sleep 15

echo
echo "Current replication status:"

sudo -u postgres psql \
    -h 127.0.0.1 \
    -p 5432 \
    -d postgres \
    -c "
    SELECT
        application_name,
        client_addr,
        state,
        sync_state
    FROM pg_stat_replication;
    "

echo
echo "Writing test data on primary..."

sudo -u postgres psql \
    -h 127.0.0.1 \
    -p 5432 \
    -d postgres \
    -c "
    CREATE TABLE IF NOT EXISTS replication_failure_test (
        id integer,
        test_name text,
        created_at timestamptz default now()
    );
    "

for i in 1 2 3; do
    sudo -u postgres psql \
        -h 127.0.0.1 \
        -p 5432 \
        -d postgres \
        -c "
        INSERT INTO replication_failure_test (id, test_name)
        VALUES ($i, 'replication-failure-test');
        "
done

echo
echo "Replication is intentionally broken."
echo "The primary should remain writable."

echo
echo "Restoring replication connectivity..."

cleanup
trap - EXIT

echo
echo "Waiting for replication to recover..."

for _ in {1..60}; do

    STREAMING_COUNT=$(
        sudo -u postgres psql \
            -h 127.0.0.1 \
            -p 5432 \
            -d postgres \
            -tAc "
            SELECT count(*)
            FROM pg_stat_replication
            WHERE state = 'streaming';
            "
    )

    if [ "$STREAMING_COUNT" -ge 1 ]; then
        break
    fi

    sleep 1
done

echo
echo "Final replication status:"

sudo -u postgres psql \
    -h 127.0.0.1 \
    -p 5432 \
    -d postgres \
    -c "
    SELECT
        application_name,
        client_addr,
        state,
        sync_state,
        pg_wal_lsn_diff(
            pg_current_wal_lsn(),
            replay_lsn
        ) AS replay_lag_bytes
    FROM pg_stat_replication;
    "

echo
echo "Final cluster state:"
"$PATRONICTL" -c "$PATRONI_CONFIG" list

echo
echo "RESULT: Replication failure test completed."