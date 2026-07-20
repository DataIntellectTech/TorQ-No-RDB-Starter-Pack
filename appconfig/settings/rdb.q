// The RDB is NOT part of the no-RDB architecture - it is the benchmark control,
// i.e. the thing this pack argues against. It is here so the read-latency matrix
// has a real in-memory RDB to compare the on-disk IDBs against.
//
// No hdbdir: with reloadenabled:1b, .rdb.endofday escapes early - before either of
// its two uses of hdbdir (writedown, .save.postreplay) - so the RDB never writes
// down. The sort proc clears it at EOD by calling its `reload`.

\d .rdb
reloadenabled:1b                                                               // if true, the RDB will not save when .u.end is called but
                                                                               // will clear its data using reload function (called by the sort proc)

connectonstart:1b                                                              // rdb connects and subscribes to tickerplant on startup
tickerplanttypes:`segmentedtickerplant
gatewaytypes:`none
replaylog:1b

hdbtypes:()                                                                    //connection to HDB not needed

subfiltered:0b
// path to rdbsub{i}.csv
subcsv:hsym first `.proc.getconfigfile["rdbsub/rdbsub",(3_string .proc`procname),".csv"]
