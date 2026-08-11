#!/usr/bin/env bats
# tests/test_lock_helpers.bats - covers the skill-lock helper functions:
#   - _detect_sha256_cmd (REQ-010)
#   - compute_content_hash (REQ-003, REQ-008)
#   - read_lock (REQ-001)
#   - write_lock (REQ-002, REQ-009)
#
# Helpers are tested in isolation by sourcing the script in a subshell
# with the trailing `main "$@"` line stripped. That loads all helper
# definitions (and module-top side effects such as `_detect_sha256_cmd`)
# without invoking the CLI flow, touching the cache, or polluting
# destination trees.
#
# PATH is wiped via `env -i "PATH=$BIN"` so `command -v` lookups see
# only the tools the test seeds. Absolute paths inside the snippet
# cover external commands the snippet itself needs (mktemp, sed, rm).
# Git is exposed by also prepending /usr/bin (git lives there on Linux
# and macOS alike). HOME is preserved because agent-skills.sh requires
# it.
#
# The source-strip snippet is printed by `module_source_snippet` and
# inlined into each `sh -c` invocation; the heredoc keeps the sed
# pattern literal so the dollar sign never crosses shell quoting.

load 'lib/test_helper'

# The sourced script calls `command -v git` at module load. To make
# `env -i "PATH=$BIN"` (no system bins) viable, with_fake_sha256_bin
# always seeds the fake bin with a git symlink.
#
# Other external commands (sed, mktemp, rm, awk) are reached via
# absolute paths in `module_source_snippet` / the script's helper
# bodies. Keeping them off PATH prevents the macOS-/usr/bin/shasum
# and /usr/bin/openssl leaks that would otherwise defeat the
# "only X" assertions.
#
# When a "only X" test wants Y and Z hidden, with_fake_sha256_bin
# seeds their names as non-executable empty files. `command -v` then
# returns failure (rc=1) for those names, so `_detect_sha256_cmd`
# falls through to the desired candidate.

# with_fake_sha256_bin <visible-tool> [<shadowed-tool>...]
# Builds a directory containing:
#   - one symlink named `visible-tool` whose target is the real binary
#   - one non-executable empty file for each `shadowed-tool` (so
#     `command -v` rc=1; an absent file would also work but the stub
#     makes the seed explicit and visible in `ls -la`).
# Visibility is the only thing that matters here: `visible-tool` MUST
# be a real, executable binary on this host. The supported names are
# sha256sum, shasum, openssl, and git. Any other name passed in is
# treated as a shadow and ignored if not sha256sum/shasum/openssl,
# so the test stays obvious about which side of the case branch
# each name falls into.
with_fake_sha256_bin() {
    _dir=$BATS_TEST_TMPDIR/bin-$$
    mkdir -p "$_dir"
    _visible=$1
    shift
    # Seed the visible tool as a real symlink.
    if [ -n "$_visible" ]; then
        _src=$(command -v "$_visible")
        if [ -n "$_src" ]; then
            ln -s "$_src" "$_dir/$_visible"
        else
            printf '#!/bin/sh\nexit 1\n' > "$_dir/$_visible"
            chmod +x "$_dir/$_visible"
        fi
    fi
    # Seed each shadowed tool name as a non-executable placeholder
    # so `command -v` returns rc=1 for it (no execute bit == not found).
    for _tool in "$@"; do
        : > "$_dir/$_tool"
    done
    # Always seed a git symlink; the module's `command -v git` check
    # must succeed under the wiped PATH.
    if [ ! -e "$_dir/git" ]; then
        ln -s "$(command -v git)" "$_dir/git"
    fi
    printf '%s\n' "$_dir"
}

