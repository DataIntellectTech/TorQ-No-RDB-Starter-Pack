\d .wdb
savedir:hdbdir:hsym `$getenv[`KDBDB]                                           // ONE directory
tickerplanttypes:sorttypes:()                                                  // sort doesn't need these connections
sortworkertypes:()                                                             // no sortworkers: this pack ships none, and the
                                                                               // no-RDB rollover sorts the staging copy with a
                                                                               // plain `each` (see code/wdb/rollover.q), so the
                                                                               // peach handles .z.pd would build from these are
                                                                               // never used. Add a sortworker proctype to
                                                                               // process.csv and set this back to `sortworker
                                                                               // to parallelise the EOD sort across workers.

\d .servers
CONNECTIONS:`rdb                                                               // no hdb (one dir), no gateway (gateway-free),
                                                                               // no sortworker (see above)

