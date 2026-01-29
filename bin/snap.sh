#!/usr/bin/env bash

#
# Really simple cli snapshot test system. Run once to generate file, run a second time to verify.
# See justfile for details.
#

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

#
# run cmd
#

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
out="$1"
shift

cat >> "$tmp" << EOF
############################################################################
# snap.sh $@
############################################################################

EOF
"$@" >> "$tmp" 2>&1
echo >> "$tmp"

#
# gen if necessary
#

if [ "$GEN" = "1" ] || [ ! -f "$out" ]; then
  mv "$tmp" "$out"
  banner "snap created: $out"
  exit 0
fi

#
# verify against existing snapshot
#

if ! diff -u "$out" "$tmp" > /dev/null; then
  fatal "snap differs: $out"
fi

echo "✓ snap verified: $out"
