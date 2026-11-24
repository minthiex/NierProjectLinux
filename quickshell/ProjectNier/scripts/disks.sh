#!/bin/sh
export LC_ALL=C
df -hT -x tmpfs -x devtmpfs -x efivarfs -x squashfs -x overlay | sed 1d | awk '!seen[$1]++ {p=$6; gsub(/%/,"",p); printf "%s\t%s / %s (%s)\t%s\n",$7,$4,$3,$2,p}'