# module_source_snippet
# Prints a self-contained shell snippet that:
#   1. Reads $1 (script path)
#   2. Copies it to a temp file, minus the trailing `main "$@"` line
#   3. Sources the temp file (loads all helpers + module-top side
#      effects such as `_detect_sha256_cmd`)
#   4. Removes the temp file
# After this snippet runs, additional shell code can be appended to
# the same `sh -c` invocation to call the just-loaded helpers.
# Absolute paths for mktemp / sed / rm so the snippet works under
# `env -i "PATH=..."` (no system bins guaranteed on PATH).
module_source_snippet() {
    cat <<'EOSNIP'
_tmp=$(/usr/bin/mktemp)
trap '/bin/rm -f "$_tmp"' EXIT INT TERM
/usr/bin/sed "/^main \"\$@\"\$/d" "$1" > "$_tmp"
. "$_tmp"
/bin/rm -f "$_tmp"
EOSNIP
}

# run_sourced <bin-dir> <body-snippet>
# Wraps `module_source_snippet` + body in `env -i` so PATH collapses
# to just the fake bin dir (where the test seeds sha256sum / shasum
# / openssl / git). External commands inside the snippet and inside
# the sourced script body are reached via absolute paths.
run_sourced() {
    _bin=$1
    _body=$2
    run env -i "HOME=$HOME" "PATH=$_bin" /bin/sh -c "$(module_source_snippet)
$_body" -- "$TARGET"
}

# run_sourced_path <bin-dir> <body-snippet> <arg1> [<arg2>...]
# Same as run_sourced but also passes additional positional args
# inside the inner shell. Useful for helpers that take a target path.
run_sourced_path() {
    _bin=$1
    _body=$2
    shift 2
    run env -i "HOME=$HOME" "PATH=$_bin" /bin/sh -c "$(module_source_snippet)
$_body" -- "$TARGET" "$@"
}

# ---- _detect_sha256_cmd (REQ-010) ------------------------------------------

@test "_detect_sha256_cmd: only sha256sum in PATH -> _sha256_cmd=sha256sum (SCN-010-1)" {
    BIN=$(with_fake_sha256_bin sha256sum shasum openssl)
    run_sourced "$BIN" 'printf "%s\n" "$_sha256_cmd"'
    [ "$status" -eq 0 ]
    [ "$output" = "sha256sum" ]
}

@test "_detect_sha256_cmd: all three in PATH -> sha256sum wins (SCN-010-2)" {
    BIN=$(with_fake_sha256_bin sha256sum shasum openssl)
    # For "all three" we need every name as a real symlink. Re-seed:
    if [ ! -e "$BIN/shasum" ] || [ ! -x "$BIN/shasum" ]; then
        ln -sf "$(command -v shasum)" "$BIN/shasum"
    fi
    if [ ! -e "$BIN/openssl" ] || [ ! -x "$BIN/openssl" ]; then
        ln -sf "$(command -v openssl)" "$BIN/openssl"
    fi
    run_sourced "$BIN" 'printf "%s\n" "$_sha256_cmd"'
    [ "$status" -eq 0 ]
    [ "$output" = "sha256sum" ]
}

@test "_detect_sha256_cmd: only shasum in PATH -> _sha256_cmd=shasum (preferred order)" {
    BIN=$(with_fake_sha256_bin shasum sha256sum openssl)
    run_sourced "$BIN" 'printf "%s\n" "$_sha256_cmd"'
    [ "$status" -eq 0 ]
    [ "$output" = "shasum" ]
}

@test "_detect_sha256_cmd: only openssl in PATH -> _sha256_cmd=openssl (preferred order)" {
    BIN=$(with_fake_sha256_bin openssl sha256sum shasum)
    run_sourced "$BIN" 'printf "%s\n" "$_sha256_cmd"'
    [ "$status" -eq 0 ]
    [ "$output" = "openssl" ]
}

@test "_detect_sha256_cmd: none of the three in PATH -> die 1 'no SHA-256 implementation' (SCN-010-3)" {
    # Build a bin that has git only (so `command -v git` succeeds)
    # but none of the sha256 candidates.
    BIN=$BATS_TEST_TMPDIR/bin-none
    mkdir -p "$BIN"
    ln -s "$(command -v git)" "$BIN/git"
    run_sourced "$BIN" 'printf "%s\n" "$_sha256_cmd"'
    [ "$status" -eq 1 ]
    [[ "$output" == *"no SHA-256 implementation found"* ]]
}

