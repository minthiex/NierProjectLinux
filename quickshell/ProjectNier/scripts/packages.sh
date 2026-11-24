#!/bin/sh
export LC_ALL=C
printf 'INSTALLED\t%s\n' "$(pacman -Qq | wc -l)"
printf 'EXPLICIT\t%s\n' "$(pacman -Qeq | wc -l)"
printf 'FOREIGN / AUR\t%s\n' "$(pacman -Qmq | wc -l)"
printf 'ORPHANS\t%s\n' "$(pacman -Qdtq 2>/dev/null | wc -l)"
printf 'CACHE SIZE\t%s\n' "$(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)"
printf '\t\n'
printf 'RECENT INSTALLS\t\n'
grep -E '\[ALPM\] (installed|upgraded)' /var/log/pacman.log 2>/dev/null | tail -8 | tac | awk '{d=substr($1,2,10); printf "%s\t%s %s\n", d, $3, $4}'
