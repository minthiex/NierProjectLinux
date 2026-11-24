#!/bin/sh
export LC_ALL=C
printf 'CPU\t%s\n' "$(lscpu | awk -F: '/Model name/{gsub(/^ +/,"",$2); print $2; exit}')"
printf 'CORES / THREADS\t%s / %s\n' "$(lscpu | awk -F: '/^Core\(s\) per socket/{gsub(/ /,"",$2); print $2}')" "$(nproc)"
printf 'GPU\t%s\n' "$(lspci 2>/dev/null | grep -iE 'vga|3d' | head -1 | sed 's/^[^ ]* [^:]*: //; s/ (rev.*//')"
printf 'MEMORY\t%s\n' "$(free -h | awk '/Mem:/{print $2}')"
printf 'BOARD\t%s %s\n' "$(cat /sys/class/dmi/id/board_vendor 2>/dev/null)" "$(cat /sys/class/dmi/id/board_name 2>/dev/null)"
printf 'BIOS\t%s\n' "$(cat /sys/class/dmi/id/bios_version 2>/dev/null)"
printf 'KERNEL\t%s\n' "$(uname -r)"
printf 'OS\t%s\n' "$(. /etc/os-release; echo $PRETTY_NAME)"
