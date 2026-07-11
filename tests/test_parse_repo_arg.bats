#!/usr/bin/env bats
# tests/test_parse_repo_arg.bats - covers repo argument parsing.
#
# parse_repo_arg runs BEFORE clone_or_update, and main() prints the
# resolved URL and cache key BEFORE clone_or_update. With a fake git
# in PATH that always succeeds, the script reaches find_skill_dir and
# fails with exit 3 (no SKILL.md). We assert on the log lines that
# main() emits for the resolved URL and cache key -- this indirectly
# verifies parse_repo_arg + extract_owner_repo_from_url behavior.
#
# Cache root is computed from $HOME, so we assert against the same
# value to keep tests hermetic.

load 'lib/test_helper'

@test "short form owner/repo resolves to github https URL" {
    run_script_with_fake_git owner/repo valid-skill .agents/skills
    [ "$status" -eq 3 ]
    [[ "$output" == *"repo:     https://github.com/owner/repo.git"* ]]
    [[ "$output" == *"cache:    $(cache_root)/owner/repo"* ]]
}

@test "owner/repo with .git suffix is accepted" {
    run_script_with_fake_git owner/repo.git valid-skill .agents/skills
    [ "$status" -eq 3 ]
    [[ "$output" == *"repo:     https://github.com/owner/repo.git"* ]]
}

@test "https URL with .git suffix is preserved verbatim" {
    run_script_with_fake_git https://github.com/owner/repo.git valid-skill .agents/skills
    [ "$status" -eq 3 ]
    [[ "$output" == *"repo:     https://github.com/owner/repo.git"* ]]
    [[ "$output" == *"cache:    $(cache_root)/owner/repo"* ]]
}

@test "https URL without .git suffix is accepted" {
    run_script_with_fake_git https://github.com/owner/repo valid-skill .agents/skills
    [ "$status" -eq 3 ]
    [[ "$output" == *"repo:     https://github.com/owner/repo"* ]]
    [[ "$output" == *"cache:    $(cache_root)/owner/repo"* ]]
}

@test "git@host:owner/repo URL is preserved verbatim" {
    run_script_with_fake_git git@github.com:owner/repo.git valid-skill .agents/skills
    [ "$status" -eq 3 ]
    [[ "$output" == *"repo:     git@github.com:owner/repo.git"* ]]
    [[ "$output" == *"cache:    $(cache_root)/owner/repo"* ]]
}

@test "git@host:owner/repo URL without .git suffix works" {
    run_script_with_fake_git git@github.com:owner/repo valid-skill .agents/skills
    [ "$status" -eq 3 ]
    [[ "$output" == *"repo:     git@github.com:owner/repo"* ]]
}

@test "ssh:// URL form is accepted" {
    run_script_with_fake_git ssh://git@github.com/owner/repo.git valid-skill .agents/skills
    [ "$status" -eq 3 ]
    [[ "$output" == *"repo:     ssh://git@github.com/owner/repo.git"* ]]
    [[ "$output" == *"cache:    $(cache_root)/owner/repo"* ]]
}

@test "ssh:// URL with port is accepted" {
    run_script_with_fake_git ssh://git@github.com:22/owner/repo valid-skill .agents/skills
    [ "$status" -eq 3 ]
    [[ "$output" == *"cache:    $(cache_root)/owner/repo"* ]]
}

@test "file:// URL is preserved and cached under local/<basename>" {
    run_script_with_fake_git file:///tmp/some/local-repo.git valid-skill .agents/skills
    [ "$status" -eq 3 ]
    [[ "$output" == *"repo:     file:///tmp/some/local-repo.git"* ]]
    [[ "$output" == *"cache:    $(cache_root)/local/local-repo"* ]]
}

@test "empty repo argument exits 2" {
    run_script "" valid-skill .agents/skills
    [ "$status" -eq 2 ]
}

@test "owner/repo with embedded colon in short form exits 2" {
    # "foo:bar/baz" matches */* AND *:* so it hits the
    # "URLs need a protocol" branch.
    run_script_with_fake_git "foo:bar/baz" my-skill .agents/skills
    [ "$status" -eq 2 ]
    [[ "$output" == *"URLs need a protocol"* ]]
}

@test "owner/repo/repo (too many slashes) exits 2" {
    run_script_with_fake_git owner/repo/extra my-skill .agents/skills
    [ "$status" -eq 2 ]
    [[ "$output" == *"use a full URL for nested paths"* ]]
}

@test "bare name with no slash exits 2" {
    run_script_with_fake_git justaname my-skill .agents/skills
    [ "$status" -eq 2 ]
    [[ "$output" == *"expected owner/repo or a full URL"* ]]
}

@test "host/owner/repo without protocol exits 2 with nested-paths error" {
    # "github.com/owner/repo" has 2 slashes but no protocol, so it
    # matches the "use a full URL for nested paths" branch.
    run_script_with_fake_git "github.com/owner/repo" my-skill .agents/skills
    [ "$status" -eq 2 ]
    [[ "$output" == *"use a full URL for nested paths"* ]]
}