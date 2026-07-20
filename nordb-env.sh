#!/bin/bash
# Layered dev env for TorQ-No-RDB-Starter-Pack:
#   core code/config  -> the TorQ checkout
#   app overlay        -> this pack
#   data               -> ./data under the pack
# Override torq.sh's default by: export SETENV=<this file>

export TORQHOME=/home/mdoherty/projects/TorQ                       # TorQ core (torq.q, code/, config/)
export TORQAPPHOME=/home/mdoherty/projects/TorQ-No-RDB-Starter-Pack # this pack (app overlay)
export TORQDATAHOME=${TORQAPPHOME}/data                            # writable data root

# core
export KDBCONFIG=${TORQHOME}/config
export KDBCODE=${TORQHOME}/code
export KDBLIB=${TORQHOME}/lib
export KDBHTML=${TORQHOME}/html
export KDBTESTS=${TORQHOME}/tests

# app overlay
export KDBAPPCONFIG=${TORQAPPHOME}/appconfig
export KDBAPPCODE=${TORQAPPHOME}/code

# data / logs
export KDBLOG=${TORQDATAHOME}/logs
export KDBTPLOG=${TORQDATAHOME}/tplogs

# --- the database: ONE directory --------------------------------------------
# No par.txt and no separate wdb/hdb areas. The WDB writes today's partition
# straight into the database the readers serve, and EOD sorts it in place, so
# there is no move and live+history are one date-partitioned DB served by N
# identical readers. savedir == hdbdir == KDBDB (see appconfig/settings/wdb.q).
#
# KDBHDB/KDBWDB are kept as aliases because TorQ core and the stock settings
# read them by name; here they deliberately resolve to the same directory.
export KDBDB=${TORQDATAHOME}/db
export KDBHDB=${KDBDB}
export KDBWDB=${KDBDB}

export KDBBASEPORT=7100
export TORQPROCESSES=${KDBAPPCONFIG}/process.csv

export RLWRAP="rlwrap"
export QCON="qcon"
export QCMD="q"

mkdir -p ${KDBLOG} ${KDBDB} ${KDBTPLOG}
