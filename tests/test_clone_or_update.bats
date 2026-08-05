#!/usr/bin/env bats
# tests/test_clone_or_update.bats - covers clone vs. pull vs. failure.
#
# The fake git supports clone (copies fixture into dest) and silently
# succeeds for pull. Tests use FAKE_GIT_FAIL=1 to exercise the
# failure path.

load 'lib/test_helper'

setup() {
    setup_fake_git
    : > "${GIT_CALL_LOG:-/dev/null}"
}

@test "clone path: empty cache -> fake git clones fixture -> exit 0" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"

    run_script "file://$FIXTURE" --skill "my-skill" "$DEST"

    [ "$status" -eq 0 ]
    [ -f "$DEST/my-skill/SKILL.md" ]
    [ -d "$(cache_root)/local/repo-single" ]
}

@test "pull path: existing cache with .git/ -> pull succeeds -> exit 0" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    prepopulate_cache "local/repo-single" "$FIXTURE"

    run_script "file://$FIXTURE" --skill "my-skill" "$DEST"

    [ "$status" -eq 0 ]
    [ -f "$DEST/my-skill/SKILL.md" ]
}

@test "existing cache dir without .git/ -> exit 4" {
    BAD=$(cache_root)/local/bad-repo
    mkdir -p "$BAD"
    echo "leftover" > "$BAD/some-file"

    run_script "file:///foo/bad-repo.git" --skill "my-skill" "$BATS_TEST_TMPDIR/dest"

    [ "$status" -eq 4 ]
    [[ "$output" == *"is not a git repo"* ]]
}

@test "FAKE_GIT_FAIL=1 on clone -> exit 4 and partial dir is cleaned" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    export FAKE_GIT_FAIL=1

    run_script "file://$FIXTURE" --skill "my-skill" "$DEST"

    [ "$status" -eq 4 ]
    [[ "$output" == *"git clone failed"* ]]
    [ ! -d "$(cache_root)/local/repo-single" ]
}

@test "match path: cached origin matches requested URL -> pull runs, no clone" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    export FAKE_GIT_ORIGIN="file://$FIXTURE"
    prepopulate_cache "local/repo-single" "$FIXTURE"

    run_script "file://$FIXTURE" --skill "my-skill" "$DEST"

    [ "$status" -eq 0 ]
    [ -f "$DEST/my-skill/SKILL.md" ]
    grep -q "pull --depth=1" "$GIT_CALL_LOG"
    ! grep -q "^clone " "$GIT_CALL_LOG"
}

@test "mismatch path: cached origin does NOT match -> cache cleared, re-clone runs, exit 0" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    export FAKE_GIT_ORIGIN="file:///wrong/host/repo"
    prepopulate_cache "local/repo-single" "$FIXTURE"

    run_script "file://$FIXTURE" --skill "my-skill" "$DEST"

    [ "$status" -eq 0 ]
    [ -f "$DEST/my-skill/SKILL.md" ]
    grep -q "remote get-url origin" "$GIT_CALL_LOG"
    grep -q "^clone " "$GIT_CALL_LOG"
}

@test "missing origin: fake git's remote get-url origin exits non-zero -> re-clone runs" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    unset FAKE_GIT_ORIGIN
    prepopulate_cache "local/repo-single" "$FIXTURE"

    run_script "file://$FIXTURE" --skill "my-skill" "$DEST"

    [ "$status" -eq 0 ]
    [ -f "$DEST/my-skill/SKILL.md" ]
    grep -q "remote get-url origin" "$GIT_CALL_LOG"
    grep -q "^clone " "$GIT_CALL_LOG"
}

@test "cache miss: no cache dir -> no extra remote get-url subshell call" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    # Do NOT prepopulate cache.
    unset FAKE_GIT_ORIGIN

    run_script "file://$FIXTURE" --skill "my-skill" "$DEST"

    [ "$status" -eq 0 ]
    [ -f "$DEST/my-skill/SKILL.md" ]
    ! grep -q "remote get-url" "$GIT_CALL_LOG"
}

@test "no stderr warning on mismatch-triggered re-clone" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    export FAKE_GIT_ORIGIN="file:///wrong/host/repo"
    prepopulate_cache "local/repo-single" "$FIXTURE"

    run_script "file://$FIXTURE" --skill "my-skill" "$DEST"

    [ "$status" -eq 0 ]
    ! [[ "$output" == *"warning"* ]]
    ! [[ "$output" == *"mismatch"* ]]
    ! [[ "$output" == *"reclone"* ]]
    ! [[ "$output" == *"re-clon"* ]]
}