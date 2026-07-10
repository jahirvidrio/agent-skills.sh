#!/usr/bin/env bats
# tests/test_clone_or_update.bats - covers clone vs. pull vs. failure.
#
# The fake git supports clone (copies fixture into dest) and silently
# succeeds for pull. Tests use FAKE_GIT_FAIL=1 to exercise the
# failure path.

load 'lib/test_helper'

@test "clone path: empty cache -> fake git clones fixture -> exit 0" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    setup_fake_git

    run_script "file://$FIXTURE" "my-skill" "$DEST"

    [ "$status" -eq 0 ]
    [ -f "$DEST/my-skill/SKILL.md" ]
    [ -d "$(cache_root)/local/repo-single" ]
}

@test "pull path: existing cache with .git/ -> pull succeeds -> exit 0" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    prepopulate_cache "local/repo-single" "$FIXTURE"
    setup_fake_git

    run_script "file://$FIXTURE" "my-skill" "$DEST"

    [ "$status" -eq 0 ]
    [ -f "$DEST/my-skill/SKILL.md" ]
}

@test "existing cache dir without .git/ -> exit 4" {
    BAD=$(cache_root)/local/bad-repo
    mkdir -p "$BAD"
    echo "leftover" > "$BAD/some-file"
    setup_fake_git

    run_script "file:///foo/bad-repo.git" "my-skill" "$BATS_TEST_TMPDIR/dest"

    [ "$status" -eq 4 ]
    [[ "$output" == *"is not a git repo"* ]]
}

@test "FAKE_GIT_FAIL=1 on clone -> exit 4 and partial dir is cleaned" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    setup_fake_git
    export FAKE_GIT_FAIL=1

    run_script "file://$FIXTURE" "my-skill" "$DEST"

    [ "$status" -eq 4 ]
    [[ "$output" == *"git clone failed"* ]]
    [ ! -d "$(cache_root)/local/repo-single" ]
}