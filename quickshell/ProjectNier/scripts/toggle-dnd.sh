#!/bin/sh
. "$(dirname "$0")/lib.sh"
if [ -f "$D/dnd" ]; then rm -f "$D/dnd"; else : > "$D/dnd"; fi
