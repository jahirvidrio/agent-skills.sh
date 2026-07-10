#!/usr/bin/env bats
# tests/test_find_skill_dir.bats - covers find_skill_dir behavior.
#
# These tests pre-populate the cache with fixtures and use a fake git
# (via setup_fake_git) so the script's pull/clone paths succeed
# without network. stdin is /dev/null in bats, so ambiguous matches
# always take the non-interactive exit-5 branch.

load 'lib/test_helper'

@test "single match: script copies skill and exits 0" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    prepopulate_cache "local/repo-single" "$FIXTURE"
    setup_fake_git

    run_script "file://$FIXTURE" "my-skill" "$DEST"

    [ "$status" -eq 0 ]
    [ -f "$DEST/my-skill/SKILL.md" ]
}

@test "multiple matches non-interactive: script exits 5 with match list" {
    FIXTURE=$(fixture_path repo-multi)
    prepopulate_cache "local/repo-multi" "$FIXTURE"
    setup_fake_git

    run_script "file://$FIXTURE" "my-skill" "$BATS_TEST_TMPDIR/dest"

    [ "$status" -eq 5 ]
    [[ "$output" == *"skills named 'my-skill' found"* ]]
}

@test "multiple matches are listed in priority order (.agents first)" {
    FIXTURE=$(fixture_path repo-multi)
    prepopulate_cache "local/repo-multi" "$FIXTURE"
    setup_fake_git

    run_script "file://$FIXTURE" "my-skill" "$BATS_TEST_TMPDIR/dest"

    [ "$status" -eq 5 ]
    # .agents must appear before .opencode in the match list
    _agents_pos=$(printf '%s' "$output" | grep -bo '\.agents/my-skill' | head -1 | cut -d: -f1)
    _opencode_pos=$(printf '%s' "$output" | grep -bo '\.opencode/my-skill' | head -1 | cut -d: -f1)
    [ -n "$_agents_pos" ]
    [ -n "$_opencode_pos" ]
    [ "$_agents_pos" -lt "$_opencode_pos" ]
}

@test "no matches: script exits 3 with skill-not-found error" {
    FIXTURE=$(fixture_path repo-empty)
    prepopulate_cache "local/repo-empty" "$FIXTURE"
    setup_fake_git

    run_script "file://$FIXTURE" "my-skill" "$BATS_TEST_TMPDIR/dest"

    [ "$status" -eq 3 ]
    [[ "$output" == *"skill 'my-skill' not found"* ]]
}

@test "matches inside .git/ are excluded from ranking" {
    # Set up a cache that has SKILL.md inside .git/ (which should be
    # ignored) AND inside .agents/ (which should be the only match).
    CACHE=$(cache_root)/local/matter
    mkdir -p "$CACHE/.git/objects" "$CACHE/.agents/my-skill"
    echo "# from git dir" > "$CACHE/.git/objects/SKILL.md"
    echo "# from .agents" > "$CACHE/.agents/my-skill/SKILL.md"
    setup_fake_git
    DEST="$BATS_TEST_TMPDIR/dest"

    run_script "file:///does/not/matter.git" "my-skill" "$DEST"

    [ "$status" -eq 0 ]
    [ -f "$DEST/my-skill/SKILL.md" ]
    [[ "$(cat "$DEST/my-skill/SKILL.md")" == *"from .agents"* ]]
}