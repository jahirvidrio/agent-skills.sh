#!/usr/bin/env bash
# tests/lib/test_helper.bash - shared setup for agent-skills.sh bats tests.
#
# Each test runs in its own subshell with $BATS_TEST_TMPDIR unique to the
# test. Helpers below create a fake `git` binary that succeeds for any
# invocation, so the script's parser/validation paths can be exercised
# without touching the network.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET="$ROOT_DIR/agent-skills.sh"

# Hermetic HOME so each test gets its own cache root under BATS_TEST_TMPDIR.
# The script computes CACHE_ROOT from $HOME; pointing HOME here means
# parser tests can assert against a predictable cache_root() without
# polluting or being polluted by the real ~/.cache/agent-skills tree.
export HOME="$BATS_TEST_TMPDIR/home"
mkdir -p "$HOME"

# make_fake_git <dir>
# Writes a fake `git` binary into <dir>/git. It supports two modes:
#   - `clone --depth=1 <url> <dest>`: copies the contents of <url>
#     (treating file:// as a local path) into <dest>. Lets E2E tests
#     exercise clone_or_update without hitting the network.
#   - anything else (pull, status, -C ...): exits 0 silently.
# Additionally, exporting FAKE_GIT_FAIL=1 makes any invocation exit 1,
# used to test the failure path of clone_or_update.
make_fake_git() {
    _dir=$1
    mkdir -p "$_dir"
    cat > "$_dir/git" <<'EOF'
#!/bin/sh
# Append-only call log under BATS_TEST_TMPDIR; lets tests assert
# which subcommands were invoked.
if [ -n "${GIT_CALL_LOG:-}" ]; then
    printf '%s\n' "$*" >> "$GIT_CALL_LOG"
fi

if [ "${FAKE_GIT_FAIL:-0}" = "1" ]; then
    printf 'fake-git: forced failure\n' >&2
    exit 1
fi

# Branch: `git [-C <dir>] remote get-url origin`.
# Filter -C and its arg; remaining argv is `remote get-url origin`.
case $* in
    *"remote"*"get-url"*"origin"*)
        if [ -n "${FAKE_GIT_ORIGIN:-}" ]; then
            printf '%s\n' "$FAKE_GIT_ORIGIN"
            exit 0
        fi
        printf 'fake-git: no origin configured\n' >&2
        exit 1
        ;;
esac

if [ "$1" = "clone" ]; then
    shift
    _fg_url=""
    _fg_dest=""
    while [ $# -gt 0 ]; do
        case $1 in
            --*) ;;
            *)
                if [ -z "$_fg_url" ]; then _fg_url=$1; else _fg_dest=$1; fi
                ;;
        esac
        shift
    done
    if [ -n "$_fg_url" ] && [ -n "$_fg_dest" ]; then
        _fg_src=${_fg_url#file://}
        mkdir -p "$_fg_dest"
        if [ -d "$_fg_src" ]; then
            for _fg_entry in "$_fg_src"/* "$_fg_src"/.[!.]*; do
                [ -e "$_fg_entry" ] || continue
                cp -R "$_fg_entry" "$_fg_dest/"
            done
        fi
    fi
    exit 0
fi

exit 0
EOF
    chmod +x "$_dir/git"
}

# setup_fake_git
# Creates $BATS_TEST_TMPDIR/fakebin/git and prepends it to PATH so the
# script picks up our stub instead of the real git.
setup_fake_git() {
    _bin=$BATS_TEST_TMPDIR/fakebin
    make_fake_git "$_bin"
    export PATH="$_bin:$PATH"
    export GIT_CALL_LOG="$BATS_TEST_TMPDIR/git-calls.log"
    : > "$GIT_CALL_LOG"
}

# cache_root
# Echoes the cache root the script will compute, given that HOME has
# been redirected to $BATS_TEST_TMPDIR/home.
cache_root() {
    printf '%s/.cache/agent-skills' "$HOME"
}

# prepopulate_cache <cache_key> <fixture_path>
# Mirrors what `git clone` would leave behind: copies the contents of
# <fixture_path> into the cache dir for <cache_key> and creates an
# empty .git/ marker so the script takes the pull branch on entry.
# Used by tests that need find_skill_dir to see a populated tree
# without exercising the clone code path.
prepopulate_cache() {
    _ck_key=$1
    _ck_fixture=$2
    _ck_dir=$(cache_root)"/$_ck_key"
    mkdir -p "$_ck_dir/.git"
    if [ -d "$_ck_fixture" ]; then
        for _ck_entry in "$_ck_fixture"/* "$_ck_fixture"/.[!.]*; do
            [ -e "$_ck_entry" ] || continue
            cp -R "$_ck_entry" "$_ck_dir/"
        done
    fi
}

# fixture_path <name>
# Returns the absolute path to a fixture directory by name.
fixture_path() {
    printf '%s/fixtures/%s' "$SCRIPT_DIR" "$1"
}

# run_script <args...>
# Runs the target script with the given args. Stdout and stderr are
# captured together into $output; exit code is in $status.
run_script() {
    run "$TARGET" "$@"
}

# run_script_with_fake_git <args...>
# Combines setup_fake_git + run_script.
run_script_with_fake_git() {
    setup_fake_git
    run_script "$@"
}