// Two read modes, set per-process with -.idb.usemapping (default 1b = mapped):
//
//   Mode B (usemapping=1b, DEFAULT) - MAPPED. .Q.MAP[] maps all partitions once
//     (fast reads, no per-query re-map); each intraday reload re-maps ONLY the
//     live partition's .Q.pm slot (constant cost, independent of history size),
//     and EOD rollover re-maps everything. Query latency stays flat as history
//     grows. Leans on undocumented .Q internals (.Q.pm shape; a slot == get<dir>).
//
//   Mode A (usemapping=0b) - DEFERRED. No .Q.MAP; the stock IDB behaviour, where
//     every select mmap/munmaps the files it touches. Always fresh, but pays a
//     per-query re-map cost that grows with the partitions/columns touched.
//
// Both modes reload the sym file identically (stock intradayreload does it on each
// WDB flush); usemapping changes only what happens to the partition maps.
//
// Load order: this file loads before the stock idb.q, so the wiring is deferred to
// .proc.initlist (runs last) to wrap intradayreload/rollover rather than be
// clobbered by them.

\d .idb

// Re-map only the live partition's .Q.pm slot for every partitioned table,
// leaving all historical slots mapped/untouched. A .Q.pm slot is exactly
// `get <partition-splay-dir>`; we splice a fresh map of just the live partition
// back in with a dict-merge (nested-index assign .Q.pm[t][k]:v is `nyi).
refreshliveslot:{
    cp:currentpartition;
    {[cp;t]
        ks:key m:.Q.pm t;
        idx:where cp=last each ks;                                             // the live (dir;partition) key
        if[0=count idx;:()];                                                   // no live-partition slot for this table yet
        lk:ks first idx;
        pdir:.Q.dd[.Q.dd[lk 0;`$string lk 1];t];                               // <dir>/<partition>/<table> splay
        .Q.pm[t]:m,(enlist lk)!enlist get pdir;
     }[cp] each .Q.pt;
 };

// Keep the map current. force=0b (intraday): cheap live-slot refresh, unless the
// map is empty or has stopped covering every partition - then a full .Q.MAP[]. The
// coverage check matters because refreshliveslot can only refresh an existing slot,
// not add one: a partition that appears after the map was built (e.g. the next day)
// would otherwise stay silently invisible - .Q.p1 returns EMPTY for it rather than
// falling back to deferred. force=1b (EOD rollover): unconditional full remap, since
// the re-sorted partition leaves the whole map stale and \l does not refresh a
// mapped session.
ensuremapped:{[force]
    if[0=count .Q.pv;:()];                                                     // no partitions on disk yet
    if[force or (0=count .Q.pm) or any (count .Q.pv) <> count each .Q.pm each .Q.pt;
        :.Q.MAP[]];                                                            // forced / first map / coverage gap -> full remap
    refreshliveslot[];                                                         // else: cheap live-slot refresh
 };

// Applied post-load via .proc.initlist, once idb.q has defined intradayreload.
applymapmode:{[]
    if[not usemapping;
        .lg.o[`idb.mode;"IDB read mode A (deferred): no .Q.MAP, selects re-map per query"];
        :()];
    .lg.o[`idb.mode;"IDB read mode B (mapped): .Q.MAP[] + per-reload live-slot refresh"];
    ensuremapped[0b];                                                          // map what already exists at startup
    intradayreload_stock::intradayreload;                                      // wrap the reload so each WDB flush refreshes only the live slot
    intradayreload::{[x] .idb.intradayreload_stock[]; .idb.ensuremapped[0b];};
    rollover_stock::rollover;                                                  // wrap the EOD rollover to force a full remap
    rollover::{[pt] .idb.rollover_stock[pt]; .idb.ensuremapped[1b];};
 };

\d .
.proc.addinitlist".idb.applymapmode[]";                                        // run Mode-B wiring after idb.q loads
