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

@test "git@host:port:path is rejected with exit 2" {
    run_script_with_fake_git "git@github.com:22:owner/repo.git" valid-skill .agents/skills
    [ "$status" -eq 2 ]
    [[ "$output" == *"ssh://"* ]]
    [[ "$output" == *"git@github.com:22:owner/repo.git"* ]]
}

@test "git@host:port:path without .git suffix is also rejected" {
    run_script_with_fake_git "git@github.com:22:owner/repo" valid-skill .agents/skills
    [ "$status" -eq 2 ]
    [[ "$output" == *"ssh://"* ]]
}

@test "git@host:port:multi/segment/path is rejected" {
    run_script_with_fake_git "git@gitlab.example.org:2222:group/sub/proj.git" valid-skill .agents/skills
    [ "$status" -eq 2 ]
    [[ "$output" == *"ssh://"* ]]
}

@test "git@host:non_numeric:rest is NOT rejected as port (path flows through)" {
    # "abc" is not digits, so the port-leak guard must NOT fire. The resulting
    # CACHE_KEY is "abc:owner/repo" (it will then fail with exit 3 from
    # find_skill_dir / no SKILL.md, NOT with exit 2 from the port guard).
    run_script_with_fake_git "git@github.com:abc:owner/repo" valid-skill .agents/skills
    [ "$status" -eq 3 ]
    [[ "$output" == *"cache:    $(cache_root)/abc:owner/repo"* ]]
}

@test "ssh:// URL with port works (audit test)" {
    run_script_with_fake_git "ssh://git@github.com:22/owner/repo.git" valid-skill .agents/skills
    [ "$status" -eq 3 ]
    [[ "$output" == *"cache:    $(cache_root)/owner/repo"* ]]
}

@test "https URL with port works (audit test)" {
    run_script_with_fake_git "https://github.com:8443/owner/repo.git" valid-skill .agents/skills
    [ "$status" -eq 3 ]
    [[ "$output" == *"cache:    $(cache_root)/owner/repo"* ]]
}

@test "http URL with port works (audit test)" {
    run_script_with_fake_git "http://github.com:8080/owner/repo.git" valid-skill .agents/skills
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

# ---------------------------------------------------------------------------
# Empty-host / empty-segment rejection guards
# ---------------------------------------------------------------------------
# The guards added in extract_owner_repo_from_url and parse_repo_arg must
# reject empty or port-only authority across all accepted protocols before
# the parameter-expansion strips erase the evidence. Each test below pins
# one input from the audit and asserts exit 2 + arm-specific diagnostic.
# Pattern mirrors the existing port-leak tests above.

@test "git@:owner/repo is rejected with empty-host diagnostic (scp-like)" {
    run_script_with_fake_git "git@:owner/repo" my-skill .agents/skills
    [ "$status" -eq 2 ]
    [[ "$output" == *"empty host in scp-like url"* ]]
    [[ "$output" == *"git@:owner/repo"* ]]
}

@test "ssh:///owner/repo is rejected with empty-host diagnostic" {
    run_script_with_fake_git "ssh:///owner/repo" my-skill .agents/skills
    [ "$status" -eq 2 ]
    [[ "$output" == *"empty host in ssh url"* ]]
    [[ "$output" == *"ssh:///owner/repo"* ]]
}

@test "ssh://:PORT/owner/repo is rejected with port-only-host diagnostic" {
    run_script_with_fake_git "ssh://:22/owner/repo" my-skill .agents/skills
    [ "$status" -eq 2 ]
    [[ "$output" == *"port-only host in ssh url"* ]]
    [[ "$output" == *"ssh://:22/owner/repo"* ]]
}

@test "ssh://user@/owner/repo is rejected with empty-host-after-user diagnostic" {
    run_script_with_fake_git "ssh://git@/owner/repo" my-skill .agents/skills
    [ "$status" -eq 2 ]
    [[ "$output" == *"empty host after user in ssh url"* ]]
    [[ "$output" == *"ssh://git@/owner/repo"* ]]
}

@test "https:///owner/repo is rejected with empty-host diagnostic" {
    run_script_with_fake_git "https:///owner/repo" my-skill .agents/skills
    [ "$status" -eq 2 ]
    [[ "$output" == *"empty host in url"* ]]
    [[ "$output" == *"https:///owner/repo"* ]]
}

@test "http:///owner/repo is rejected with empty-host diagnostic" {
    run_script_with_fake_git "http:///owner/repo" my-skill .agents/skills
    [ "$status" -eq 2 ]
    [[ "$output" == *"empty host in url"* ]]
    [[ "$output" == *"http:///owner/repo"* ]]
}

@test "https://:PORT/owner/repo is rejected with port-only-host diagnostic" {
    run_script_with_fake_git "https://:443/owner/repo" my-skill .agents/skills
    [ "$status" -eq 2 ]
    [[ "$output" == *"port-only host in url"* ]]
    [[ "$output" == *"https://:443/owner/repo"* ]]
}

@test "/ alone is rejected with empty-segment diagnostic" {
    run_script_with_fake_git "/" my-skill .agents/skills
    [ "$status" -eq 2 ]
    [[ "$output" == *"empty owner or repo segment"* ]]
}

@test "/repo (empty owner) is rejected with empty-segment diagnostic" {
    run_script_with_fake_git "/repo" my-skill .agents/skills
    [ "$status" -eq 2 ]
    [[ "$output" == *"empty owner or repo segment"* ]]
}

@test "owner/ (empty repo) is rejected with empty-segment diagnostic" {
    run_script_with_fake_git "owner/" my-skill .agents/skills
    [ "$status" -eq 2 ]
    [[ "$output" == *"empty owner or repo segment"* ]]
}

# ---------------------------------------------------------------------------
# Lock tests: pin the two deferred scenarios from the audit (obs #565)
# ---------------------------------------------------------------------------

@test "git@host:owner/sub/proj (multi-segment path) parses successfully" {
    # Multi-segment SCP-like paths (group/sub/proj) MUST keep working.
    # Locked here because the existing port-leak guard sits in the same arm.
    run_script_with_fake_git "git@github.com:owner/sub/proj" valid-skill .agents/skills
    [ "$status" -eq 3 ]
    [[ "$output" == *"repo:     git@github.com:owner/sub/proj"* ]]
    [[ "$output" == *"cache:    $(cache_root)/owner/sub/proj"* ]]
}

@test "git@host: (missing path) is rejected with cannot-extract diagnostic" {
    # The trailing */*) fallthrough at the end of extract_owner_repo_from_url
    # already exits 2 on this input; lock it here so future refactors don't
    # break the existing normative behavior.
    run_script_with_fake_git "git@host:" my-skill .agents/skills
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot extract owner/repo from 'git@host:'"* ]]
}

# ---------------------------------------------------------------------------
# file:/// non-regression (RFC 8089 permits empty authority)
# ---------------------------------------------------------------------------

@test "file:///local/path (without .git) is preserved under local/<basename>" {
    # Sibling to the existing line-115 test (which uses .git suffix). Both
    # forms MUST keep working; the empty-host guards added above must not
    # touch the file:// arm.
    run_script_with_fake_git "file:///tmp/some/local-repo" valid-skill .agents/skills
    [ "$status" -eq 3 ]
    [[ "$output" == *"repo:     file:///tmp/some/local-repo"* ]]
    [[ "$output" == *"cache:    $(cache_root)/local/local-repo"* ]]
}