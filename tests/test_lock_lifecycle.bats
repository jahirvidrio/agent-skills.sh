#!/usr/bin/env bats
# tests/test_lock_lifecycle.bats - covers the lock-aware copy_skill flow
# (REQ-004, REQ-005, REQ-006) and the main plumbing that feeds the
# URL + commit through (REQ-007). Tests run end-to-end via real
# file:// clones so lockfile reads/writes exercise the full path.

load 'lib/test_helper'

# write_lockfile <dir> <url> <commit> <hash>
# Drops a v1 lockfile into <dir>/.skill-lock.
write_lockfile() {
    _dir=$1
    _url=$2
    _commit=$3
    _hash=$4
    {
        printf '# agent-skills.sh skill-lock v1\n'
        printf 'schemaVersion=1\n'
        printf 'origin.url=%s\n' "$_url"
        printf 'origin.commit=%s\n' "$_commit"
        printf 'installedAt=2026-08-10T15:00:00Z\n'
        printf 'contentHash=%s\n' "$_hash"
    } > "$_dir/.skill-lock"
}

# setup_fake_git_with_rev_parse
# Wraps setup_fake_git, then rewrites the git stub so `rev-parse HEAD`
# returns the value of $FAKE_GIT_REV_PARSE (default: 40-hex zero-ish
# string). main() reads HEAD via `git -C "$CACHE_DIR" rev-parse HEAD`
# (line 1055 of agent-skills.sh); without this support the script dies
# 1 with "cannot read HEAD from cache".
#
# The rev-parse branch is inserted BEFORE the clone branch so it wins
# regardless of where `-C <dir>` lands in argv.
setup_fake_git_with_rev_parse() {
    setup_fake_git
    FAKE_BIN=$BATS_TEST_TMPDIR/fakebin
    cat > "$FAKE_BIN/git" <<'GITEOF'
#!/bin/sh
if [ -n "${GIT_CALL_LOG:-}" ]; then
    printf '%s\n' "$*" >> "$GIT_CALL_LOG"
fi
if [ "${FAKE_GIT_FAIL:-0}" = "1" ]; then
    printf 'fake-git: forced failure\n' >&2
    exit 1
fi
case $* in
    *"rev-parse"*"HEAD"*)
        printf '%s\n' "${FAKE_GIT_REV_PARSE:-0123456789abcdef0123456789abcdef01234567}"
        exit 0
        ;;
esac
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
GITEOF
    chmod +x "$FAKE_BIN/git"
}

# Lifecycle tests cache the result of fixture_path/cache_root/prepopulate
# so that re-runs within a single test see the same cache dir.

@test "copy_skill: skip install when URL, commit, and contentHash all match (SCN-004-1)" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    prepopulate_cache "local/repo-single" "$FIXTURE"
    setup_fake_git
    export FAKE_GIT_ORIGIN="file://$FIXTURE"

    run_script "file://$FIXTURE" --skill "my-skill" --dest "$DEST"
    [ "$status" -eq 0 ]
    [ -f "$DEST/my-skill/.skill-lock" ]

    run_script "file://$FIXTURE" --skill "my-skill" --dest "$DEST"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Installed: $DEST/my-skill"* ]]
}

@test "copy_skill: reinstall + new lockfile when contentHash is stale (SCN-004-2)" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    prepopulate_cache "local/repo-single" "$FIXTURE"
    setup_fake_git
    export FAKE_GIT_ORIGIN="file://$FIXTURE"

    run_script "file://$FIXTURE" --skill "my-skill" --dest "$DEST"
    [ "$status" -eq 0 ]
    sed -i '' 's/^contentHash=.*/contentHash=0000000000000000000000000000000000000000000000000000000000000000/' "$DEST/my-skill/.skill-lock"
    run_script "file://$FIXTURE" --skill "my-skill" --dest "$DEST"
    [ "$status" -eq 0 ]
    NEW_HASH=$(awk -F= '/^contentHash=/ {print $2}' "$DEST/my-skill/.skill-lock")
    [ "$NEW_HASH" != "0000000000000000000000000000000000000000000000000000000000000000" ]
    [ "${#NEW_HASH}" -eq 64 ]
}

@test "copy_skill: no .skill-lock written when cp -Rp fails (SCN-005-1)" {
    FIXTURE=$(fixture_path repo-single)
    prepopulate_cache "local/repo-single" "$FIXTURE"
    setup_fake_git
    export FAKE_GIT_ORIGIN="file://$FIXTURE"

    # Make the parent directory unwriteable so `cp -Rp` to <DEST>
    # fails after the cache is populated and the script reaches copy.
    PARENT=$BATS_TEST_TMPDIR/parent
    mkdir -p "$PARENT"
    chmod 555 "$PARENT"
    run_script "file://$FIXTURE" --skill "my-skill" --dest "$PARENT/dest"
    chmod 755 "$PARENT"
    [ "$status" -ne 0 ]
    [ ! -e "$PARENT/dest/my-skill/.skill-lock" ]
}

