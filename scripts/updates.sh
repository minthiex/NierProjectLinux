#!/bin/sh
export LC_ALL=C
out=$(checkupdates 2>/dev/null)
n=$(printf '%s' "$out" | grep -c .)
printf 'UPDATES AVAILABLE\t%s\n' "$n"
printf '%s\n' "$out" | grep . | head -40 | awk '{printf "%s\t%s -> %s\n",$1,$2,$4}'
