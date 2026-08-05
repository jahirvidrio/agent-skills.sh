#!/usr/bin/env bats
# tests/test_multi_skill.bats - covers the --skill repeatable flag, the
# default .agents/skills destination, and the atomic-batch semantics
# of multi-skill invocations.
#
# Template row (JD2-002): every test in this file uses the same
# invocation shape —
#
#     FIXTURE=$(fixture_path repo-multi-skills)
#     setup_fake_git
#     run_script file://$FIXTURE --skill <name> [--skill <name>...] [<dest>]
#
# — and asserts on exit code, $output substrings, destination
# filesystem state, and (where applicable) $GIT_CALL_LOG entry
# counts. Each test cd's to $BATS_TEST_TMPDIR so $PWD-relative
# assertions (default destination) are scoped to the test and do
# not leak across tests (JD-006). Warm-cache cases use
# prepopulate_cache from lib/test_helper. GIT_CALL_LOG greps use
# the double-dash form (--depth=1), not the typo'd single-dash
# form (JD-011).

load 'lib/test_helper'

FIXTURE=$(fixture_path repo-multi-skills)

setup() {
    cd "$BATS_TEST_TMPDIR"
}

# ---- Happy-path coverage --------------------------------------------------

@test "multi: single --skill copies one skill to default dest" {
    setup_fake_git
    run_script "file://$FIXTURE" --skill "alpha"

    [ "$status" -eq 0 ]
    [ -f "$PWD/.agents/skills/alpha/SKILL.md" ]
    [[ "$output" == *"Installed: .agents/skills/alpha"* ]]
}

@test "multi: two --skill flags install in order" {
    setup_fake_git
    run_script "file://$FIXTURE" --skill "alpha" --skill "beta"

    [ "$status" -eq 0 ]
    [ -f "$PWD/.agents/skills/alpha/SKILL.md" ]
    [ -f "$PWD/.agents/skills/beta/SKILL.md" ]
}

@test "multi: fresh cache -> exactly one clone --depth=1, zero pulls" {
    setup_fake_git
    run_script "file://$FIXTURE" --skill "alpha" --skill "beta"

    [ "$status" -eq 0 ]
    [ "$(grep -c 'clone --depth=1' "$GIT_CALL_LOG")" -eq 1 ]
    [ "$(grep -c 'pull --depth=1' "$GIT_CALL_LOG")" -eq 0 ]
}

@test "multi: warm cache -> exactly one pull --depth=1, zero clones" {
    prepopulate_cache "local/repo-multi-skills" "$FIXTURE"
    setup_fake_git
    export FAKE_GIT_ORIGIN="file://$FIXTURE"
    run_script "file://$FIXTURE" --skill "alpha" --skill "beta"

    [ "$status" -eq 0 ]
    [ "$(grep -c 'pull --depth=1' "$GIT_CALL_LOG")" -eq 1 ]
    [ "$(grep -c 'clone --depth=1' "$GIT_CALL_LOG")" -eq 0 ]
}

# ---- Atomic-batch failure modes -------------------------------------------

@test "multi: missing skill exits 3 with no partial copies" {
    setup_fake_git
    run_script "file://$FIXTURE" --skill "alpha" --skill "ghost"

    [ "$status" -eq 3 ]
    [ ! -d "$PWD/.agents/skills" ]
    [ ! -d "$PWD/.agents/skills/alpha" ]
    [ ! -d "$PWD/.agents/skills/ghost" ]
}

@test "multi: invalid name exits 2 before clone" {
    setup_fake_git
    run_script "file://$FIXTURE" --skill "../etc/passwd" --skill "alpha"

    [ "$status" -eq 2 ]
    [ ! -d "$(cache_root)/local/repo-multi-skills" ]
    [ "$(grep -c 'clone' "$GIT_CALL_LOG")" -eq 0 ]
}

@test "multi: leading-dot name exits 2" {
    run_script "file://$FIXTURE" --skill ".hidden"

    [ "$status" -eq 2 ]
    [[ "$output" == *"invalid"* ]]
}

@test "multi: length>100 name exits 2" {
    LONG=$(printf 'a%.0s' {1..101})
    run_script "file://$FIXTURE" --skill "$LONG"

    [ "$status" -eq 2 ]
}

