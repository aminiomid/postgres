#!/usr/bin/env bash

set -u

PATRONI_CONFIG="/etc/patroni/config.yml"
PATRONICTL="/opt/patroni/venv/bin/patronictl"

PASS=0
FAIL=0

pass() {
    echo "PASS: $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
}

echo "========================================"
echo " PostgreSQL HA Cluster Validation"
echo "========================================"
echo

echo "== 1. Patroni Cluster =="

if [ ! -x "$PATRONICTL" ]; then
    fail "patronictl not found at $PATRONICTL"
    PATRONI_AVAILABLE=false
else
    if "$PATRONICTL" -c "$PATRONI_CONFIG" list; then
        pass "Patroni cluster is reachable"
        PATRONI_AVAILABLE=true
    else
        fail "Patroni cluster is not reachable"
        PATRONI_AVAILABLE=false
    fi
fi

echo

echo "== 2. Leader Check =="

if [ "$PATRONI_AVAILABLE" = true ]; then

    LEADER_COUNT=$(
        "$PATRONICTL" -c "$PATRONI_CONFIG" list 2>/dev/null |
        grep -E '\|[[:space:]]*Leader[[:space:]]*\|' |
        wc -l
    )

    if [ "$LEADER_COUNT" -eq 1 ]; then
        pass "Exactly one leader exists"
    else
        fail "Expected exactly one leader, found $LEADER_COUNT"
    fi

else
    fail "Leader check skipped because Patroni is unavailable"
fi

echo

echo "== 3. PostgreSQL Connectivity =="

if sudo -u postgres psql \
    -h 127.0.0.1 \
    -p 5432 \
    -d postgres \
    -c "SELECT 1;" >/dev/null 2>&1
then
    pass "PostgreSQL is accepting local connections"
else
    fail "PostgreSQL connection failed"
fi

echo

echo "== 4. PostgreSQL Role =="

IS_RECOVERY=$(
    sudo -u postgres psql \
        -h 127.0.0.1 \
        -p 5432 \
        -d postgres \
        -tAc "SELECT pg_is_in_recovery();"
)

if [ "$IS_RECOVERY" = "f" ]; then
    pass "This node is writable primary"
else
    echo "INFO: This node is a replica"
fi

echo

echo "== 5. Replication =="

if [ "$IS_RECOVERY" = "f" ]; then

    REPLICA_COUNT=$(
        sudo -u postgres psql \
            -h 127.0.0.1 \
            -p 5432 \
            -d postgres \
            -tAc "SELECT count(*) FROM pg_stat_replication;"
    )

    STREAMING_COUNT=$(
        sudo -u postgres psql \
            -h 127.0.0.1 \
            -p 5432 \
            -d postgres \
            -tAc "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming';"
    )

    if [ "$REPLICA_COUNT" -ge 1 ] && [ "$REPLICA_COUNT" -eq "$STREAMING_COUNT" ]; then
        pass "All replicas are streaming"
    else
        fail "Replication is not healthy"
    fi

else
    echo "INFO: Replication check skipped on replica node"
fi

echo

echo "== 6. Replication Details =="

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

echo "== 7. Final Result =="

echo "PASS: $PASS"
echo "FAIL: $FAIL"

echo

if [ "$FAIL" -eq 0 ]; then
    echo "RESULT: VALIDATION PASSED"
    exit 0
else
    echo "RESULT: VALIDATION FAILED"
    exit 1
fi