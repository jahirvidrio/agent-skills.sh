#!/usr/bin/env bats
# tests/test_e2e.bats - end-to-end via file:// fixture URLs.
#
# These tests run the script as a real user would, only swapping the
# network for a local fixture directory. stdin is /dev/null (bats
# default), so ambiguous-match cases take exit 5.

load 'lib/test_helper'

@test "e2e single-match repo: success and skill installed" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    setup_fake_git

    run_script "file://$FIXTURE" --skill "my-skill" "$DEST"

    [ "$status" -eq 0 ]
    [ -f "$DEST/my-skill/SKILL.md" ]
    [[ "$output" == *"Installed: $DEST/my-skill"* ]]
    [[ "$output" == *"Done."* ]]
}

@test "e2e multi-match repo non-TTY: exit 5 with sorted match list" {
    FIXTURE=$(fixture_path repo-multi)
    setup_fake_git

    run_script "file://$FIXTURE" --skill "my-skill" "$BATS_TEST_TMPDIR/dest"

    [ "$status" -eq 5 ]
    [[ "$output" == *".agents/my-skill"* ]]
    [[ "$output" == *".opencode/my-skill"* ]]
    [[ "$output" == *".skills/my-skill"* ]]
    [[ "$output" == *"random/my-skill"* ]]
}

@test "e2e empty repo: exit 3 (skill not found)" {
    FIXTURE=$(fixture_path repo-empty)
    setup_fake_git

    run_script "file://$FIXTURE" --skill "my-skill" "$BATS_TEST_TMPDIR/dest"

    [ "$status" -eq 3 ]
}

@test "e2e logs include repo, skills, cache, and dest-dir lines" {
    FIXTURE=$(fixture_path repo-single)
    setup_fake_git
    DEST="$BATS_TEST_TMPDIR/dest"

    run_script "file://$FIXTURE" --skill "my-skill" "$DEST"

    [ "$status" -eq 0 ]
    [[ "$output" == *"repo:     file://$FIXTURE"* ]]
    [[ "$output" == *"skills:   my-skill"* ]]
    [[ "$output" == *"cache:    $(cache_root)/local/repo-single"* ]]
    [[ "$output" == *"dest-dir: $DEST"* ]]
}