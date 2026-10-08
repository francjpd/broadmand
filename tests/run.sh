#!/usr/bin/env bash
# tests/run.sh — stable entry point for the broadmand test suite.
#
# Usage:
#   tests/run.sh            # run everything
#   tests/run.sh util popup # run a subset
#
# Uses isolated HOME and TMPDIR so the suite never touches real state.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_base="$(mktemp -d "${TMPDIR:-/tmp}/broadmand-tests.XXXXXX")"
export HOME="$_base/home"
export TMPDIR="$_base/tmp"
mkdir -p "$HOME" "$TMPDIR"
# shellcheck disable=SC2329  # invoked from the EXIT trap below
cleanup() { rm -rf "$_base"; }
trap cleanup EXIT

tests=(lint util integration broadcast-counts popup picker picker-stream)
if [ "$#" -gt 0 ]; then
  tests=("$@")
fi

overall=0
for t in "${tests[@]}"; do
  file="$TESTS_DIR/$t.test.sh"
  if [ ! -f "$file" ]; then
    printf 'run.sh: missing test %s\n' "$file" >&2
    overall=1
    continue
  fi
  printf '\n=== %s ===\n' "$t"
  if "${BASH:-bash}" "$file"; then
    :
  else
    overall=1
  fi
done

if [ "$overall" -ne 0 ]; then
  printf '\nTEST SUITE FAILED\n' >&2
  exit 1
fi
printf '\nALL TESTS PASSED\n'