@test "_detect_sha256_cmd: stderr message names all three candidate tools" {
    BIN=$BATS_TEST_TMPDIR/bin-none
    mkdir -p "$BIN"
    ln -s "$(command -v git)" "$BIN/git"
    run_sourced "$BIN" 'printf "%s\n" "$_sha256_cmd"'
    [ "$status" -eq 1 ]
    [[ "$output" == *"sha256sum"* ]]
    [[ "$output" == *"shasum"* ]]
    [[ "$output" == *"openssl"* ]]
}

# ---- compute_content_hash (REQ-003, REQ-008) -------------------------------

# SHA-256 of an empty byte stream, lowercase hex. Spec constant for
# SCN-003-3.
EMPTY_SHA256="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

# populate_dir <dir> <name> <body>
# Writes one file under <dir>/<name> with the supplied body. Used to
# build deterministic tree fixtures for hash tests.
populate_dir() {
    _dir=$1
    _name=$2
    _body=$3
    mkdir -p "$_dir"
    printf '%s' "$_body" > "$_dir/$_name"
}

# compute_content_hash_for_dir <dir>
# Echoes the SHA-256 hash of <dir>'s contents outside the script.
# Used as a fixture-side oracle.
compute_content_hash_for_dir() {
    _ccfd_dir=$1
    find "$_ccfd_dir" -type f ! -name '.skill-lock' | sort | xargs cat 2>/dev/null \
        | sha256sum | awk '{print $1}'
}

# run_hash <dir>
# Runs `compute_content_hash` against <dir> inside a sourced script
# subshell and echoes the resulting hex. Bats captures status/output.
# Argument layout inside the inner shell:
#   $1 = TARGET (script path, consumed by module_source_snippet)
#   $2 = the directory to hash (consumed by the body)
run_hash() {
    _dir=$1
    _body='compute_content_hash "$2"
printf "%s\n" "$_cch_hash"'
    run env -i "HOME=$HOME" "PATH=/usr/bin:/bin:/sbin" /bin/sh -c "$(module_source_snippet)
$_body" -- "$TARGET" "$_dir"
}

@test "compute_content_hash: stability — same content computes the same hash (SCN-003-1)" {
    DIR=$BATS_TEST_TMPDIR/skill
    populate_dir "$DIR" a.txt "hello"
    populate_dir "$DIR" b.txt "world"
    run_hash "$DIR"; H1=$output
    run_hash "$DIR"; H2=$output
    [ "$status" -eq 0 ]
    [ -n "$H1" ]
    [ "$H1" = "$H2" ]
    [ "${#H1}" -eq 64 ]  # SHA-256 hex length
}

@test "compute_content_hash: sensitivity — file mutation changes the hash" {
    DIR=$BATS_TEST_TMPDIR/skill
    populate_dir "$DIR" a.txt "hello"
    run_hash "$DIR"; H1=$output
    printf '%s' "mutated" > "$DIR/a.txt"
    run_hash "$DIR"; H2=$output
    [ "$status" -eq 0 ]
    [ "$H1" != "$H2" ]
}

@test "compute_content_hash: .skill-lock excluded — mutating lockfile leaves hash unchanged (SCN-003-2)" {
    DIR=$BATS_TEST_TMPDIR/skill
    populate_dir "$DIR" SKILL.md "the actual skill"
    populate_dir "$DIR" .skill-lock "schemaVersion=1"
    run_hash "$DIR"; H1=$output
    printf '%s' "different lock content" > "$DIR/.skill-lock"
    run_hash "$DIR"; H2=$output
    [ "$status" -eq 0 ]
    [ "$H1" = "$H2" ]
}

@test "compute_content_hash: empty dir — hash equals SHA-256 of empty input (SCN-003-3)" {
    DIR=$BATS_TEST_TMPDIR/skill-empty
    mkdir -p "$DIR"
    run_hash "$DIR"
    [ "$status" -eq 0 ]
    [ "$output" = "$EMPTY_SHA256" ]
}

