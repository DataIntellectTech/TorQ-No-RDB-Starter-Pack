\d .wdb
// ONE directory: the WDB writes today's partition straight into the database the
// readers serve. savedir == hdbdir, so there is nothing to move at EOD - the
// partition is already home and EOD only has to sort it (in place, via a hidden
// staging dir). This is what lets live and history be one DB served by N
// identical readers, with no gateway.
savedir:hdbdir:hsym `$getenv[`KDBDB]
sortworkertypes:()                                                             // WDB doesn't need to connect to sortworkers

// --- continuous flush (the no-RDB differentiator) ---
immediate:1b                                                                   // write down on every timer tick (ignores maxrows threshold)
settimer:0D00:00:01                                                            // flush-check timer interval -> ~1s continuous flush to disk

\d .servers
// no hdb: one dir means the IDBs serve history too, and the IDBs register
// themselves with the WDB on init so they don't need listing here either.
// no rdb: this WDB runs mode:`save, so it delegates EOD to the sort proc via
// informsortandreload and never calls doreload - the sort proc is what reaches
// the RDB to clear it (see appconfig/settings/sort.q). Would be needed again if
// this WDB were ever switched to mode:`saveandsort.
CONNECTIONS:`segmentedtickerplant`sort
