#!/bin/bash
# Bench env overlay: identical to the main pack env, except it swaps in the full
# BENCHMARK topology (bench/process.csv - the stripped default plus the extra
# mapped readers and an rdb needed for the A/B/C/D comparison) by overriding
# TORQPROCESSES. The default appconfig/process.csv is left untouched.
# Use as: SETENV=<pack>/bench/bench-env.sh <TorQ>/torq.sh start all
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/nordb-env.sh"
export TORQPROCESSES=${TORQAPPHOME}/bench/process.csv

# --- benchmark port map ------------------------------------------------------
# Derived from KDBBASEPORT (set in nordb-env.sh) so changing the base port moves
# the whole bench suite with it. The offsets MUST match bench/process.csv.
# run.sh / matrix.sh / concurrency.sh source this file and use only these names.
export BENCH_STP=$((KDBBASEPORT))                 # stp1
export BENCH_WDB=$((KDBBASEPORT + 5))             # wdb1
export BENCH_SORT=$((KDBBASEPORT + 6))            # sort1
export BENCH_DEFERRED=$((KDBBASEPORT + 2))        # db1  - setup A, deferred reader
export BENCH_RDB=$((KDBBASEPORT + 4))             # rdb1 - setup D, in-memory control
export BENCH_MAPPED=$((KDBBASEPORT + 8))          # db2  - setup B, mapped reader
export BENCH_PAR="$((KDBBASEPORT + 9)) $((KDBBASEPORT + 10)) $((KDBBASEPORT + 11)) $((KDBBASEPORT + 12))"
                                                  # db3-6 - setup C, parallel mapped readers
export BENCH_NPAR=$(set -- $BENCH_PAR; echo $#)   # how many readers setup C uses

# every port the bench topology must have listening before it can run
# (discovery is deliberately excluded - nothing here queries it directly)
export BENCH_PORTS="$BENCH_STP $BENCH_WDB $BENCH_SORT $BENCH_DEFERRED $BENCH_RDB $BENCH_MAPPED $BENCH_PAR"
export BENCH_NPORTS=$(set -- $BENCH_PORTS; echo $#)
