#!/bin/sh
# scripts/lint.sh - POSIX-style lint gate for agent-skills.sh.
#
# Runs (in order):
#   1. dash -n          syntax check (POSIX-strict shell)
#   2. shellcheck -s sh static analysis in POSIX mode
#   3. checkbashisms    optional: skipped if not installed
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