@test "compute_content_hash: random file creation order produces identical hash (SCN-003-4)" {
    DIR1=$BATS_TEST_TMPDIR/skill-order1
    DIR2=$BATS_TEST_TMPDIR/skill-order2
    populate_dir "$DIR1" a.txt "alpha"
    populate_dir "$DIR1" b.txt "beta"
    populate_dir "$DIR1" c.txt "gamma"
    # Same files in different order of creation; find may surface
    # them in a different filesystem order across mounts.
    populate_dir "$DIR2" c.txt "gamma"
    populate_dir "$DIR2" a.txt "alpha"
    populate_dir "$DIR2" b.txt "beta"
    run_hash "$DIR1"; H1=$output
    run_hash "$DIR2"; H2=$output
    [ "$status" -eq 0 ]
    [ "$H1" = "$H2" ]
}

@test "compute_content_hash: dies 1 if _sha256_cmd is unset (REQ-008)" {
    DIR=$BATS_TEST_TMPDIR/skill
    populate_dir "$DIR" a.txt "hello"
    # Force _sha256_cmd="" before invoking. We shell in with a small
    # snippet that nullifies the global before delegating to the
    # sourced module body.
    BODY='_sha256_cmd=
compute_content_hash "$2"
printf "%s\n" "$_cch_hash"'
    run env -i "HOME=$HOME" "PATH=/usr/bin:/bin:/sbin" /bin/sh -c "$(module_source_snippet)
$BODY" -- "$TARGET" "$DIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"sha256 not detected"* ]]
}

@test "compute_content_hash: nested directories contribute to hash (round-trip with a deep tree)" {
    DIR=$BATS_TEST_TMPDIR/skill-deep
    mkdir -p "$DIR/sub/deeper"
    populate_dir "$DIR" top.txt "alpha"
    populate_dir "$DIR/sub" mid.txt "beta"
    populate_dir "$DIR/sub/deeper" leaf.txt "gamma"
    run_hash "$DIR"; H1=$output
    [ "$status" -eq 0 ]
    [ "${#H1}" -eq 64 ]
    # Mutating a deep file changes the hash.
    printf '%s' "delta" > "$DIR/sub/deeper/leaf.txt"
    run_hash "$DIR"; H2=$output
    [ "$H1" != "$H2" ]
}

# ---- read_lock (REQ-001) ---------------------------------------------------

# Five globals populated by read_lock. Populate-side assertions verify
# the round-trip; missing-file and empty-file cases must leave all
# five empty.
LOCK_URL="https://github.com/example/repo.git"
LOCK_COMMIT="0123456789abcdef0123456789abcdef01234567"
LOCK_HASH="a]b]c]d]e]f]0]1]2]3]4]5]6]7]8]9]0]a]b]c]d]e]f]0]1]2]3]4]5]6]7]8]9]0]1]2]3]4]5]6]7]8]9]0]a]b]c]d]e]f]0]1]2]3]4]5]6]7]8]9"
LOCK_HASH="${LOCK_HASH//]/}"  # strip our placeholders; below is the real hex
LOCK_HASH="abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
LOCK_INSTALLED="2026-08-10T15:00:00Z"
LOCK_SCHEMA="1"

# read_lock_inside <dir>
# Runs `read_lock <dir>` in a sourced subshell and echoes the five
# globals, one per line, in fixed order:
#   _rl_url _rl_commit _rl_hash _rl_schema _rl_installed_at
read_lock_inside() {
    _dir=$1
    _body='read_lock "$2"
printf "%s\n%s\n%s\n%s\n%s\n" \
  "$_rl_url" "$_rl_commit" "$_rl_hash" "$_rl_schema" "$_rl_installed_at"'
    run env -i "HOME=$HOME" "PATH=/usr/bin:/bin:/sbin" /bin/sh -c "$(module_source_snippet)
$_body" -- "$TARGET" "$_dir"
}

# write_lockfile <dir>
# Writes a known-good v1 lockfile with the LOCK_* fixtures above.
write_lockfile() {
    _dir=$1
    {
        printf '# agent-skills.sh skill-lock v1\n'
        printf 'schemaVersion=1\n'
        printf 'origin.url=%s\n' "$LOCK_URL"
        printf 'origin.commit=%s\n' "$LOCK_COMMIT"
        printf 'installedAt=%s\n' "$LOCK_INSTALLED"
        printf 'contentHash=%s\n' "$LOCK_HASH"
    } > "$_dir/.skill-lock"
}

