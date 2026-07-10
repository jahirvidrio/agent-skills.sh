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