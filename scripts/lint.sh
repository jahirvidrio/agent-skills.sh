#!/bin/sh
# scripts/lint.sh - POSIX-style lint + test gate for agent-skills.sh.
#
# Runs (in order):
#   1. scripts/test.sh  bats test suite (skipped if bats is not installed)
#   2. dash -n           syntax check (POSIX-strict shell)
#   3. shellcheck -s sh  static analysis in POSIX mode
#   4. checkbashisms     optional: skipped if not installed
#
# Exits 0 if all checks pass.

set -eu

script_dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$script_dir/.." && pwd)
target="$root/agent-skills.sh"

[ -f "$target" ] || {
    printf 'error: %s not found\n' "$target" >&2
    exit 1
}

command -v dash >/dev/null 2>&1 || {
    printf 'error: dash is required for syntax check\n' >&2
    exit 1
}
command -v shellcheck >/dev/null 2>&1 || {
    printf 'error: shellcheck is required for lint\n' >&2
    exit 1
}

if command -v bats >/dev/null 2>&1; then
    printf '>> scripts/test.sh\n'
    if ! "$script_dir/test.sh"; then
        printf 'error: tests failed\n' >&2
        exit 1
    fi
else
    printf '>> bats not installed, skipping tests (brew install bats-core)\n'
fi

printf '>> dash -n %s\n' "$target"
dash -n "$target"

printf '>> shellcheck -s sh %s\n' "$target"
shellcheck -s sh "$target"

if command -v checkbashisms >/dev/null 2>&1; then
    printf '>> checkbashisms %s\n' "$target"
    if ! checkbashisms "$target"; then
        printf 'error: checkbashisms reported bashisms; review before committing\n' >&2
        exit 1
    fi
else
    printf '>> checkbashisms: not installed, skipping (install devscripts to enable)\n'
fi

printf 'OK\n'