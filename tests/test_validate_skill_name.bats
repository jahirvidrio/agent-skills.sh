#!/usr/bin/env bats
# tests/test_validate_skill_name.bats - covers skill-name validation.
#
# Validation runs in main() BEFORE parse_repo_arg, so the script
# exits at the validation step. We assert on exit code 2 plus the
# error message text. No git involvement here.

load 'lib/test_helper'

setup() {
    cd "$BATS_TEST_TMPDIR"
}

@test "empty skill name exits 2" {
    # Cannot pass empty as a positional arg via the shell, so we
    # use the --skill flag with empty value: parse_args' inner
    # check catches the empty case before validate_skill_name runs.
    run_script owner/repo --skill ""
    [ "$status" -eq 2 ]
    [[ "$output" == *"requires a name"* ]]
}

@test "skill name starting with a dot exits 2" {
    run_script_with_fake_git owner/repo --skill ".hidden"
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot start with a dot"* ]]
}

@test "skill name with a slash exits 2" {
    run_script_with_fake_git owner/repo --skill "bad/name"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no path separators"* ]]
}

@test "skill name with disallowed characters exits 2" {
    run_script_with_fake_git owner/repo --skill "bad name!"
    [ "$status" -eq 2 ]
    [[ "$output" == *"only [A-Za-z0-9._-] allowed"* ]]
}

@test "skill name with shell metacharacters exits 2" {
    run_script_with_fake_git owner/repo --skill "bad;name"
    [ "$status" -eq 2 ]
    [[ "$output" == *"only [A-Za-z0-9._-] allowed"* ]]
}

@test "valid skill name passes validation (proceeds to git/find)" {
    # With a fake git that succeeds, the script reaches find_skill_dir
    # which fails with exit 3 because there is no SKILL.md under the
    # (empty) cache dir. The point of this test is to prove validation
    # accepted the name -- exit 3 != 2 means validation passed.
    run_script_with_fake_git owner/repo --skill "valid-name"
    [ "$status" -eq 3 ]
}

@test "skill name with dots and hyphens in the middle is valid" {
    run_script_with_fake_git owner/repo --skill "my.skill-v2"
    [ "$status" -eq 3 ]
}

@test "skill name longer than 100 chars exits 2" {
    LONG=$(printf 'a%.0s' {1..101})
    run_script_with_fake_git owner/repo --skill "$LONG"
    [ "$status" -eq 2 ]
    [[ "$output" == *"longer than 100 chars"* ]]
}

@test "skill name exactly 100 chars is accepted" {
    EXACT=$(printf 'a%.0s' {1..100})
    run_script_with_fake_git owner/repo --skill "$EXACT"
    [ "$status" -eq 3 ]
}