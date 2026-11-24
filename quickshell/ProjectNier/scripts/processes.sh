#!/bin/sh
export LC_ALL=C
ps -eo pid,pcpu,pmem,comm --sort=-pcpu | sed 1d | head -16 | awk '{p=$2; if(p>100)p=100; printf "%s (%s)\tCPU %s%%  MEM %s%%\t%d\n",$4,$1,$2,$3,p}'
