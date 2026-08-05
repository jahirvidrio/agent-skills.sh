#!/usr/bin/env bats
# tests/test_copy_skill.bats - covers copy_skill: replacement and
# .git stripping.

load 'lib/test_helper'

@test "copy_skill replaces existing destination" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    # Pre-create dest with stale content
    mkdir -p "$DEST/my-skill"
    echo "stale" > "$DEST/my-skill/stale.txt"
    prepopulate_cache "local/repo-single" "$FIXTURE"
    setup_fake_git

    run_script "file://$FIXTURE" --skill "my-skill" "$DEST"

    [ "$status" -eq 0 ]
    [ ! -f "$DEST/my-skill/stale.txt" ]
    [ -f "$DEST/my-skill/SKILL.md" ]
}

@test "copy_skill creates destination parent if missing" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/deep/nested/dest"
    prepopulate_cache "local/repo-single" "$FIXTURE"
    setup_fake_git

    run_script "file://$FIXTURE" --skill "my-skill" "$DEST"

    [ "$status" -eq 0 ]
    [ -f "$DEST/my-skill/SKILL.md" ]
}

@test "copy_skill strips .git/ from the destination tree" {
    # prepopulate_cache adds an empty .git/ marker; copy_skill must
    # remove it so the installed skill has no .git directory.
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    prepopulate_cache "local/repo-single" "$FIXTURE"
    setup_fake_git

    run_script "file://$FIXTURE" --skill "my-skill" "$DEST"

    [ "$status" -eq 0 ]
    [ ! -d "$DEST/my-skill/.git" ]
}