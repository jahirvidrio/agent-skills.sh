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
    [[ "$output" == *"agent-skills.sh <repo> <skill-name> <dest-dir>"* ]]
    [[ "$output" == *"Exit codes:"* ]]
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

@test "one argument prints usage and exits 2" {
    run_script only-one-arg
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "two arguments prints usage and exits 2" {
    run_script owner/repo only-two
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "too many arguments prints usage and exits 2" {
    run_script owner/repo my-skill ./dest extra
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage:"* ]]
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

    run_script --no-banner "file://$FIXTURE" "my-skill" "$DEST"

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

    run_script "file://$FIXTURE" "my-skill" "$DEST"

    [ "$status" -eq 0 ]
    [[ "$output" != *"__| |_"* ]]
}

@test "without --no-banner the banner is shown" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    setup_fake_git

    run_script "file://$FIXTURE" "my-skill" "$DEST"

    [ "$status" -eq 0 ]
    [[ "$output" == *"__| |_"* ]]
}

@test "unknown flag exits 2" {
    run_script --no-such-flag owner/repo my-skill ./dest
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown flag"* ]]
}

@test "-- separator ends option parsing" {
    FIXTURE=$(fixture_path repo-single)
    DEST="$BATS_TEST_TMPDIR/dest"
    setup_fake_git

    run_script -- "file://$FIXTURE" "my-skill" "$DEST"

    [ "$status" -eq 0 ]
}

@test "--help takes precedence even after other flags" {
    run_script --no-banner --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}