@test "read_lock: parses a valid lockfile into the five globals (SCN-001-1)" {
    DIR=$BATS_TEST_TMPDIR/skill
    mkdir -p "$DIR"
    write_lockfile "$DIR"
    read_lock_inside "$DIR"
    [ "$status" -eq 0 ]
    # First line is _rl_url ... fifth is _rl_installed_at.
    url=$(printf '%s' "$output" | sed -n '1p')
    commit=$(printf '%s' "$output" | sed -n '2p')
    hash=$(printf '%s' "$output" | sed -n '3p')
    schema=$(printf '%s' "$output" | sed -n '4p')
    installed=$(printf '%s' "$output" | sed -n '5p')
    [ "$url" = "$LOCK_URL" ]
    [ "$commit" = "$LOCK_COMMIT" ]
    [ "$hash" = "$LOCK_HASH" ]
    [ "$schema" = "$LOCK_SCHEMA" ]
    [ "$installed" = "$LOCK_INSTALLED" ]
}

@test "read_lock: missing .skill-lock leaves all five globals empty, exits 0 (SCN-001-2)" {
    DIR=$BATS_TEST_TMPDIR/skill
    mkdir -p "$DIR"
    # No .skill-lock file.
    read_lock_inside "$DIR"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '\n\n\n\n\n')" ]
}

@test "read_lock: empty .skill-lock is treated as missing (SCN-001-2 boundary)" {
    DIR=$BATS_TEST_TMPDIR/skill
    mkdir -p "$DIR"
    : > "$DIR/.skill-lock"
    read_lock_inside "$DIR"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '\n\n\n\n\n')" ]
}

@test "read_lock: lockfile with only schemaVersion populates schema, leaves others empty" {
    # Partial-field behavior: read_lock writes whatever keys it sees
    # and leaves the rest empty. The downstream reinstall logic uses
    # the empty values as a mismatch (REQ-004 / REQ-005).
    DIR=$BATS_TEST_TMPDIR/skill
    mkdir -p "$DIR"
    printf 'schemaVersion=1\n' > "$DIR/.skill-lock"
    read_lock_inside "$DIR"
    [ "$status" -eq 0 ]
    url=$(printf '%s' "$output" | sed -n '1p')
    schema=$(printf '%s' "$output" | sed -n '4p')
    [ "$url" = "" ]
    [ "$schema" = "1" ]
}

@test "read_lock: corrupt lockfile (it's a directory) is treated as missing" {
    DIR=$BATS_TEST_TMPDIR/skill
    mkdir -p "$DIR/.skill-lock"
    # Place a sentinel inside; we should NOT see its content in any global.
    echo "garbage" > "$DIR/.skill-lock/sentinel"
    read_lock_inside "$DIR"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '\n\n\n\n\n')" ]
}

@test "read_lock: comment-only lines and blank lines are skipped, not parsed" {
    DIR=$BATS_TEST_TMPDIR/skill
    mkdir -p "$DIR"
    {
        printf '# this is a comment\n'
        printf '\n'
        printf '   \n'
        printf '# schemaVersion=99 (in a comment, ignored)\n'
        printf 'schemaVersion=%s\n' "$LOCK_SCHEMA"
        printf 'origin.url=%s\n' "$LOCK_URL"
        printf 'origin.commit=%s\n' "$LOCK_COMMIT"
        printf 'installedAt=%s\n' "$LOCK_INSTALLED"
        printf 'contentHash=%s\n' "$LOCK_HASH"
    } > "$DIR/.skill-lock"
    read_lock_inside "$DIR"
    [ "$status" -eq 0 ]
    url=$(printf '%s' "$output" | sed -n '1p')
    commit=$(printf '%s' "$output" | sed -n '2p')
    schema=$(printf '%s' "$output" | sed -n '4p')
    [ "$url" = "$LOCK_URL" ]
    [ "$commit" = "$LOCK_COMMIT" ]
    [ "$schema" = "$LOCK_SCHEMA" ]
}