@test "copy_skill: dies 1 when .skill-lock has schemaVersion=2 (SCN-006-1)" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    prepopulate_cache "local/repo-single" "$FIXTURE"
    setup_fake_git
    export FAKE_GIT_ORIGIN="file://$FIXTURE"

    mkdir -p "$DEST/my-skill"
    echo "# Original" > "$DEST/my-skill/SKILL.md"
    write_lockfile "$DEST/my-skill" "file://$FIXTURE" "0123456789abcdef0123456789abcdef01234567" "x"
    sed -i '' 's/^schemaVersion=1$/schemaVersion=2/' "$DEST/my-skill/.skill-lock"

    run_script "file://$FIXTURE" --skill "my-skill" --dest "$DEST"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unsupported schema version"* ]]
    [ -f "$DEST/my-skill/SKILL.md" ]
}

@test "main: lockfile origin.url matches _canonicalize_url output (SCN-007-1)" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    prepopulate_cache "local/repo-single" "$FIXTURE"
    setup_fake_git
    export FAKE_GIT_ORIGIN="file://$FIXTURE"

    run_script "file://$FIXTURE" --skill "my-skill" --dest "$DEST"
    [ "$status" -eq 0 ]
    saved_url=$(awk -F= '/^origin.url=/ {print $2}' "$DEST/my-skill/.skill-lock")
    expected=$(printf '%s' "file://$FIXTURE" | sed 's/[[:space:]]*$//')
    expected=${expected%.git}
    [ "$saved_url" = "$expected" ]
}

@test "main: lockfile origin.commit is the 40-hex rev-parse HEAD (SCN-007-1)" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    prepopulate_cache "local/repo-single" "$FIXTURE"
    setup_fake_git
    export FAKE_GIT_ORIGIN="file://$FIXTURE"
    # Patch the fake bin so its `rev-parse HEAD` returns a known SHA.
    # NOTE: setup_fake_git writes the git stub with a final `exit 0`,
    # so we rewrite the file with our rev-parse branch inserted BEFORE
    # the trailing exit (bash exits before reaching lines after it).
    FAKE_BIN=$BATS_TEST_TMPDIR/fakebin
    cat > "$FAKE_BIN/git" <<'EOF'
#!/bin/sh
# Patched fake git that supports `rev-parse HEAD` for this test.
if [ -n "${GIT_CALL_LOG:-}" ]; then
    printf '%s\n' "$*" >> "$GIT_CALL_LOG"
fi

if [ "${FAKE_GIT_FAIL:-0}" = "1" ]; then
    printf 'fake-git: forced failure\n' >&2
    exit 1
fi

# Rev-parse support — must come BEFORE `clone` since $1 may be -C.
case $* in
    *"rev-parse"*"HEAD"*)
        printf '%s\n' "${FAKE_GIT_REV_PARSE:-0123456789abcdef0123456789abcdef01234567}"
        exit 0
        ;;
esac

# Branch: `git [-C <dir>] remote get-url origin`.
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
    chmod +x "$FAKE_BIN/git"
    export FAKE_GIT_REV_PARSE="0123456789abcdef0123456789abcdef01234567"

    run_script "file://$FIXTURE" --skill "my-skill" --dest "$DEST"
    [ "$status" -eq 0 ]
    saved_commit=$(awk -F= '/^origin.commit=/ {print $2}' "$DEST/my-skill/.skill-lock")
    [ "$saved_commit" = "0123456789abcdef0123456789abcdef01234567" ]
    [ "${#saved_commit}" -eq 40 ]
}

@test "copy_skill: second run on unchanged skill hits skip path (no Installed: log)" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    prepopulate_cache "local/repo-single" "$FIXTURE"
    setup_fake_git
    export FAKE_GIT_ORIGIN="file://$FIXTURE"

    run_script "file://$FIXTURE" --skill "my-skill" --dest "$DEST"
    [ "$status" -eq 0 ]
    SNAP=$(awk -F= '/^installedAt=/ {print $2}' "$DEST/my-skill/.skill-lock")

    sleep 1

    run_script "file://$FIXTURE" --skill "my-skill" --dest "$DEST"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Installed: $DEST/my-skill"* ]]
    AFTER=$(awk -F= '/^installedAt=/ {print $2}' "$DEST/my-skill/.skill-lock")
    [ "$AFTER" = "$SNAP" ]
}

