#!/bin/bash
# =============================================================================
# bench/matrix.sh - latency matrix across FIVE setups, all server-side timed (\t):
#   A = db1  deferred (1 reader)                    $BENCH_DEFERRED
#   B = db2  mapped   (1 reader)                    $BENCH_MAPPED
#   C = db7  mapped + in-memory attribute (1 reader) $BENCH_MEMATTR
#   D = db3-6 mapped, N readers IN PARALLEL         $BENCH_PAR
#   E = rdb1 in-memory (1 reader)                   $BENCH_RDB
# A/B/C/E are per-query ms (one reader). D is the EFFECTIVE ms/query when N readers
# serve the load in parallel = aggregate throughput as latency = max(server-side
# time over the N) / (N x reps). D ~= B/N if it scales; compare D against E.
# C is B plus -.idb.usememattr 1: the live partition carries a real `g# on sym, so
# the filter_sym* rows should drop to RDB (column E) latency. Everything else should
# track B closely - that is the point of the column.
# Ports come from bench-env.sh (derived from KDBBASEPORT), sourced below so this
# script works standalone as well as via run.sh.
# Usage: REPS=10 bash bench/matrix.sh
# =============================================================================
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/bench-env.sh"     # -> BENCH_DEFERRED, BENCH_MAPPED, BENCH_PAR, BENCH_RDB, BENCH_NPAR
Q=${Q:-q}                       # q on PATH; override with Q=/path/to/q
CC="$HERE/cclient.q"
THRQ="$HERE/timethr.q"
REPS=${REPS:-3}                 # quick-run default; raise for tighter numbers

# The blog's 4-filter grid: {attribute, no-attribute} x {small, large result}, all
# on the same 50M-row table.
#            small result                   large result
#   attr     filter_sym_sel (g# sym ~0.01%) filter_sym     (g# sym ~5%)
#   no-attr  filter_time_sm (tradetime)     filter_time_lg (tradetime)
# sym carries g# (indexed lookup, cost ~ result size); tradetime carries NO attr
# (see database.q) so a filter on it scans the whole table regardless of result
# size. T_LG/T_SM are tradetime thresholds at fixed row percentiles, precomputed
# server-side (bench/timethr.q) so the queries stay static literals - no per-rep
# aggregation muddying the timing.
read T_LG T_SM < <($Q "$THRQ" -q 2>/dev/null)
: "${T_LG:?failed to compute tradetime thresholds - is the cluster up and seeded?}"

declare -A LBL=( ["filter_sym"]="select from trade where sym=\`AAPL" \
                 ["filter_sym_sel"]="select from trade where sym=\`S3000" \
                 ["filter_time_lg"]="select from trade where tradetime>=$T_LG" \
                 ["filter_time_sm"]="select from trade where tradetime>=$T_SM" \
                 ["agg_by_sym"]="select avg price, sum size by sym from trade" \
                 ["filtered_agg"]="select avg price by sym from trade where size>500" )
ORDER=(filter_sym filter_sym_sel filter_time_lg filter_time_sm agg_by_sym filtered_agg)

one(){ $Q "$CC" -q -st -port "$1" -reps "$REPS" -query "$2" 2>&1 | awk '/^RESULT/{print $3}'; }

# Preflight: confirm db7 really has the in-memory attribute applied. Without this a
# silently-ignored flag (bad extras string, deferred mode, sort.csv not found) would
# just look like "the overlay does not help" instead of "the overlay is not on".
MEMCHK=$($Q -q 2>/dev/null <<'EOF'
p:"J"$getenv`BENCH_MEMATTR; h:@[hopen;`$":localhost:",string[p],":admin:admin";0Ni];
-1 $[null h;"unreachable";h"\"usememattr=\",string[.idb.usememattr],\" attr=\",(string attr .idb.memcols[`trade;`sym]),\" rows=\",string count .idb.memcols[`trade;`sym]"]; exit 0
EOF
)
echo "db7 (column C) state: ${MEMCHK:-<could not query>}"
case "$MEMCHK" in
  *"usememattr=1 attr=g"*) : ;;
  *) echo "WARNING: db7 has no \`g# in-memory attribute - column C is NOT measuring what it claims" ;;
esac
echo ""

printf "ms/query, server-side, REPS=%s   (D = effective ms/q across %s parallel readers)\n\n" "$REPS" "$BENCH_NPAR"
printf "%-14s %12s %12s %12s %14s %12s\n" "query" "A_deferred" "B_mapped" "C_memattr" "D_${BENCH_NPAR}par(eff)" "E_rdb"
printf -- "-------------------------------------------------------------------------------------\n"

TMP=$(mktemp -d)
for k in "${ORDER[@]}"; do
  q="${LBL[$k]}"
  A=$(one "$BENCH_DEFERRED" "$q")
  B=$(one "$BENCH_MAPPED" "$q")
  C=$(one "$BENCH_MEMATTR" "$q")
  E=$(one "$BENCH_RDB" "$q")
  rm -f "$TMP"/*
  for p in $BENCH_PAR; do $Q "$CC" -q -st -port "$p" -reps "$REPS" -query "$q" > "$TMP/$p" 2>&1 & done
  wait
  Dmax=$(cat "$TMP"/* | awk '/^RESULT/{print $3}' | sort -n | tail -1)
  awk -v k="$k" -v a="$A" -v b="$B" -v c="$C" -v d="$Dmax" -v e="$E" -v r="$REPS" -v n="$BENCH_NPAR" 'BEGIN{
    printf "%-14s %12.2f %12.2f %12.2f %14.2f %12.2f\n", k, a/r, b/r, c/r, d/(r*n), e/r }'
done
rm -rf "$TMP"
