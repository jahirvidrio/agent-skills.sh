#!/usr/bin/env bats
# tests/test_usage.bats - covers usage(), --help, and arg-count validation.
#
# These tests run agent-skills.sh as a subprocess so the script's
# `set -eu` + `main` flow is exercised end-to-end. They do not need
# git (parsing happens before clone_or_update), so we rely on the
# real git being absent or unused -- the script exits at the usage
# step before touching git.

load 'lib/test_helper'

@test "--help prints usage to stderr and exits 0" {
    run_script --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"agent-skills.sh [options] <repo> --skill <name> [--skill <name>...]"* ]]
    [[ "$output" != *"[dest]"* ]]
    [[ "$output" == *"Exit codes:"* ]]
}

@test "--help documents agent and destination flags without positional dest" {
    run_script --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--agent <name>"* ]]
    [[ "$output" == *"--dest <path>"* ]]
    [[ "$output" != *"dest       Destination directory"* ]]
    [[ "$output" == *"--agent claude-code"* ]]
    [[ "$output" == *"--dest ./vendor/skills"* ]]
}

@test "-h is an alias for --help" {
    run_script -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "no arguments prints usage and exits 2" {
    run_script
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "one argument exits 2 mentioning --skill" {
    run_script only-one-arg
    [ "$status" -eq 2 ]
    [[ "$output" == *"--skill"* ]]
}

@test "two arguments exits 2 mentioning --skill" {
    run_script owner/repo only-two
    [ "$status" -eq 2 ]
    [[ "$output" == *"--skill"* ]]
}

@test "two positionals with --skill are rejected" {
    run_script owner/repo legacy-dest --skill my-skill
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "too many arguments prints usage and exits 2" {
    run_script owner/repo my-skill .agents/skills extra
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "old 3-positional signature exits 2 with migration message" {
    run_script owner/repo my-skill .agents/skills
    [ "$status" -eq 2 ]
    [[ "$output" == *"--agent <name>"* ]]
    [[ "$output" == *"--skill <name>"* ]]
}

@test "--version prints version and exits 0" {
    run_script --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"agent-skills.sh "* ]]
}

@test "--no-banner suppresses the banner but still parses args" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    setup_fake_git

    run_script --no-banner "file://$FIXTURE" --skill "my-skill" --dest "$DEST"

    [ "$status" -eq 0 ]
    # The banner contains the unique substring "__| |_"; with
    # --no-banner passed, the ASCII art must NOT appear.
    [[ "$output" != *"__| |_"* ]]
    # But the "Installed:" log line (printed by copy_skill) must.
    [[ "$output" == *"Installed: $DEST/my-skill"* ]]
}

@test "AGENT_SKILLS_NO_BANNER=1 env var suppresses the banner" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    setup_fake_git
    export AGENT_SKILLS_NO_BANNER=1

    run_script "file://$FIXTURE" --skill "my-skill" --dest "$DEST"

    [ "$status" -eq 0 ]
    [[ "$output" != *"__| |_"* ]]
}

@test "without --no-banner the banner is shown" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    setup_fake_git

    run_script "file://$FIXTURE" --skill "my-skill" --dest "$DEST"

    [ "$status" -eq 0 ]
    [[ "$output" == *"__| |_"* ]]
}

@test "--agent accepts all supported names" {
    FIXTURE=$(fixture_path repo-single)
    cd "$BATS_TEST_TMPDIR"

    setup_fake_git
    run_script "file://$FIXTURE" --skill my-skill --agent claude-code
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installed: .claude/skills/my-skill"* ]]
    [ -f "$PWD/.claude/skills/my-skill/SKILL.md" ]
}

@test "--agent equals form is rejected" {
    run_script owner/repo --skill my-skill --agent=foo
    [ "$status" -eq 2 ]
    [[ "$output" == *"separate tokens"* ]]
}

@test "bare --agent is rejected" {
    run_script owner/repo --skill my-skill --agent
    [ "$status" -eq 2 ]
    [[ "$output" == *"requires a name"* ]]
}

@test "--dest accepts absolute and relative paths" {
    FIXTURE=$(fixture_path repo-single)
    setup_fake_git

    run_script "file://$FIXTURE" --skill my-skill --dest "$BATS_TEST_TMPDIR/absolute"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installed: $BATS_TEST_TMPDIR/absolute/my-skill"* ]]
    [ -f "$BATS_TEST_TMPDIR/absolute/my-skill/SKILL.md" ]
}

@test "--dest equals form is rejected" {
    run_script owner/repo --skill my-skill --dest=foo
    [ "$status" -eq 2 ]
    [[ "$output" == *"separate tokens"* ]]
}

@test "bare --dest is rejected" {
    run_script owner/repo --skill my-skill --dest
    [ "$status" -eq 2 ]
    [[ "$output" == *"requires a path"* ]]
}

@test "unknown flag exits 2" {
    run_script --no-such-flag owner/repo --skill my-skill
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown flag"* ]]
}

@test "-- separator ends option parsing" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    setup_fake_git

    run_script --no-banner --skill my-skill --dest "$DEST" -- "file://$FIXTURE"

    [ "$status" -eq 0 ]
}

@test "--help takes precedence even after other flags" {
    run_script --no-banner --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}