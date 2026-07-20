// =============================================================================
// bench/timethr.q - print two tradetime thresholds (space-separated) at fixed row
// percentiles, computed server-side on the RDB. matrix.sh reads these to build the
// filter_time_lg / filter_time_sm queries as static timestamp literals:
//   T_LG = 95.00 pctile -> `where tradetime>=T_LG` returns ~top 5%    (large)
//   T_SM = 99.99 pctile -> `where tradetime>=T_SM` returns ~top 0.01% (small)
// Percentiles (not the analytic uniform bounds) so it stays correct for any feed.
// The rdb port is derived from $KDBBASEPORT (default 7100) + 4, per bench/process.csv.
// =============================================================================
bp:$[count s:getenv`KDBBASEPORT; "J"$s; 7100];
h:hopen `$":localhost:",string[bp+4],":admin:admin";
r:h"s:asc trade`tradetime; n:count s; s@(floor 0.95*n;floor 0.9999*n)";
-1 " " sv string r;
exit 0
