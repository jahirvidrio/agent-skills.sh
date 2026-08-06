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

@test "agent dest helper: known agents map to expected destinations" {
    _rad_src=$(awk '/^resolve_agent_dest\(/,/^}/' "$TARGET")
    _rad_script="$BATS_TEST_TMPDIR/resolve_agent_dest_test.sh"
    {
        printf 'die() { printf "%%s\\n" "$2" >&2; exit "$1"; }\n'
        printf '%s\n' "$_rad_src"
        printf 'resolve_agent_dest "$1"\n'
    } > "$_rad_script"

    run sh "$_rad_script" opencode
    [ "$status" -eq 0 ]
    [ "$output" = ".agents/skills" ]

    run sh "$_rad_script" claude-code
    [ "$status" -eq 0 ]
    [ "$output" = ".claude/skills" ]

    run sh "$_rad_script" gemini-cli
    [ "$status" -eq 0 ]
    [ "$output" = ".agents/skills" ]
}

@test "agent dest helper: unknown agent exits 2 and lists supported agents" {
    _rad_src=$(awk '/^resolve_agent_dest\(/,/^}/' "$TARGET")
    _rad_script="$BATS_TEST_TMPDIR/resolve_agent_dest_unknown_test.sh"
    {
        printf 'die() { printf "%%s\\n" "$2" >&2; exit "$1"; }\n'
        printf '%s\n' "$_rad_src"
        printf 'resolve_agent_dest "$1"\n'
    } > "$_rad_script"

    run sh "$_rad_script" unknown

    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown agent 'unknown'"* ]]
    [[ "$output" == *"supported: opencode, claude-code, gemini-cli"* ]]
}

# ---- Happy-path coverage --------------------------------------------------

@test "multi: single --skill copies one skill to default dest" {
    setup_fake_git
    run_script "file://$FIXTURE" --skill "alpha"

    [ "$status" -eq 0 ]
    [ -f "$PWD/.agents/skills/alpha/SKILL.md" ]
    [[ "$output" == *"Installed: .agents/skills/alpha"* ]]
}

@test "multi: three --skill flags install in order" {
    setup_fake_git
    run_script "file://$FIXTURE" --skill "alpha" --skill "beta" --skill "gamma"

    [ "$status" -eq 0 ]
    [ -f "$PWD/.agents/skills/alpha/SKILL.md" ]
    [ -f "$PWD/.agents/skills/beta/SKILL.md" ]
    [ -f "$PWD/.agents/skills/gamma/SKILL.md" ]
    [[ "$output" == *"Installed: .agents/skills/alpha"* ]]
    [[ "$output" == *"Installed: .agents/skills/beta"* ]]
    [[ "$output" == *"Installed: .agents/skills/gamma"* ]]
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

    DEST="$BATS_TEST_TMPDIR/dest"
    run_script "file://$FIXTURE" --skill "my-skill" --dest "$DEST" </dev/null

    [ "$status" -eq 5 ]
    [ ! -d "$DEST" ]
    [ ! -d "$PWD/.agents/skills" ]
    [[ "$output" == *".agents/my-skill"* ]]
    [[ "$output" == *"skills named 'my-skill' found"* ]]
}

@test "multi: N-matches + TTY in multi-skill -> prompts and default-1 selects bucket-1" {
    FIXTURE=$(fixture_path repo-multi)
    setup_fake_git
    export FAKE_GIT_ORIGIN="file://$FIXTURE"

    # Part A: prompt emission. macOS BSD `script -q typescript
    # CMD` allocates a PTY for CMD; pick_skill_match sees [ -t 0 ]
    # true and runs the prompt path.
    TYPESCRIPT="$BATS_TEST_TMPDIR/typescript"
    OUTPUT=$(script -q "$TYPESCRIPT" "$TARGET" "file://$FIXTURE" --skill "my-skill" "$BATS_TEST_TMPDIR/dest" 2>&1 || true)
    rm -f "$TYPESCRIPT"
    [[ "$OUTPUT" == *"Found 4 matches"* ]]
    [[ "$OUTPUT" == *"Select [1-4]"* ]]

    # Part B: default-1 contract. prompt_choice (agent-skills.sh:55-89)
    # must echo "1" on stdout when stdin delivers an empty line.
    # We extract the function via awk and run it in a sub-bash with
    # stubbed die/log/read helpers. Sourcing the full script is
    # unsafe because of `set -eu` + `main "$@"` at the script's
    # tail. macOS BSD `script` does NOT propagate stdin through the
    # PTY to the child, so programmatic end-to-end selection is
    # unreliable on macOS; this unit proof pins the default-1 logic
    # that drives the install path in the TTY branch.
    _pc_src=$(awk '/^prompt_choice\(/,/^}/' "$TARGET")
    _pc_script="$BATS_TEST_TMPDIR/prompt_choice_test.sh"
    {
        printf 'die() { printf "%%s\\n" "$2" >&2; exit "$1"; }\n'
        printf 'log() { printf "%%s\\n" "$*" >&2; }\n'
        printf 'read() { REPLY=""; return 0; }\n'
        printf '%s\n' "$_pc_src"
        printf 'prompt_choice "Select [1-4] (default: 1): " 4\n'
    } > "$_pc_script"
    OUT=$(bash "$_pc_script")
    rm -f "$_pc_script"
    [ "$OUT" = "1" ]
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
    [[ "$output" == *"--agent <name>"* ]]
    [[ "$output" == *"--skill <name>"* ]]
}

@test "multi: --dest overrides a valid agent and unknown agent still fails" {
    setup_fake_git
    run_script "file://$FIXTURE" --skill alpha --agent claude-code --dest "$BATS_TEST_TMPDIR/override"

    [ "$status" -eq 0 ]
    [ -f "$BATS_TEST_TMPDIR/override/alpha/SKILL.md" ]
    [ ! -d "$PWD/.claude/skills" ]

    run_script "file://$FIXTURE" --skill alpha --agent unknown --dest "$BATS_TEST_TMPDIR/rejected"
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown agent"* ]]
    [ ! -d "$BATS_TEST_TMPDIR/rejected" ]
}

@test "multi: explicit dest overrides default" {
    setup_fake_git
    run_script "file://$FIXTURE" --skill "alpha" --skill "beta" --dest "$BATS_TEST_TMPDIR/vendor"

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