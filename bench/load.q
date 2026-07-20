// =============================================================================
// bench/load.q - seed the benchmark dataset through the real STP -> WDB pipeline.
// Publishes ~50M trade rows to match the blog's NYSE TAQ day, then flushes the
// WDB and waits for the IDBs to catch up, so all query targets (idb deferred,
// idb mapped, rdb in-mem) end with the same data on disk / in memory.
// Run: q bench/load.q   (cluster must be up)
// Ports are derived from $KDBBASEPORT (default 7100) with the offsets in
// bench/process.csv, so this follows the cluster if the base port changes.
// =============================================================================
\c 2000 2000
bp:$[count s:getenv`KDBBASEPORT; "J"$s; 7100];
conn:{[off] hopen `$":localhost:",string[bp+off],":admin:admin"};
stp:conn 0;                             // stp1
wdb:conn 5;                             // wdb1
a:conn 2;                               // db1 (deferred) - used as the catch-up barrier
r:conn 4;                               // rdb1 - verified at the end

// Skewed sym universe (like real TAQ volume): 10 liquid mega-caps that dominate,
// plus a long tail of ~5000 thin names. ~half the rows come from the 10 liquid
// syms (each ~5% of the day), half spread across the 5000 tail syms (each ~0.01%).
// This gives matrix.sh two selectivity tiers on the SAME g#-indexed sym column:
//   filter_sym     on AAPL (liquid) -> ~5%    of rows = large result
//   filter_sym_sel on a tail sym    -> ~0.01% of rows = small result (RDB's best case)
liquid:`AAPL`GOOG`MSFT`AMZN`META`TSLA`NVDA`NFLX`INTC`AMD;
tail:`$"S",/:string 1000+til 5000;
mksym:{[n] ?[(n?1f)<0.5; n?liquid; n?tail]};

// tradetime: an explicit trade-event timestamp we control, spread UNIFORMLY across
// a 6.5h session. It carries NO attribute (see database.q), so filter_time_* on it
// forces a full scan on every target - the no-attribute counterpart to the
// g#-indexed sym filters - and being uniform + per-row it supports any selectivity
// (matrix.sh picks the small/large thresholds by percentile). Distinct from the
// STP's ingest `time`, which only changes once per publish.
sessionstart:(`timestamp$.z.D)+09:30:00.000000000;
sessionns:`long$06:30:00.000000000;
mktradetime:{[n] sessionstart+`timespan$ n?sessionns};

// trade feed columns WITHOUT ingest time (segmented TP prepends it):
//   sym,price,size,stop,cond,ex,side,tradetime
mkbatch:{[n] (mksym n; n?100f; `int$n?1000; n?0b; n?" AB"; n?"NLQ"; n?`buy`sell; mktradetime n)};

// ~50M rows (50 x 1M). No per-batch sleeps: publish fast, then flush and wait for
// the readers to catch up. Override with nbatch=.. batchsz=..
nbatch:@[value;`nbatch;50];
batchsz:@[value;`batchsz;1000000];
target:nbatch*batchsz;

-1 "publishing ",string[target]," trade rows over ",string[nbatch]," batches...";
{[i] stp(`.u.upd;`trade;mkbatch batchsz);
     if[0=(i+1)mod 10; -1 "  published ",string[(i+1)*batchsz]," rows"];
 } each til nbatch;

-1 "flushing WDB and waiting for IDBs to catch up...";
wdb".wdb.savetodisk[]";
w:0;
while[(target > a"count trade") and w<120; system"sleep 1"; w+:1];
c:a"count trade";
-1 $[target>c;"WARNING incomplete after ",string[w]," s: ";""],"db1 count trade = ",string c;
-1 "rdb1 count trade = ",string r"count trade";
-1 "load complete.";
hclose'[(stp;wdb;a;r)];
exit 0
