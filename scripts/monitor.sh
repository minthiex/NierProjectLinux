#!/bin/sh
# key <TAB> value <TAB> percent (optional)
export LC_ALL=C
# CPU use since the last refresh, from /proc/stat (state in the runtime dir); the first look takes a 0.3 s sample
st="${XDG_RUNTIME_DIR:-/tmp}/projectnier-cpu"
stat() { awk '/^cpu /{t=0; for(i=2;i<=NF;i++) t+=$i; print t, $5+$6}' /proc/stat; }
cur=$(stat); prev=$(cat "$st" 2>/dev/null)
if [ -z "$prev" ]; then prev=$cur; sleep 0.3; cur=$(stat); fi
printf '%s\n' "$cur" > "$st"
cpu=$(echo "$prev $cur" | awk '{dt=$3-$1; di=$4-$2; if (dt<=0) print 0; else printf "%.0f", 100*(dt-di)/dt}')
printf 'CPU\t%s%%\t%s\n' "$cpu" "$cpu"
free -m | awk '/Mem:/{printf "MEMORY\t%d / %d MiB\t%d\n",$3,$2,$3*100/$2} /Swap:/{if($2>0) printf "SWAP\t%d / %d MiB\t%d\n",$3,$2,$3*100/$2}'
g=$(cat /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -1)
[ -n "$g" ] && printf 'GPU\t%s%%\t%s\n' "$g" "$g"
sensors 2>/dev/null | awk '
  /^Tctl:|^Package id 0:|^CPU:/ && !c {gsub(/[+°C]/,"",$2); printf "CPU TEMP\t%s C\t%d\n",$2,$2; c=1}
  /^edge:/ && !g {gsub(/[+°C]/,"",$2); printf "GPU TEMP\t%s C\t%d\n",$2,$2; g=1}'
printf 'LOAD AVERAGE\t%s\n' "$(cut -d' ' -f1-3 /proc/loadavg)"
printf 'UPTIME\t%s\n' "$(uptime -p | sed 's/^up //')"
