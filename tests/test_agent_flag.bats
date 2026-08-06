#!/usr/bin/env bats
# tests/test_agent_flag.bats - lock-down coverage for the --agent and
# --dest flags introduced by the agent-flag change.
#
# Each @test below pins one row of the agent-flag behavior matrix from
# the spec. The matrix covers:
#
#   - the three known agent->destination mappings
#   - the default (omitted --agent -> opencode)
#   - validation: unknown, missing value, equals-form (--agent=, --dest=)
#   - multi-skill combined with --agent
#   - order independence for --agent (before/after <repo>, after --skill)
#   - --dest override (alone; with --agent; agent-still-validated)
#
# Every test runs the script end-to-end against a real fixture via
# file:// (no network). Tests that need a populated destination state
# use setup_fake_git. Default-destination assertions cd to
# $BATS_TEST_TMPDIR (mirrors test_multi_skill.bats JD-006) so they
# stay hermetic across the suite.

load 'lib/test_helper'

FIXTURE=$(fixture_path repo-multi-skills)

setup() {
    cd "$BATS_TEST_TMPDIR"
}

# ===========================================================================
# Mapped agents install at their declared destinations.
# ===========================================================================

@test "agent: --agent opencode installs at .agents/skills/<name>" {
    setup_fake_git
    run_script "file://$FIXTURE" --skill alpha --agent opencode
    [ "$status" -eq 0 ]
    [ -f "$PWD/.agents/skills/alpha/SKILL.md" ]
    [[ "$output" == *"Installed: .agents/skills/alpha"* ]]
}

@test "agent: --agent claude-code installs at .claude/skills/<name>" {
    setup_fake_git
    run_script "file://$FIXTURE" --skill alpha --agent claude-code
    [ "$status" -eq 0 ]
    [ -f "$PWD/.claude/skills/alpha/SKILL.md" ]
    [[ "$output" == *"Installed: .claude/skills/alpha"* ]]
}

@test "agent: --agent gemini-cli installs at .agents/skills/<name>" {
    setup_fake_git
    run_script "file://$FIXTURE" --skill alpha --agent gemini-cli
    [ "$status" -eq 0 ]
    [ -f "$PWD/.agents/skills/alpha/SKILL.md" ]
    [[ "$output" == *"Installed: .agents/skills/alpha"* ]]
}

# ===========================================================================
# Default-agent contract: omitting --agent resolves to opencode (REGRESSION
# guard for the 12 default-destination assertions in test_multi_skill.bats).
# ===========================================================================

@test "agent: --agent omitted defaults to opencode and installs at .agents/skills/<name>" {
    setup_fake_git
    run_script "file://$FIXTURE" --skill alpha
    [ "$status" -eq 0 ]
    [ -f "$PWD/.agents/skills/alpha/SKILL.md" ]
    [[ "$output" == *"agent:    opencode"* ]]
}

# ===========================================================================
# Validation: unknown agent, missing value, equals-form rejects with
# specific substrings so error messages stay diagnosable.
# ===========================================================================

@test "agent: --agent foo (unknown) exits 2 with supported list" {
    run_script "file://$FIXTURE" --skill alpha --agent foo
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown agent 'foo'"* ]]
    [[ "$output" == *"supported: opencode, claude-code, gemini-cli"* ]]
}

@test "agent: bare --agent (no value) exits 2 with requires-a-name message" {
    run_script "file://$FIXTURE" --skill alpha --agent
    [ "$status" -eq 2 ]
    [[ "$output" == *"requires a name"* ]]
}

@test "agent: --agent=foo (equals form) exits 2 with separate-tokens message" {
    run_script "file://$FIXTURE" --skill alpha --agent=foo
    [ "$status" -eq 2 ]
    [[ "$output" == *"separate tokens"* ]]
}

@test "dest: --dest=foo (equals form) exits 2 with separate-tokens message" {
    run_script "file://$FIXTURE" --skill alpha --dest=foo
    [ "$status" -eq 2 ]
    [[ "$output" == *"separate tokens"* ]]
}

@test "dest: bare --dest (no value) exits 2 with requires-a-path message" {
    run_script "file://$FIXTURE" --skill alpha --dest
    [ "$status" -eq 2 ]
    [[ "$output" == *"requires a path"* ]]
}

# ===========================================================================
# Multi-skill combined with --agent: every requested --skill lands under
# the agent-resolved destination.
# ===========================================================================

@test "agent: --agent opencode with multiple --skill installs all in .agents/skills/<name>" {
    setup_fake_git
    run_script "file://$FIXTURE" --agent opencode --skill alpha --skill beta
    [ "$status" -eq 0 ]
    [ -f "$PWD/.agents/skills/alpha/SKILL.md" ]
    [ -f "$PWD/.agents/skills/beta/SKILL.md" ]
}

# ===========================================================================
# Order independence for --agent: walker accepts it before <repo>,
# after <repo>, and after --skill without reordering tokens.
# ===========================================================================

@test "agent: --agent before <repo> is accepted" {
    setup_fake_git
    run_script --agent opencode "file://$FIXTURE" --skill alpha
    [ "$status" -eq 0 ]
    [ -f "$PWD/.agents/skills/alpha/SKILL.md" ]
}

@test "agent: --agent after <repo> is accepted" {
    setup_fake_git
    run_script "file://$FIXTURE" --agent opencode --skill alpha
    [ "$status" -eq 0 ]
    [ -f "$PWD/.agents/skills/alpha/SKILL.md" ]
}

@test "agent: --agent after --skill is accepted" {
    setup_fake_git
    run_script "file://$FIXTURE" --skill alpha --agent opencode
    [ "$status" -eq 0 ]
    [ -f "$PWD/.agents/skills/alpha/SKILL.md" ]
}

# ===========================================================================
# --dest override contract:
#   - alone: skills land at the literal user path
#   - + --agent: override wins; --agent is still validated for typos
# ===========================================================================

@test "dest: --dest alone installs at the user path" {
    setup_fake_git
    run_script "file://$FIXTURE" --skill alpha --dest "$BATS_TEST_TMPDIR/dest"
    [ "$status" -eq 0 ]
    [ -f "$BATS_TEST_TMPDIR/dest/alpha/SKILL.md" ]
    [ ! -d "$PWD/.agents/skills" ]
}

@test "dest: --dest overrides --agent (claude-code ignored for path resolution; .claude/skills not created)" {
    setup_fake_git
    run_script "file://$FIXTURE" --skill alpha --agent claude-code --dest "$BATS_TEST_TMPDIR/override"
    [ "$status" -eq 0 ]
    [ -f "$BATS_TEST_TMPDIR/override/alpha/SKILL.md" ]
    [ ! -d "$PWD/.claude/skills" ]
}

@test "dest: --dest with invalid --agent still fails (agent validated even when overridden)" {
    run_script "file://$FIXTURE" --skill alpha --agent foo --dest "$BATS_TEST_TMPDIR/rejected"
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown agent"* ]]
    [ ! -d "$BATS_TEST_TMPDIR/rejected" ]
}