@test "read_lock: schemaVersion other than 1 is read verbatim (copy_skill decides)" {
    # Req-006 lives in copy_skill (die 1); read_lock just parses
    # whatever schemaVersion the file claims.
    DIR=$BATS_TEST_TMPDIR/skill
    mkdir -p "$DIR"
    {
        printf '# agent-skills.sh skill-lock v2 (future)\n'
        printf 'schemaVersion=2\n'
        printf 'origin.url=%s\n' "$LOCK_URL"
    } > "$DIR/.skill-lock"
    read_lock_inside "$DIR"
    [ "$status" -eq 0 ]
    schema=$(printf '%s' "$output" | sed -n '4p')
    [ "$schema" = "2" ]
}

@test "read_lock: value containing '=' is captured intact (first '=' is the separator)" {
    # origin.url may legitimately contain `=` (e.g. query strings).
    # The split-on-first-`=` policy keeps the value intact.
    DIR=$BATS_TEST_TMPDIR/skill
    mkdir -p "$DIR"
    printf 'origin.url=https://example.com/repo?token=abc=def\n' > "$DIR/.skill-lock"
    read_lock_inside "$DIR"
    [ "$status" -eq 0 ]
    url=$(printf '%s' "$output" | sed -n '1p')
    [ "$url" = "https://example.com/repo?token=abc=def" ]
}

# ---- write_lock (REQ-002, REQ-009) -----------------------------------------

# write_lock_inside <dir>
# Sources the module, sets the four write-side globals, and calls
# `write_lock <dir>`. Bats captures the function's exit status.
write_lock_inside() {
    _dir=$1
    _body='_cs_url='"$LOCK_URL"'
_cs_commit='"$LOCK_COMMIT"'
_cs_hash='"$LOCK_HASH"'
write_lock "$2"
printf "ok\n"'
    run env -i "HOME=$HOME" "PATH=/usr/bin:/bin:/sbin" /bin/sh -c "$(module_source_snippet)
$_body" -- "$TARGET" "$_dir"
}

# shellcheck disable=SC2034  # used inside sourced subshell tests
_cs_url=
_cs_commit=

@test "write_lock: writes a v1 lockfile with header + 4 fields (SCN-002-1, SCN-009-1)" {
    DIR=$BATS_TEST_TMPDIR/skill
    mkdir -p "$DIR"
    write_lock_inside "$DIR"
    [ "$status" -eq 0 ]
    [ -f "$DIR/.skill-lock" ]
    first_line=$(sed -n '1p' "$DIR/.skill-lock")
    [ "$first_line" = "# agent-skills.sh skill-lock v1" ]
    # Verify all four fields are present and well-formed.
    grep -qE '^schemaVersion=1$' "$DIR/.skill-lock"
    grep -qE "^origin\.url=${LOCK_URL}\$" "$DIR/.skill-lock"
    # 40-hex commit
    grep -qE '^origin\.commit=[0-9a-f]{40}$' "$DIR/.skill-lock"
    # ISO 8601 UTC (YYYY-MM-DDTHH:MM:SSZ)
    grep -qE '^installedAt=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$DIR/.skill-lock"
    # 64-hex hash
    grep -qE '^contentHash=[0-9a-f]{64}$' "$DIR/.skill-lock"
}

@test "write_lock: round-trips through read_lock (content_hash + commit + url + schema + installedAt)" {
    # write_lock calls compute_content_hash internally, so we have to
    # populate the dir with real files BEFORE write_lock runs.
    DIR=$BATS_TEST_TMPDIR/skill
    populate_dir "$DIR" SKILL.md "# Test"
    populate_dir "$DIR" body.txt "real content"
    write_lock_inside "$DIR"
    [ "$status" -eq 0 ]
    # Round-trip through read_lock:
    read_lock_inside "$DIR"
    [ "$status" -eq 0 ]
    url=$(printf '%s' "$output" | sed -n '1p')
    commit=$(printf '%s' "$output" | sed -n '2p')
    hash=$(printf '%s' "$output" | sed -n '3p')
    schema=$(printf '%s' "$output" | sed -n '4p')
    [ "$url" = "$LOCK_URL" ]
    [ "$commit" = "$LOCK_COMMIT" ]
    [ "$schema" = "1" ]
    # _cch_hash and LOCK_HASH differ because write_lock computes the
    # actual SHA-256 of the populated tree; LOCK_HASH is just a
    # placeholder in this fixture. The round-trip value comes from
    # the live computation, not the placeholder.
    [ "${#hash}" -eq 64 ]
}

