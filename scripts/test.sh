#!/bin/sh
# scripts/test.sh - run bats tests for agent-skills.sh.
#
# Exits 0 if all tests pass; non-zero otherwise.
#
# Usage:
#   scripts/test.sh              # run all tests
#   scripts/test.sh tests/foo.bats  # run a single file

set -eu

script_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$script_dir/.." && pwd)
tests_dir="$root/tests"

command -v bats >/dev/null 2>&1 || {
    printf 'error: bats is required (brew install bats-core)\n' >&2
    exit 1
}

if [ ! -d "$tests_dir" ]; then
    printf 'error: %s not found\n' "$tests_dir" >&2
    exit 1
fi

printf '>> bats %s\n' "${*:-"$tests_dir"}"
if [ "$#" -eq 0 ]; then
    bats "$tests_dir"
else
    bats "$@"
fi