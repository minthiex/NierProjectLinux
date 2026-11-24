#!/bin/sh
export LC_ALL=C
journalctl -b -p warning -n 22 --no-pager -o short 2>/dev/null | grep -v '^-- ' | tac | awk '{t=substr($3,1,5); $1=$2=$3=$4=""; sub(/^ +/,""); printf "%s\t%s\n", t, $0}'