@test "copy_skill: local edit on installed file → mismatch on next run → reinstall" {
    # REQ-004 corollary: if the user edits an installed file, the
    # next run must detect the mismatch (contentHash differs) and
    # reinstall to repair the broken state.
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    prepopulate_cache "local/repo-single" "$FIXTURE"
    setup_fake_git
    export FAKE_GIT_ORIGIN="file://$FIXTURE"

    run_script "file://$FIXTURE" --skill "my-skill" --dest "$DEST"
    [ "$status" -eq 0 ]

    # User edits SKILL.md locally. Fixture content starts with
    # "# my-skill"; we overwrite with "USER EDITED".
    printf '%s\n' "USER EDITED" > "$DEST/my-skill/SKILL.md"
    [ "$(cat "$DEST/my-skill/SKILL.md")" = "USER EDITED" ]

    # Next run must reinstall — "Installed:" log line reappears and
    # the user edit is overwritten by the canonical content.
    run_script "file://$FIXTURE" --skill "my-skill" --dest "$DEST"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installed: $DEST/my-skill"* ]]
    [ "$(cat "$DEST/my-skill/SKILL.md")" = "# my-skill

Single-match fixture. No other copies anywhere in this repo." ]
}

# Spec edge case 10 — same content, different commit → reinstall.
# The skip predicate at agent-skills.sh:824-826 is an AND of URL,
# commit, and contentHash. URL and contentHash match (fixture hasn't
# changed), but commit differs, so the predicate must fail and
# copy_skill must reinstall (fresh timestamp, "Installed:" log,
# new commit recorded).
#
# Test setup: the fake git is patched (in-place) to return a
# configurable 40-hex SHA from `rev-parse HEAD`. First run records
# commit "aaaa...a" in the lockfile; second run with rev-parse
# returning "bbbb...b" (same content, different commit) must
# reinstall.
@test "copy_skill: reinstall when URL+hash match but commit differs (spec edge case 10)" {
    FIXTURE=$(fixture_path repo-single)
    DEST=$BATS_TEST_TMPDIR/dest
    prepopulate_cache "local/repo-single" "$FIXTURE"
    setup_fake_git_with_rev_parse
    export FAKE_GIT_ORIGIN="file://$FIXTURE"

    # First install: commit A (40 'a's).
    export FAKE_GIT_REV_PARSE="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    run_script "file://$FIXTURE" --skill "my-skill" --dest "$DEST"
    [ "$status" -eq 0 ]
    SNAP_INSTALLED=$(awk -F= '/^installedAt=/ {print $2}' "$DEST/my-skill/.skill-lock")
    ORIG_COMMIT=$(awk -F= '/^origin.commit=/ {print $2}' "$DEST/my-skill/.skill-lock")
    ORIG_HASH=$(awk -F= '/^contentHash=/ {print $2}' "$DEST/my-skill/.skill-lock")
    [ "$ORIG_COMMIT" = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ]
    [ "${#ORIG_HASH}" -eq 64 ]

    # Cross the 1-second ISO 8601 timestamp resolution so the second
    # write_lock produces a strictly later timestamp.
    sleep 1

    # Second run: commit B (40 'b's). Same URL, same content → same
    # hash, but commit differs → skip predicate fails → reinstall.
    export FAKE_GIT_REV_PARSE="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    run_script "file://$FIXTURE" --skill "my-skill" --dest "$DEST"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installed: $DEST/my-skill"* ]]
    NEW_COMMIT=$(awk -F= '/^origin.commit=/ {print $2}' "$DEST/my-skill/.skill-lock")
    NEW_INSTALLED=$(awk -F= '/^installedAt=/ {print $2}' "$DEST/my-skill/.skill-lock")
    NEW_HASH=$(awk -F= '/^contentHash=/ {print $2}' "$DEST/my-skill/.skill-lock")
    [ "$NEW_COMMIT" = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" ]
    # The content hash must NOT change (fixture content is identical
    # across the two runs); only commit and timestamp do.
    [ "$NEW_HASH" = "$ORIG_HASH" ]
    [ "$NEW_INSTALLED" != "$SNAP_INSTALLED" ]
}

# Triangulation for the W-002 skip predicate: once the reinstall has
# recorded the new commit (B) in the lockfile, a subsequent run with
# the same URL + commit B + matching hash MUST hit the skip path
# (no "Installed:" log line, timestamp preserved). Proves that the
# reinstall actually wrote a fresh lockfile with the new commit —
# the predicate now matches again.
@test "copy_skill: after commit-change reinstall, third run with new commit hits skip path" {
    FIXTURE=$(fixture_path repo-single)
    DEST=$BATS_TEST_TMPDIR/dest
    prepopulate_cache "local/repo-single" "$FIXTURE"
    setup_fake_git_with_rev_parse
    export FAKE_GIT_ORIGIN="file://$FIXTURE"

    # Two installs with different commits to land on commit B.
    export FAKE_GIT_REV_PARSE="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    run_script "file://$FIXTURE" --skill "my-skill" --dest "$DEST"
    [ "$status" -eq 0 ]
    sleep 1
    export FAKE_GIT_REV_PARSE="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    run_script "file://$FIXTURE" --skill "my-skill" --dest "$DEST"
    [ "$status" -eq 0 ]
    SNAP_INSTALLED=$(awk -F= '/^installedAt=/ {print $2}' "$DEST/my-skill/.skill-lock")

    sleep 1

    # Third run: same URL, same commit B, same content → skip.
    run_script "file://$FIXTURE" --skill "my-skill" --dest "$DEST"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Installed: $DEST/my-skill"* ]]
    AFTER_INSTALLED=$(awk -F= '/^installedAt=/ {print $2}' "$DEST/my-skill/.skill-lock")
    [ "$AFTER_INSTALLED" = "$SNAP_INSTALLED" ]
}
