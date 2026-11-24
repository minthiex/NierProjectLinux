#!/bin/sh
# key <TAB> value <TAB> percent (optional)
export LC_ALL=C
idle=$(top -bn1 | awk '/Cpu\(s\)/{for(i=1;i<=NF;i++) if($i=="id,"||$i=="id") print $(i-1)}')
cpu=$(awk -v i="${idle:-100}" 'BEGIN{printf "%.0f", 100-i}')
printf 'CPU\t%s%%\t%s\n' "$cpu" "$cpu"
free -m | awk '/Mem:/{printf "MEMORY\t%d / %d MiB\t%d\n",$3,$2,$3*100/$2} /Swap:/{if($2>0) printf "SWAP\t%d / %d MiB\t%d\n",$3,$2,$3*100/$2}'
g=$(cat /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -1)
[ -n "$g" ] && printf 'GPU\t%s%%\t%s\n' "$g" "$g"
sensors 2>/dev/null | awk '
  /^Tctl:|^Package id 0:|^CPU:/ && !c {gsub(/[+°C]/,"",$2); printf "CPU TEMP\t%s C\t%d\n",$2,$2; c=1}
  /^edge:/ && !g {gsub(/[+°C]/,"",$2); printf "GPU TEMP\t%s C\t%d\n",$2,$2; g=1}'
printf 'LOAD AVERAGE\t%s\n' "$(cut -d' ' -f1-3 /proc/loadavg)"
printf 'UPTIME\t%s\n' "$(uptime -p | sed 's/^up //')"
