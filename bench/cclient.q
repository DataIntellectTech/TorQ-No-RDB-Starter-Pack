// =============================================================================
// bench/cclient.q - one benchmark client process. Connects to a single target,
// runs its query set `reps` times (blocking/sync), prints total ms. Used by
// bench/concurrency.sh to get TRUE parallelism (separate OS processes), since a
// single q process can neither fire IPC in parallel nor use -s threads for IPC.
// Args: -port P -reps N -query "q1" [-query "q2" ...]  [-st]
//   default     : client loop, sync calls incl. result transfer (throughput bench)
//   -st present : SERVER-SIDE timing via \t:reps on the target (no result transfer),
//                 matching the latency-matrix methodology.
// =============================================================================
p:.Q.opt .z.x;
port:"J"$first p`port;
reps:"J"$first p`reps;
qs:p`query;                                     // one or more query strings
h:hopen (`$":localhost:",string[port],":admin:admin"; 8000);
{h x} each qs;                                  // warm
tot:$[`st in key p;
    `long$ sum {[h;r;q] h ("\\t:",string[r]," ",q)}[h;reps] each qs;   // server-side ms (no transfer)
    {[h;r;qs] t0:.z.p; do[r; {h x} each qs]; `long$(.z.p-t0)%1000000}[h;reps;qs]];  // client loop incl. transfer
-1 "RESULT ",string[port]," ",string[tot]," ",string reps;
exit 0
