#!/usr/bin/env bash

# Tiny snapshot helper for CLI smoke tests.
# Set GEN=1 to (re)write snapshots instead of verifying them.

if [ "$#" -lt 2 ]; then
  echo "Usage: snap.sh <out> <command> [args...]" >&2
  exit 1
fi

expect_fail=0
if [ "$1" = "--fail" ]; then
  expect_fail=1
  shift
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

if "$@" >> "$tmp" 2>&1; then
  status=0
else
  status=$?
fi

if [ "$expect_fail" -eq 1 ] && [ "$status" -eq 0 ]; then
  echo "snap command unexpectedly succeeded: $*" >&2
  exit 1
fi

if [ "$expect_fail" -eq 0 ] && [ "$status" -ne 0 ]; then
  echo "snap command failed: $*" >&2
  exit 1
fi

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
