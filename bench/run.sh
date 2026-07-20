#!/bin/bash
# =============================================================================
# bench/run.sh - one-shot benchmark run. Brings up the BENCH topology (bench/
# process.csv: the stripped default plus the extra mapped readers + an rdb, via
# bench/bench-env.sh), wipes+reseeds ~50M rows, runs the latency matrix and the
# throughput bench, then tears the cluster back down.
# Usage: [REPS=3 N=8] bash bench/run.sh
# =============================================================================
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ENV="$HERE/bench-env.sh"
source "$ENV"                                   # -> TORQHOME, TORQAPPHOME, KDB* , TORQPROCESSES
TORQ="$TORQHOME/torq.sh"
DATA="$TORQDATAHOME"
Q=${Q:-q}
PORTS="$BENCH_PORTS"                            # from bench-env.sh, derived from KDBBASEPORT

echo "== stopping any running cluster =="
SETENV="$ENV" "$TORQ" stop all 2>/dev/null || true

echo "== wiping data ($DATA) =="
rm -rf "$DATA/db" "$DATA/tplogs" "$DATA/logs"
mkdir -p "$DATA/db" "$DATA/tplogs" "$DATA/logs"

echo "== starting bench topology =="
SETENV="$ENV" "$TORQ" start all
for i in $(seq 1 30); do
  up=0; for p in $PORTS; do timeout 1 bash -c "exec 3<>/dev/tcp/localhost/$p" 2>/dev/null && up=$((up+1)); done
  [ "$up" -eq "$BENCH_NPORTS" ] && break; sleep 1
done
echo "   $up/$BENCH_NPORTS bench ports up"

echo "== seeding ~50M rows =="
$Q "$HERE/load.q"

echo ""
echo "== latency matrix =="
bash "$HERE/matrix.sh"

echo ""
echo "== throughput =="
bash "$HERE/concurrency.sh"

echo ""
echo "== tearing down =="
SETENV="$ENV" "$TORQ" stop all
echo "done."
