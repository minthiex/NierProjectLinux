#!/bin/sh
. "$(dirname "$0")/lib.sh"
case "$1" in
  add)    printf '[ ] %s\n' "$2" >> "$D/todo.txt" ;;
  toggle) sed -i "$2s/^\[ \] /[?] /; $2s/^\[x\] /[ ] /; $2s/^\[?\] /[x] /" "$D/todo.txt"
          # log a completion
          l=$(sed -n "$2p" "$D/todo.txt"); case "$l" in "[x] "*) printf '%s\tmission\t%s\n' "$(date '+%F %H:%M')" "${l#??? }" >> "$D/done.log";; esac ;;
  clear)  sed -i '/^\[x\] /d' "$D/todo.txt" ;;
  add-daily) printf '[ ] %s\n' "$2" >> "$D/daily-$(date +%F).txt" ;;
  toggle-daily) f="$D/daily-$(date +%F).txt"; sed -i "$2s/^\[ \] /[?] /; $2s/^\[x\] /[ ] /; $2s/^\[?\] /[x] /" "$f" ;;
  memo)   printf '%s\t%s\n' "$(date '+%m-%d %H:%M')" "$2" >> "$D/memo.txt" ;;
  contact) printf '%s\t%s\n' "$2" "" >> "$D/contacts.txt" ;;
esac
