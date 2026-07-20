// EOD rollover for the no-RDB pack. Installs on BOTH wdb1 and sort1 (sort1 runs
// with -parentproctype wdb): the wdb runs mode:`save and delegates the sort via
// informsortandreload, so sort1 is where this actually executes (the wdb only runs
// it in the no-sort-proc fallback path).
//
// Stock .wdb.endofdaysortdate sorts the live partition IN PLACE then moves it to a
// separate hdb dir. Neither works here: there's one dir (nothing to move), and
// we're gateway-free, so an in-place sort would rewrite column files under live
// readers. (The stock gateway hold wouldn't have helped anyway - it fires inside
// doreload, i.e. AFTER the sort.) So we sort a hidden copy and swap it in with two
// atomic renames - see nordbsortdate for the steps. Readers only ever see the
// microsecond gap between the two renames; mapped readers keep serving across it
// (mmap survives the rename), deferred readers throw until they reload - loudly,
// which is the failure mode we want, and rare given how small the gap is.
//
// Cost: one extra full copy of the day's partition at EOD, transiently ~2x its
// disk. That's the price of a zero-downtime, gateway-free rollover.
//
// Load order: defined under our own name and swapped in from .proc.initlist (runs
// last), because the stock wdb.q loads after this file and would otherwise clobber
// a direct redefinition. Same pattern as code/idb/.

\d .wdb

// "/db/2026.07.14"
partpath:{[dir;pt] .os.pth -1 _ string .Q.par[dir;pt;`]};
// "/db/2026.07.14" + suffix -> "/db/.2026.07.14<sfx>". The leading dot matters:
// kdb+ ignores names that don't start with a digit in a partitioned root, so the
// staging/trash dirs stay invisible to readers. (A digit-first name would parse as
// a partition value -> 'part, taking the DB down - so never "tidy" the dot away.)
dotpath:{[dir;pt;sfx] p:partpath[dir;pt]; i:1+last where "/"=p; (i#p),".",(i _ p),sfx};

// Sweep superseded copies left by PREVIOUS rollovers. Deliberately done here, at
// the start of the next one, rather than at the end of the last: mapped readers
// keep the old inodes alive until they reload, and .<pt>.old is also the only
// rollback if a sort ever went wrong. Retention is therefore ~one day.
sweeptrash:{[dir]
    k:key dir;                                                                 // NB assign before use: q is
    t:k where (string k) like ".*.old";                                        // right-to-left, so k:.. inline
    if[0=count t; :()];                                                        // would be read before assignment
    {[dir;n] p:.os.pth[dir],"/",string n;
        .lg.o[`nordb.rollover;"sweeping superseded partition ",p];
        @[.os.deldir;p;{.lg.e[`nordb.rollover;"failed to sweep: ",x]}] }[dir] each t;
 };

// The rollover: sort today's partition into place with no visible in-between.
// Copy <pt> to a hidden .<pt>.stage, sort the copy, then swap it in with two
// atomic renames (<pt> -> .<pt>.old, then .<pt>.stage -> <pt>); the only visible
// moment is the microsecond gap between them (see file header). A stale .stage is
// cleared first (mv would otherwise nest it inside itself) and prior rollovers'
// .old dirs are swept.
nordbsortdate:{[dir;pt;tablist;hdbsettings]
    src:partpath[dir;pt];
    stg:dotpath[dir;pt;".stage"];                                              // hidden staging copy
    old:dotpath[dir;pt;".old"];                                                // hidden superseded copy
    if[.os.Fex hsym `$stg; .lg.o[`nordb.rollover;"removing stale ",stg]; .os.deldir stg];
    sweeptrash[dir];                                                           // drop prior rollovers' .old dirs

    .lg.o[`nordb.rollover;"staging ",src," -> ",stg];
    system"cp -a \"",src,"\" \"",stg,"\"";                                     // plain cp -a (no .os.cpy); Linux

    .lg.o[`nordb.rollover;"sorting staged partition (readers still on ",src,")"];
    reloadsymfile[.Q.dd[hdbsettings `hdbdir;`sym]];
    {[stg;t] .sort.sorttab (t; `$":",stg,"/",string t); if[gc;.gc.run[]]}[stg] each tablist; // stock sort on the staging dir

    .lg.o[`nordb.rollover;"swapping sorted partition into place"];
    .os.ren[src;old];                                                          // GAP OPENS
    .os.ren[stg;src];                                                          // GAP CLOSES
    .lg.o[`nordb.rollover;"rollover complete; superseded copy left at ",old];

    .save.postreplay[hdbsettings[`hdbdir];pt];                                 // unchanged EOD tail (post-replay hook)
    if[permitreload; doreload[pt]];                                            // then TorQ's own reload notify
 };

// Swap our rollover in once the stock wdb.q has finished loading.
applyrollover:{[]
    .lg.o[`nordb.rollover;"installing no-RDB EOD rollover (staged sort + atomic swap)"];
    endofdaysortdate::nordbsortdate;
 };

\d .
.proc.addinitlist".wdb.applyrollover[]";                                       // install after code/processes/wdb.q loads
