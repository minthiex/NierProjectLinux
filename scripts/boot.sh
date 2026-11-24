#!/bin/sh
export LC_ALL=C
systemd-analyze 2>/dev/null | head -1 | sed 's/^Startup finished in //' | awk -F' = ' '{print "TOTAL\t" $2; print "PHASES\t" $1}'
printf '\t\n'
printf 'SLOWEST UNITS\t\n'
systemd-analyze blame 2>/dev/null | grep -v '\.device' | head -10 | awk '{t=$1; $1=""; sub(/^ +/,""); printf "%s\t%s\n",$0,t}'