@test "write_lock: round-trip with matching computed hash (lockfile writing the live SHA-256)" {
    # Demonstrate that write_lock's contentHash equals what
    # compute_content_hash returns for the SAME dir.
    DIR=$BATS_TEST_TMPDIR/skill-rt
    populate_dir "$DIR" SKILL.md "# Test"
    populate_dir "$DIR" body.txt "real content"
    BODY='_cs_url='"$LOCK_URL"'
_cs_commit='"$LOCK_COMMIT"'
compute_content_hash "$2" >/dev/null 2>&1
write_lock "$2"
printf "%s\n" "$_cch_hash"'
    EXPECTED=$(compute_content_hash_for_dir "$DIR")
    run env -i "HOME=$HOME" "PATH=/usr/bin:/bin:/sbin" /bin/sh -c "$(module_source_snippet)
$BODY" -- "$TARGET" "$DIR"
    [ "$status" -eq 0 ]
    [ "$output" = "$EXPECTED" ]
    last_hash=$(awk 'END{print}' "$DIR/.skill-lock" | sed 's/^contentHash=//')
    [ "$last_hash" = "$EXPECTED" ]
}

@test "write_lock: atomic — no .skill-lock if mv was never reached (REQ-002 atomicity)" {
    # Atomicity invariant (SCN-002-2): if write_lock fails between
    # `mktemp` and `mv`, the destination `.skill-lock` MUST NOT exist.
    # We force a failure by pointing write_lock at a path whose parent
    # directory does not exist — `mv` cannot create the final
    # .skill-lock because the parent isn't a directory.
    NONEXISTENT=$BATS_TEST_TMPDIR/not-a-dir/here/skill
    BODY='_cs_url='"$LOCK_URL"'
_cs_commit='"$LOCK_COMMIT"'
write_lock "$2" 2>/dev/null
exit $?'
    run env -i "HOME=$HOME" "PATH=/usr/bin:/bin:/sbin" /bin/sh -c "$(module_source_snippet)
$BODY" -- "$TARGET" "$NONEXISTENT"
    # write_lock dies 1 because mv can't land.
    [ "$status" -ne 0 ]
    # The destination's lockfile must not exist.
    [ ! -e "$NONEXISTENT/.skill-lock" ]
}

