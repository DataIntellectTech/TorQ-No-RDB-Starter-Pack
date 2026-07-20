#!/bin/bash
# =============================================================================
# bench/concurrency.sh - read THROUGHPUT headline (the "who needs an RDB" point):
#   a fixed batch of N identical queries, run by
#     (a) ONE traditional RDB, serially (single-threaded), and
#     (b) the no-RDB db readers (db3-6) in parallel (N/NPAR each).
#   throughput speedup = RDB-serial-time / parallel-readers-time.
#
# Uses a COMPUTE-BOUND query (median by group = sort-dominated). For such queries
# the mapped on-disk db costs ~the same per query as the in-memory RDB (the RDB's
# in-memory edge only helps cheap bandwidth-bound scans), so the parallel readers
# win ~NPARx. True parallelism via separate OS client processes (q can't parallelise
# IPC in-process); q-startup amortised over the per-client reps.
# Ports come from bench-env.sh (derived from KDBBASEPORT), sourced below so this
# script works standalone as well as via run.sh.
# Usage: N=24 QUERY="select med price by sym from trade" bash bench/concurrency.sh
# =============================================================================
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/bench-env.sh"     # -> BENCH_PAR, BENCH_NPAR, BENCH_RDB
Q=${Q:-q}                       # q on PATH; override with Q=/path/to/q
CC="$HERE/cclient.q"
N=${N:-8}                                               # total queries in the batch (quick-run default)
QUERY=${QUERY:-"select med price by sym from trade"}    # compute-bound by default
PER=$(( N / BENCH_NPAR ))
SOLO=$(echo $BENCH_PAR | cut -d' ' -f1)                 # one of the parallel readers, run alone

TMP=$(mktemp -d)

# (b) PARALLEL: NPAR IDBs, N/NPAR queries each, concurrent
for p in $BENCH_PAR; do
  $Q "$CC" -q -port "$p" -reps "$PER" -query "$QUERY" > "$TMP/$p" 2>&1 &
done
wait
# (a) SERIAL: 1 RDB, all N queries
$Q "$CC" -q -port "$BENCH_RDB" -reps "$N" -query "$QUERY" > "$TMP/rdb" 2>&1
# baseline: 1 db, all N queries (isolates parallelism from the in-mem-vs-disk axis)
$Q "$CC" -q -port "$SOLO" -reps "$N" -query "$QUERY" > "$TMP/dbsolo" 2>&1

parmax=$(for p in $BENCH_PAR; do cat "$TMP/$p"; done | awk '/^RESULT/{print $3}' | sort -n | tail -1)
rdbtot=$(awk '/^RESULT/{print $3}' "$TMP/rdb")
idbtot=$(awk '/^RESULT/{print $3}' "$TMP/dbsolo")

echo "query : $QUERY"
echo "batch : $N queries  (parallel = $PER per reader x $BENCH_NPAR readers)"
echo ""
echo "per-client totals (ms):"
for p in $BENCH_PAR; do cat "$TMP/$p"; done | grep RESULT | sed 's/^/    parallel /'
grep RESULT "$TMP/rdb"  | sed 's/^/    RDB      /'
grep RESULT "$TMP/dbsolo" | sed 's/^/    db-solo  /'
echo ""
awk -v r="$rdbtot" -v p="$parmax" -v i="$idbtot" -v n="$N" -v np="$BENCH_NPAR" 'BEGIN{
  printf "  RDB serial      (%d queries) : %7.0f ms   (%.1f q/s)\n", n, r, 1000*n/r;
  printf "  db  serial      (%d queries) : %7.0f ms   (%.1f q/s)\n", n, i, 1000*n/i;
  printf "  %d dbs parallel  (%d total)   : %7.0f ms   (%.1f q/s)\n", np, n, p, 1000*n/p;
  printf "\n";
  printf "  THROUGHPUT speedup vs RDB serial : %.2f x\n", r/p;
  printf "  parallel scaling vs 1 db         : %.2f x\n", i/p;
}'
rm -rf "$TMP"