@test "multi: multi-bad-name mix reports first offender, no partial install" {
    setup_fake_git
    run_script "file://$FIXTURE" --skill "ok" --skill "../bad" --skill "also-ok"

    [ "$status" -eq 2 ]
    [[ "$output" == *"../bad"* ]]
    [ ! -d "$PWD/.agents/skills" ]
}

# ---- Disambiguation semantics in multi-skill context ----------------------

@test "multi: single-match in multi-skill context installs silently" {
    setup_fake_git
    run_script "file://$FIXTURE" --skill "alpha" --skill "beta"

    [ "$status" -eq 0 ]
    # No prompt: each --skill resolves to exactly one match.
    [[ "$output" != *"Select"* ]]
}

@test "multi: N-matches + non-TTY in multi-skill -> exit 5, no partial copies" {
    FIXTURE=$(fixture_path repo-multi)
    setup_fake_git

    run_script "file://$FIXTURE" --skill "my-skill" "$BATS_TEST_TMPDIR/dest" </dev/null

    [ "$status" -eq 5 ]
    [ ! -d "$PWD/.agents/skills" ]
}

@test "multi: N-matches + TTY in multi-skill -> prompts" {
    FIXTURE=$(fixture_path repo-multi)
    setup_fake_git

    # macOS `script` does not support -c. We invoke the script
    # directly as the command argument: `script -q typescript
    # /path/to/script ...`. The PTY allocation makes [ ! -t 0 ]
    # return false in pick_skill_match, so the prompt path runs
    # instead of the exit-5 path. We do NOT verify prompt
    # completion (PTY-stdin piping across `script` is unreliable
    # on macOS); we only verify the prompt was emitted, which
    # proves the resolve_skills -> pick_skill_match -> prompt
    # chain works in multi-skill context. The prompt-completion
    # path itself is already covered by test_find_skill_dir.bats.
    export FAKE_GIT_ORIGIN="file://$FIXTURE"
    TYPESCRIPT="$BATS_TEST_TMPDIR/typescript"
    OUTPUT=$(script -q "$TYPESCRIPT" "$TARGET" "file://$FIXTURE" --skill "my-skill" "$BATS_TEST_TMPDIR/dest" 2>&1 || true)
    rm -f "$TYPESCRIPT"
    [[ "$OUTPUT" == *"Found 4 matches"* ]]
    [[ "$OUTPUT" == *"Select [1-4]"* ]]
}

# ---- --skill flag parser cases --------------------------------------------

@test "multi: --skill=foo rejected with exit 2" {
    run_script "file://$FIXTURE" --skill=foo

    [ "$status" -eq 2 ]
    [[ "$output" == *"separate tokens"* ]]
}

@test "multi: --skill as last token exits 2" {
    run_script "file://$FIXTURE" --skill

    [ "$status" -eq 2 ]
    [[ "$output" == *"requires a name"* ]]
}

@test "multi: missing --skill exits 2" {
    run_script "file://$FIXTURE" "./vendor"

    [ "$status" -eq 2 ]
    [[ "$output" == *"--skill"* ]]
}

@test "multi: old 3-positional signature emits migration message" {
    run_script "file://$FIXTURE" "my-skill" ".agents/skills"

    [ "$status" -eq 2 ]
    [[ "$output" == *"--skill <name> [--skill <name>...] [dest]"* ]]
}

@test "multi: explicit dest overrides default" {
    setup_fake_git
    run_script "file://$FIXTURE" --skill "alpha" --skill "beta" "$BATS_TEST_TMPDIR/vendor"

    [ "$status" -eq 0 ]
    [ -f "$BATS_TEST_TMPDIR/vendor/alpha/SKILL.md" ]
    [ -f "$BATS_TEST_TMPDIR/vendor/beta/SKILL.md" ]
    [ ! -d "$PWD/.agents/skills" ]
}

@test "multi: unknown flag still exits 2" {
    run_script --no-such-flag "file://$FIXTURE" --skill "alpha"

    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown flag"* ]]
}

@test "multi: empty --skill value exits 2" {
    run_script "file://$FIXTURE" --skill "" --skill "alpha"

    [ "$status" -eq 2 ]
    [[ "$output" == *"requires a name"* ]]
}