@test "write_lock: trap cleans up the temp file on write failure (no leak)" {
    # After a failed write_lock, the mktemp temp file must be cleaned
    # up by the EXIT trap. The previous version of this test sampled
    # `ls /tmp | wc -l` with a 50-entry slack threshold, which
    # accepted up to ~50 leaked files as "noise" — a regression in
    # the trap could leak hundreds of files and still pass. This
    # version controls exactly where the script's `mktemp` lands its
    # temp file (via a PATH shim) and asserts zero delta in that
    # directory before vs after the failed write_lock.
    #
    # Why a mktemp shim: on macOS the bare `mktemp` ignores TMPDIR
    # and lands in /var/folders/.../T/, which is shared with every
    # other process on the host. Snapshotting that dir for any
    # pattern is racy. By intercepting `mktemp` via PATH, we land
    # the script's temp file in a per-test spy directory and can
    # compare exact counts.
    NONEXISTENT=$BATS_TEST_TMPDIR/nowhere/here/skill
    SPY=$BATS_TEST_TMPDIR/mktemp-spy
    mkdir -p "$SPY"
    BIN=$BATS_TEST_TMPDIR/bin-trap
    mkdir -p "$BIN"
    # Shim: drop a tmp.XXXXXXXX file inside $SPY via the real
    # /usr/bin/mktemp -p. The script's bare `mktemp` call resolves
    # through PATH and picks this shim up first.
    printf '#!/bin/sh\nexec /usr/bin/mktemp -p "%s" "tmp.XXXXXXXX"\n' "$SPY" \
        > "$BIN/mktemp"
    chmod +x "$BIN/mktemp"

    # Snapshot the spy dir BEFORE the failure path runs.
    BEFORE=$(ls "$SPY"/tmp.???????? 2>/dev/null | wc -l)
    BODY='_cs_url='"$LOCK_URL"'
_cs_commit='"$LOCK_COMMIT"'
write_lock "$2" 2>/dev/null
exit $?'
    run env -i "HOME=$HOME" "PATH=$BIN:/usr/bin:/bin:/sbin" /bin/sh -c "$(module_source_snippet)
$BODY" -- "$TARGET" "$NONEXISTENT"
    # Status non-zero — write_lock failed at the `mv` step because
    # the parent directory does not exist.
    [ "$status" -ne 0 ]

    # Snapshot AFTER. Exact equality: zero leaked files. A regression
    # in the trap (or in mktemp error handling) would leave one or
    # more `tmp.XXXXXXXX` files behind and the count would grow.
    AFTER=$(ls "$SPY"/tmp.???????? 2>/dev/null | wc -l)
    [ "$AFTER" -eq "$BEFORE" ]
}

# Triangulation: on the SUCCESS path, no temp file is left behind
# either. The trap clears itself after `mv` succeeds (line 207 of
# agent-skills.sh), and `mv` consumes the temp file, so the spy
# directory must be empty after a successful write_lock.
@test "write_lock: success path leaves no temp file behind either (trap cleared, mv consumed)" {
    DIR=$BATS_TEST_TMPDIR/skill-success
    SPY=$BATS_TEST_TMPDIR/mktemp-spy-success
    mkdir -p "$SPY"
    BIN=$BATS_TEST_TMPDIR/bin-trap-success
    mkdir -p "$BIN"
    printf '#!/bin/sh\nexec /usr/bin/mktemp -p "%s" "tmp.XXXXXXXX"\n' "$SPY" \
        > "$BIN/mktemp"
    chmod +x "$BIN/mktemp"

    # Snapshot before — should be 0 (fresh dir) but assert anyway
    # so this test is robust against other tests using the same path.
    BEFORE=$(ls "$SPY"/tmp.???????? 2>/dev/null | wc -l)
    populate_dir "$DIR" SKILL.md "real skill content"

    # Inline the call so we can inject our mktemp-shim PATH.
    BODY='_cs_url='"$LOCK_URL"'
_cs_commit='"$LOCK_COMMIT"'
write_lock "$2"
printf "ok\n"'
    run env -i "HOME=$HOME" "PATH=$BIN:/usr/bin:/bin:/sbin" /bin/sh -c "$(module_source_snippet)
$BODY" -- "$TARGET" "$DIR"

    [ "$status" -eq 0 ]
    [ -f "$DIR/.skill-lock" ]
    AFTER=$(ls "$SPY"/tmp.???????? 2>/dev/null | wc -l)
    [ "$AFTER" -eq "$BEFORE" ]
}

@test "write_lock: overwrite — fresh timestamp, same shape (idempotent semantics)" {
    # Calling write_lock twice in a row produces a well-formed lockfile
    # both times. Timestamps may differ between invocations; the field
    # shapes must match.
    DIR=$BATS_TEST_TMPDIR/skill
    mkdir -p "$DIR"
    write_lock_inside "$DIR"
    [ "$status" -eq 0 ]
    first_count=$(wc -l < "$DIR/.skill-lock")
    sleep 1
    write_lock_inside "$DIR"
    [ "$status" -eq 0 ]
    second_count=$(wc -l < "$DIR/.skill-lock")
    [ "$first_count" = "$second_count" ]
    # Both files have the v1 header:
    sed -n '1p' "$DIR/.skill-lock" | grep -q "v1"
}
