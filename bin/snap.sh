#!/usr/bin/env bash

# Tiny snapshot helper for CLI smoke tests.
# Set GEN=1 to (re)write snapshots instead of verifying them.

if [ "$#" -lt 2 ]; then
  echo "Usage: snap.sh <out> <command> [args...]" >&2
  exit 1
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

out="$1"
shift

{
  printf '############################################################################\n'
  printf '# snap.sh %s\n' "$*"
  printf '############################################################################\n\n'
} > "$tmp"

"$@" >> "$tmp" 2>&1
printf '\n' >> "$tmp"

if [ "${GEN-}" = "1" ] || [ ! -f "$out" ]; then
  mv "$tmp" "$out"
  printf 'snap created: %s\n' "$out"
  exit 0
fi

if ! diff -u "$out" "$tmp" > /dev/null; then
  echo "snap differs: $out" >&2
  diff -u "$out" "$tmp" || true
  exit 1
fi
