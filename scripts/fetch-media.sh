#!/bin/sh
# usage: fetch-media.sh <url> <output file>   (the Matrix access token comes in the TOKEN environment variable)
url="$1"; out="$2"
mkdir -p "$(dirname "$out")"
# already cached: mark it as used (the disk is mounted noatime, so the cache is pruned by mtime, see MatrixClient.qml)
if [ -s "$out" ]; then touch "$out"; exit 0; fi
tmp="$out.part.$$"
# the header goes in on stdin: on the command line the token would show up in `ps` for the whole download
if printf 'Authorization: Bearer %s\n' "$TOKEN" | curl -sS --fail --max-time 180 -H @- -o "$tmp" "$url"; then
  mv "$tmp" "$out"
else
  rm -f "$tmp"; exit 1
fi
