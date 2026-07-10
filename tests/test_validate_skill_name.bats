#!/usr/bin/env bats
# tests/test_validate_skill_name.bats - covers skill-name validation.
#
# validation runs in main() BEFORE parse_repo_arg, so the script
# exits at the validation step. We assert on exit code 2 plus the
# error message text. No git involvement here.

load 'lib/test_helper'

@test "empty skill name exits 2" {
    # Cannot pass empty as a positional arg via the shell, so we
    # invoke via env-var trickery: invoke with a placeholder then
    # verify the script's own validation hits a different code.
    # Instead, use a clearly-invalid name to exercise the path.
    run_script owner/repo "" /tmp/dest
    [ "$status" -eq 2 ]
}

@test "skill name starting with a dot exits 2" {
    run_script_with_fake_git owner/repo ".hidden" /tmp/dest
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot start with a dot"* ]]
}

@test "skill name with a slash exits 2" {
    run_script_with_fake_git owner/repo "bad/name" /tmp/dest
    [ "$status" -eq 2 ]
    [[ "$output" == *"no path separators"* ]]
}

@test "skill name with disallowed characters exits 2" {
    run_script_with_fake_git owner/repo 'bad name!' /tmp/dest
    [ "$status" -eq 2 ]
    [[ "$output" == *"only [A-Za-z0-9._-] allowed"* ]]
}

@test "skill name with shell metacharacters exits 2" {
    run_script_with_fake_git owner/repo 'bad;name' /tmp/dest
    [ "$status" -eq 2 ]
    [[ "$output" == *"only [A-Za-z0-9._-] allowed"* ]]
}

@test "valid skill name passes validation (proceeds to git/find)" {
    # With a fake git that succeeds, the script reaches find_skill_dir
    # which fails with exit 3 because there is no SKILL.md under the
    # (empty) cache dir. The point of this test is to prove validation
    # accepted the name -- exit 3 != 2 means validation passed.
    run_script_with_fake_git owner/repo valid-name /tmp/dest
    [ "$status" -eq 3 ]
}

@test "skill name with dots and hyphens in the middle is valid" {
    run_script_with_fake_git owner/repo "my.skill-v2" /tmp/dest
    [ "$status" -eq 3 ]
}