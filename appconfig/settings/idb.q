\d .idb

// read mode flag: 1b = mapped (.Q.MAP + live-slot refresh, default), 0b = deferred.
// Override per-process, e.g. -.idb.usemapping 0 on the command line.
usemapping:@[value;`usemapping;1b];

// Re-enable proctype-directory code loading so .proc.reloadcode picks up our
// read-mode behaviour from $KDBAPPCODE/idb/ (i.e. code/idb/mapping.q). Core
// config/settings/idb.q sets this 0b because stock TorQ ships no code/idb dir;
// this appconfig layer loads AFTER core, so setting it back to 1b here is what
// activates the overlay. (The WDB needs no such flip - wdb.q keeps it 1b.)
\d .proc
loadprocesscode:1b
