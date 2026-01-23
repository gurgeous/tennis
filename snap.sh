#!/usr/bin/env bash

if [ "$#" -lt 2 ]; then
  echo "Usage: snap.sh <out> <command> [args...]" >&2
  exit 1
fi

banner() {
  printf '\e[1;37;42m[%s] %-72s\e[0m\n' `date '+%H:%M:%S'` "$1"
}
fatal() {
  printf '\e[1;37;41m[%s] %-72s\e[0m\n' `date '+%H:%M:%S'` "$1"
  exit 1
}

# this whole thing is generic except for this line
export CLICOLOR_FORCE=1

# run cmd
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
out="$1"
shift

echo '#' > "$tmp"
echo '# snap.sh' "$@" >> "$tmp"
echo '#' >> "$tmp"
echo >> "$tmp"
"$@" >> "$tmp" 2>&1
echo >> "$tmp"

# update if necessary
if [ "$UPDATE" = "1" ] || [ ! -f "$out" ]; then
  mv "$tmp" "$out"
  banner "snap created: $out"
  exit 0
fi

# Compare with existing snapshot
if ! diff -u "$out" "$tmp" > /dev/null; then
  fatal "snap differs: $out"
fi

echo "✓ snap verified: $out"
