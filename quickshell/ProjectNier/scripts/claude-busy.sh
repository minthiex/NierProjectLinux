#!/bin/bash
# usage: claude-busy.sh on|off   (run by Claude Code hooks: UserPromptSubmit → on, Stop / SessionEnd → off)
# Marks the Claude process this hook belongs to as busy, so the shell won't close its window by accident.
dir="${XDG_RUNTIME_DIR:-/tmp}/projectnier-busy"
mkdir -p "$dir"
p=$$
while [ -n "$p" ] && [ "$p" -gt 1 ]; do
  [ "$(cat /proc/$p/comm 2>/dev/null)" = claude ] && break
  p=$(ps -o ppid= -p "$p" | tr -d ' ')
done
[ -z "$p" ] || [ "$p" -le 1 ] && exit 0
if [ "$1" = on ]; then touch "$dir/$p"; else rm -f "$dir/$p"; fi
# drop marks of Claude processes that are gone
for f in "$dir"/*; do [ -e "$f" ] || continue; [ "$(cat /proc/${f##*/}/comm 2>/dev/null)" = claude ] || rm -f "$f"; done
exit 0
