#!/bin/sh
export LC_ALL=C
printf 'FAILED UNITS\t%s\n' "$(systemctl --failed --no-legend --plain 2>/dev/null | grep -c .)"
printf 'RUNNING SERVICES\t%s\n' "$(systemctl list-units --type=service --state=running --no-legend --plain | grep -c .)"
printf '\t\n'
systemctl list-units --type=service --state=running --no-legend --plain | head -16 | awk '{u=$1; sub(/\.service$/,"",u); $1=$2=$3=$4=""; sub(/^ +/,""); printf "%s\t%s\n", u, $0}'
