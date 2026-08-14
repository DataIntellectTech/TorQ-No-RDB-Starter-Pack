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
// On top of Mode B, -.idb.usememattr (default 0b, opt-in) adds the IN-MEMORY
// ATTRIBUTE overlay. In kdb+ you cannot maintain an attribute on an on-disk column
// while appending to it. The attribute flag sits in the file header, but the index it
// points at is written as a FOOTER, after the data - so every append would shift it,
// pulling it out from under any memory-mapped reader. kdb+ avoids that by silently
// DROPPING the attribute on append (the file truncates back to header+data). So in
// the two modes above the live partition is un-indexed and selective lookups scan it.
//
// In-memory columns on the heap have no such problem: `g# is maintained across an
// append. And .Q.MAP[] leaves behind .Q.pm, a fixed dictionary of the mapped tables
// and their columns. .Q.pm is not mentioned at all in KX's documentation, so this
// should be considered somewhat experimental - but its existence means we can swap
// one column of the live slot for an in-memory copy carrying a real `g#, leaving the
// rest mapped:
//
//     .Q.pm[t]: <slot dict> , (enlist lk)!enlist @[T;`sym;:;memsym]
//
// The engine simply sees a column with a genuine attribute; it does not care whether
// that column is in-memory or mapped from disk. So this is transparent to everything
// - plain q-sql, `by sym`, aj - and composes with history: `p# serves the older
// slots, heap `g# the live one. The copy is derived from the disk file itself,
// appending only each flush's delta, so there is no second source of truth and no WDB
// changes. Indexed columns come from sort.csv, the same file EOD uses to place `p#.
//
// Load order: this file loads before the stock idb.q, so the wiring is deferred to
// .proc.initlist (runs last) to wrap intradayreload/rollover rather than be
// clobbered by them.

\d .idb

memattrpart:`;                                                                 // partition the cache below is built for
memcols:()!();                                                                 // table ! (column ! heap `g# vector); registry AND cache

// Indexed columns for table t, mirroring .sort.sorttab's precedence: a table's own
// sort.csv rows win if it has ANY, else the `default rows
memattrcols:{[t]
    if[0=count .sort.params;@[.sort.getsortcsv;.sort.defaultfile;{.lg.e[`idb.memattr;"could not read sort.csv (",x,"); no in-memory attributes"]}]];
    t:$[t in .sort.params`tabname;t;`default];
    exec distinct column from .sort.params where tabname=t, att in `p`g
 };

// Rebuild the registry with one EMPTY `g#-attributed placeholder per indexed column.
resetmemattr:{[cp]
    memcols::.Q.pt!{[t] c:memattrcols t; c!count[c]#enlist `g#()} each .Q.pt;
    memattrpart::cp;
    .Q.gc[];                                                                   // or yesterday's in-memory data stays resident
    .lg.o[`idb.memattr;"live partition now ",string[cp],"; indexing ","; " sv {[t] string[t],": ",", " sv string key memcols t} each key memcols];
 };

// Bring each indexed column level with disk and splice it into the mapped slot.
buildmemattr:{[t;T]
    if[not t in key memcols; :T];                                              // if table appeared since the last reset return early
    {[t;T;c]
        d:T c;                                                                 // snapshot mapping: count was fixed at `get pdir` i.e. any additional writes to the end of the file are invisible
        if[(count memcols[t;c])>count d;                                       // column on disk shrank i.e. the partition was rebuilt under us
            .lg.w[`idb.memattr;"disk shrank for ",string[t],".",string[c],"; rebuilding"];
            .[`.idb.memcols;(t;c);:;`g#()]];                                   // wipe out the in-memory columns so we can start over
        n:count memcols[t;c];                                                  // current in-memory count
        if[n<count d; .[`.idb.memcols;(t;c);,;n _ d]];                         // append the new rows (`g# maintained incrementally); NOTE n _ d will _only read the new rows from disk_, not the full file
        @[T;c;:;$[count memcols[t;c];memcols[t;c];`g#0#d]]                     // splice in the in-memory columns with attrs; `g#0#d keeps an empty new day correctly typed
     }[t]/[T;(key memcols t) inter cols T]
 };

// Re-map only the live partition's .Q.pm slot for every partitioned table,
// leaving all historical slots mapped/untouched. A .Q.pm slot is exactly
// `get <partition-splay-dir>`; we splice a fresh map of just the live partition
// back in with a dict-merge (nested-index assign .Q.pm[t][k]:v is `nyi).
refreshliveslot:{
    cp:currentpartition;
    if[usememattr and not cp~memattrpart; resetmemattr cp];                    // new day -> start the cache over
    {[cp;t]
        ks:key .Q.pm t;
        idx:where cp=last each ks;                                             // the live (dir;partition) key
        if[0=count idx;:()];                                                   // no live-partition slot for this table yet
        lk:ks first idx;
        pdir:.Q.dd[.Q.dd[lk 0;`$string lk 1];t];                               // <dir>/<partition>/<table> splay
        // NOTE this is unguarded: `get` on a ragged splay (during a WDB write) throws 'length. It will still correctly reload on the next try, but worth fixing at some point.
        .Q.pm[t]:(.Q.pm t),(enlist lk)!enlist T:get pdir;                      // Refresh the live partition slot. Must be its own assignment: it drops the old slot's reference to memcols, keeping the append below in-place
        if[not usememattr;:()];
        .Q.pm[t]:(.Q.pm t),(enlist lk)!enlist buildmemattr[t;T];               // Splice in the in-memory columns with attrs
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
        .Q.MAP[]];                                                             // forced / first map / coverage gap -> full remap
    refreshliveslot[];                                                         // runs after .Q.MAP[] too: it rebuilds every slot
 };                                                                            // from disk, dropping any overlay

// Applied post-load via .proc.initlist, once idb.q has defined intradayreload.
applymapmode:{[]
    if[not usemapping;
        .lg.o[`idb.mode;"IDB read mode A (deferred): no .Q.MAP, selects re-map per query"];
        if[usememattr;
            .lg.w[`idb.memattr;"usememattr ignored: deferred mode has no .Q.pm to overlay"];
            usememattr::0b];
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
