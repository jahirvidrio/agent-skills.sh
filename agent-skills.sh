#!/bin/sh
# agent-skills.sh - download an agent skill from a git repository.
# Run with --help for usage, exit codes, and examples.

set -eu

# ---- Configuration ---------------------------------------------------------

VERSION="0.3.0"
CACHE_ROOT="${HOME:?HOME must be set}/.cache/agent-skills"

resolve_agent_dest() {
    _rad_name=$1
    case $_rad_name in
        opencode) printf '%s' '.agents/skills' ;;
        claude-code) printf '%s' '.claude/skills' ;;
        gemini-cli) printf '%s' '.agents/skills' ;;
        *) die 2 "error: unknown agent '$_rad_name' (supported: opencode, claude-code, gemini-cli)" ;;
    esac
}

# ---- Prerequisites ---------------------------------------------------------

command -v git >/dev/null 2>&1 || {
    printf 'error: git is required but not installed\n' >&2
    exit 1
}

# ---- Logging ---------------------------------------------------------------

log() {
    printf '%s\n' "$*" >&2
}

print_banner() {
    # Banner is gated by SHOW_BANNER (set by parse_args when --no-banner
    # is passed) and AGENT_SKILLS_NO_BANNER (env-var override for CI).
    # Using `${VAR:-}` keeps set -u happy when neither is set.
    if [ "${SHOW_BANNER:-1}" -eq 0 ] || [ -n "${AGENT_SKILLS_NO_BANNER:-}" ]; then
        return 0
    fi
    cat <<'EOF' >&2
                   _          _   _ _ _         _
 __ _ __ _ ___ _ _| |_ ___ __| |_(_) | |___  __| |_
/ _` / _` / -_) ' \  _|___(_-< / / | | (_-<_(_-< ' \
\__,_\__, \___|_||_\__|   /__/_\_\_|_|_/__(_)__/_||_|
     |___/


EOF
}

print_version() {
    printf 'agent-skills.sh %s\n' "$VERSION"
}

die() {
    log "$2"
    exit "$1"
}

# prompt_choice <prompt> <max>
# Reads a line from stdin, validates it is an integer in [1, max], echoes
# the chosen number on stdout. Exits 1 on EOF or after 3 invalid attempts.
prompt_choice() {
    _pc_prompt=$1
    _pc_max=$2
    _pc_attempt=0
    _pc_max_attempts=3

    while [ "$_pc_attempt" -lt "$_pc_max_attempts" ]; do
        _pc_attempt=$((_pc_attempt + 1))
        printf '%s' "$_pc_prompt" >&2
        if ! IFS= read -r _pc_answer; then
            printf '\n' >&2
            die 1 "error: no input received"
        fi

        case $_pc_answer in
            '')
                printf '%s\n' "1"
                return 0
                ;;
            *[!0-9]*)
                log "  invalid: please enter a number"
                continue
                ;;
        esac

        if [ "$_pc_answer" -ge 1 ] && [ "$_pc_answer" -le "$_pc_max" ]; then
            printf '%s\n' "$_pc_answer"
            return 0
        fi

        log "  out of range: enter 1-$_pc_max"
    done

    die 1 "error: too many invalid attempts"
}

# ---- Help ------------------------------------------------------------------

usage() {
    cat <<'EOF' >&2
agent-skills.sh - Download an agent skill from a git repository.

Usage:
  agent-skills.sh [options] <repo> --skill <name> [--skill <name>...]

Options:
  -h, --help           show this help and exit
  --version            print version and exit
  --no-banner          suppress the startup banner (also: AGENT_SKILLS_NO_BANNER=1)
  --skill <name>       install <name> from the repo (repeatable, required).
                       Each --skill consumes the next token as the skill name;
                       --skill=<name> is rejected.
  --agent <name>       select destination for opencode, claude-code, or gemini-cli
                       (default: opencode).
  --dest <path>        override the agent destination with a custom path.
  --                   end of options; everything after is positional

Arguments:
  repo       Repository identifier. Recognized forms:
               owner/repo            -> https://github.com/owner/repo.git
               https://host/path     -> used as-is
                git@host:owner/repo   -> used as-is

Destination:
  Agent destinations are relative to the current working directory and are
  created if missing. Each requested skill replaces any prior copy at
  <destination>/<skill-name>.

Cache:
  Repos are cached at $HOME/.cache/agent-skills/<owner>/<repo> and
  reused across runs. Each invocation refreshes the cached clone with
  `git pull --depth=1`. The repo is cloned or pulled exactly once per
  invocation, regardless of how many --skill flags were passed.

Exit codes:
  0  success
  1  generic error
  2  invalid arguments (also: the old <repo> <skill-name> <dest-dir>
     signature, which now exits with a one-line migration message)
  3  skill not found in repo
  4  git clone/pull failed
  5  ambiguous match (multiple skills with the requested name, and
     stdin is not a TTY so the script cannot ask which one to use)

Examples:
  agent-skills.sh owner/repo --skill my-skill
  agent-skills.sh owner/repo --skill skill-1 --skill skill-2 --skill skill-3
  agent-skills.sh owner/repo --skill my-skill --agent claude-code
  agent-skills.sh owner/repo --skill my-skill --dest ./vendor/skills
  agent-skills.sh --no-banner owner/repo --skill my-skill
  agent-skills.sh git@github.com:owner/repo.git --skill my-skill
EOF
    exit "${1:-0}"
}

# ---- Argument validation ---------------------------------------------------

# parse_repo_arg <arg>
# Resolves the repo argument into a clonable URL and a filesystem cache
# key. On success, sets globals REPO_URL and CACHE_KEY. On failure,
# dies with code 2.
parse_repo_arg() {
    _arg=$1

    case $_arg in
        '')
            die 2 "error: repo argument is empty"
            ;;
        git@*|ssh://*|https://*|http://*|file://*)
            extract_owner_repo_from_url "$_arg"
            ;;
        # Short form: owner/repo (exactly one slash, no protocol, no colon)
        */*)
            # Reject empty owner or repo segments (/, /repo, owner/). Compute
            # both segments and require each to be non-empty; the existing
            # */*/* check below still rejects multi-segment paths.
            _owner=${_arg%/*}
            _repo=${_arg#*/}
            if [ -z "$_owner" ] || [ -z "$_repo" ]; then
                die 2 "error: invalid repo '$_arg' (empty owner or repo segment)"
            fi
            case $_arg in
                *:*)
                    die 2 "error: invalid repo '$_arg' (URLs need a protocol)"
                    ;;
                */*/*)
                    die 2 "error: invalid repo '$_arg' (use a full URL for nested paths)"
                    ;;
                *)
                    REPO_URL="https://github.com/${_arg}.git"
                    CACHE_KEY=$_arg
                    ;;
            esac
            ;;
        *)
            die 2 "error: invalid repo '$_arg' (expected owner/repo or a full URL)"
            ;;
    esac
}

# extract_owner_repo_from_url <url>
# Resolves a full git URL and writes the result into globals REPO_URL
# (preserved verbatim) and CACHE_KEY (owner/repo, or local/REPO for
# file:// — usable as a path segment under the cache root). Dies with
# code 2 on a malformed URL. Sets globals instead of printing to keep
# the contract aligned with parse_repo_arg's caller.
extract_owner_repo_from_url() {
    _url=$1

    case $_url in
        # SSH form: git@host:owner/repo[.git]
        git@*)
            # Reject SCP-like URLs with an empty host (git@:path). The SCP-like
            # form requires a non-empty host segment between 'git@' and the
            # first ':'; an empty host collapses to a misleading cache key.
            case $_url in
                git@:*)
                    die 2 "error: invalid repo '$_url' (empty host in scp-like url)"
                    ;;
            esac
            # Reject SCP-like URLs with an embedded port (git@host:port:path).
            # The standard SCP-like form is [user@]host:path and does NOT support
            # ports; use ssh://user@host:port/path when a port is needed.
            case $_url in
                git@*:*:*/*)
                    _after_at=${_url#git@}
                    _mid=${_after_at#*:}
                    case $_mid in
                        [!0-9]*)
                            : # fall through to normal handling
                            ;;
                        *)
                            _host=${_after_at%%:*}
                            die 2 "error: invalid repo '$_url' (git SCP-like URLs cannot embed a port; use ssh://${_host}:PORT/path instead)"
                            ;;
                    esac
                    ;;
            esac
            _path=${_url#*:}
            _path=${_path%.git}
            _path=${_path#/}
            ;;
        # SSH form with protocol: ssh://[user@]host[:port]/owner/repo[.git]
        ssh://*)
            # Reject URLs with empty or port-only authority (ssh:///path,
            # ssh://user@/path, ssh://:PORT/path). The authority segment
            # between 'ssh://' and the first '/' must contain a real host.
            case $_url in
                ssh:///*)
                    die 2 "error: invalid repo '$_url' (empty host in ssh url)"
                    ;;
                ssh://*@/*)
                    die 2 "error: invalid repo '$_url' (empty host after user in ssh url)"
                    ;;
                ssh://:*)
                    die 2 "error: invalid repo '$_url' (port-only host in ssh url)"
                    ;;
            esac
            _path=${_url#ssh://}
            _path=${_path#*/}
            _path=${_path%.git}
            _path=${_path#/}
            ;;
        # HTTPS / HTTP form
        https://*|http://*)
            # Reject URLs with empty or port-only authority (https:///path,
            # https://user@/path, https://:PORT/path). Same shape as the ssh://
            # guard above; per-scheme duplicates because POSIX case patterns
            # don't support scheme alternation inside a nested case.
            case $_url in
                https:///*|http:///*)
                    die 2 "error: invalid repo '$_url' (empty host in url)"
                    ;;
                https://*@/*|http://*@/*)
                    die 2 "error: invalid repo '$_url' (empty host after user in url)"
                    ;;
                https://:*|http://:*)
                    die 2 "error: invalid repo '$_url' (port-only host in url)"
                    ;;
            esac
            _path=${_url#*://}
            _path=${_path#*/}
            _path=${_path%.git}
            ;;
        # file:// form (useful for local testing/debugging). Cache key
        # uses the path basename so different paths cache separately.
        file://*)
            _path=${_url#file://}
            _path=${_path%.git}
            _base=${_path##*/}
            if [ -z "$_base" ] || [ "$_path" = "$_base" ]; then
                die 2 "error: cannot extract repo name from '$_url'"
            fi
            REPO_URL=$_url
            CACHE_KEY="local/$_base"
            return 0
            ;;
        *)
            die 2 "error: cannot extract owner/repo from '$_url'"
            ;;
    esac

    case $_path in
        */*)
            REPO_URL=$_url
            CACHE_KEY=$_path
            ;;
        *)
            die 2 "error: cannot extract owner/repo from '$_url'"
            ;;
    esac
}

# validate_skill_name <name>
# Dies with code 2 on invalid input. Accepted: [A-Za-z0-9._-], no
# leading dot, no path separators, length 1..MAX_SKILL_NAME_LEN.
# The cap protects log lines and copy paths from absurd inputs.
MAX_SKILL_NAME_LEN=100

validate_skill_name() {
    _name=$1

    case $_name in
        '')
            die 2 "error: skill name is empty"
            ;;
        .*)
            die 2 "error: invalid skill name '$_name' (cannot start with a dot)"
            ;;
        */*)
            die 2 "error: invalid skill name '$_name' (no path separators allowed)"
            ;;
        *)
            case $_name in
                *[!A-Za-z0-9._-]*)
                    die 2 "error: invalid skill name '$_name' (only [A-Za-z0-9._-] allowed)"
                    ;;
            esac
            ;;
    esac

    if [ "${#_name}" -gt "$MAX_SKILL_NAME_LEN" ]; then
        die 2 "error: invalid skill name '$_name' (longer than $MAX_SKILL_NAME_LEN chars)"
    fi
}

# ---- Git operations --------------------------------------------------------

# _canonicalize_url <url>
# Echoes the canonical form of <url>. Rules:
# trim trailing whitespace, strip trailing .git, lowercase host only.
_canonicalize_url() {
    _cu_url=$1

    # Trim trailing whitespace (POSIX sed; one-liner).
    _cu_url=$(printf '%s' "$_cu_url" | sed 's/[[:space:]]*$//')
    # Strip trailing .git (no-op if not present).
    _cu_url=${_cu_url%.git}

    # Lowercase the host portion only.
    case $_cu_url in
        *://*)
            _cu_scheme=${_cu_url%%://*}
            _cu_rest=${_cu_url#*://}
            case $_cu_rest in
                *@*) _cu_at="${_cu_rest%%@*}@"; _cu_hp=${_cu_rest#*@} ;;
                *)   _cu_at=""; _cu_hp=$_cu_rest ;;
            esac
            case $_cu_hp in
                */*) _cu_host=${_cu_hp%%/*}; _cu_path=/${_cu_hp#*/} ;;
                *)   _cu_host=$_cu_hp; _cu_path="" ;;
            esac
            _cu_lc=$(printf '%s' "$_cu_host" | tr 'A-Z' 'a-z')
            printf '%s://%s%s%s' "$_cu_scheme" "$_cu_at" "$_cu_lc" "$_cu_path"
            ;;
        *@*:*)
            _cu_pre=${_cu_url%%@*}
            _cu_post=${_cu_url#*@}
            _cu_host=${_cu_post%%:*}
            _cu_path=${_cu_post#*:}
            _cu_lc=$(printf '%s' "$_cu_host" | LC_ALL=C tr '[:upper:]' '[:lower:]')
            printf '%s@%s:%s' "$_cu_pre" "$_cu_lc" "$_cu_path"
            ;;
        *)
            printf '%s' "$_cu_url"
            ;;
    esac
}

# _origin_matches_cached <cached_origin> <requested_url>
# Returns 0 if canonicalized forms match, 1 otherwise. No stderr.
# CALLER MUST wrap in `if`/`while` (set -e would abort on return 1).
_origin_matches_cached() {
    _omc_cached=$1
    _omc_requested=$2
    _omc_c=$(_canonicalize_url "$_omc_cached")
    _omc_r=$(_canonicalize_url "$_omc_requested")
    if [ "$_omc_c" = "$_omc_r" ]; then return 0; fi
    return 1
}

# clone_or_update <cache_dir> <url>: pulls on cache hit, clones on miss.
clone_or_update() {
    _cache_dir=$1
    _url=$2

    if [ -d "$_cache_dir" ]; then
        if [ -d "$_cache_dir/.git" ]; then
            log "Updating cache: $_cache_dir"
            # Verify cached origin matches requested URL before pulling.
            if _cached=$(git -C "$_cache_dir" remote get-url origin 2>/dev/null) \
                && _origin_matches_cached "$_cached" "$_url"; then
                if ! git -C "$_cache_dir" pull --depth=1; then
                    die 4 "error: git pull failed for $_cache_dir"
                fi
                return 0
            fi
            rm -rf -- "$_cache_dir"
        else
            log "error: cache dir '$_cache_dir' exists but is not a git repo"
            log "       remove it manually to continue"
            exit 4
        fi
    fi

    log "Cloning $_url"
    if ! mkdir -p -- "$_cache_dir"; then
        die 1 "error: cannot create cache dir '$_cache_dir'"
    fi

    _co_partial=$_cache_dir
    trap 'rm -rf -- "$_co_partial" 2>/dev/null; trap - EXIT INT TERM' EXIT INT TERM

    if ! git clone --depth=1 "$_url" "$_cache_dir"; then
        trap - EXIT INT TERM
        rm -rf -- "$_cache_dir"
        die 4 "error: git clone failed for $_url"
    fi

    trap - EXIT INT TERM
    return 0
}

# resolve_skills <cache_dir> <name> [<name>...]
# For each <name>, runs find_skill_dir against <cache_dir>. On success,
# prints "<name>\n<path>\n" pairs to stdout in input order. On the
# first failure (missing: exit 3, ambiguous + non-TTY: exit 5),
# exits with the same code WITHOUT printing further pairs. NO copy
# happens here; callers consume the output to drive an atomic apply
# phase. Prompts for ambiguous matches (TTY only) run during resolve,
# at the time the user expects.
resolve_skills() {
    _rs_cache=$1
    shift
    for _rs_name; do
        _rs_dir=$(find_skill_dir "$_rs_cache" "$_rs_name") || exit $?
        printf '%s\n%s\n' "$_rs_name" "$_rs_dir"
    done
}

# find_skill_dir <root> <name>
# Echoes the path of a directory named <name> that directly contains a
# file named SKILL.md, anywhere under <root> (excluding the .git tree).
# Behavior:
#   1 match  -> echoes it silently
#   N match  -> if stdin is a TTY, prompts the user with a numbered list.
#               If stdin is NOT a TTY (pipe, redirect, /dev/null), fails
#               with exit 5 so non-interactive callers (CI, scripts) are
#               forced to disambiguate explicitly.
# Dies 3 if nothing matches; exits 5 if ambiguous in non-interactive
# mode; dies 1 on EOF or too many invalid attempts in interactive mode.
# find_skill_dir <root> <name>
# Orchestrates skill discovery for a given cache root:
#   1. discover all directories named <name> containing SKILL.md
#   2. early-return the single match if there is exactly one
#   3. rank the matches by canonical-location priority
#   4. delegate the TTY-vs-non-TTY disambiguation to pick_skill_match
# Dies 3 if nothing matches; defers all exit codes >= 4 to
# pick_skill_match / prompt_user_for_match.
find_skill_dir() {
    _root=$1
    _name=$2

    _matches=$(discover_matches "$_root" "$_name")
    _count=$(printf '%s\n' "$_matches" | awk 'END{print NR}')

    if [ "$_count" -eq 1 ]; then
        printf '%s\n' "$_matches"
        return 0
    fi

    _sorted=$(rank_matches "$_root" "$_matches")
    pick_skill_match "$_root" "$_name" "$_count" "$_sorted"
}

# pick_skill_match <root> <name> <count> <sorted_matches>
# Disambiguator for find_skill_dir when there is more than one match.
# When stdin is a TTY it prompts via prompt_user_for_match; when
# stdin is NOT a TTY it logs the matches and exits 5 so non-
# interactive callers (CI, scripts) are forced to disambiguate
# explicitly. Echoes the selected match on stdout.
pick_skill_match() {
    _root=$1
    _name=$2
    _count=$3
    _sorted=$4

    if [ ! -t 0 ]; then
        log "error: $_count skills named '$_name' found; \
cannot prompt (stdin is not a TTY)"
        log "  matches:"
        while IFS= read -r _path; do
            log "    ${_path#"$_root"/}"
        done <<EOF
$_sorted
EOF
        log "  re-run with a more specific skill name, or pick one of the above paths manually"
        exit 5
        # Note on heredoc style: <<EOF (no quotes) intentionally
        # expands $_sorted; print_banner and usage use <<'EOF' (quoted)
        # so their bodies stay literal.
    fi

    prompt_user_for_match "$_root" "$_name" "$_count" "$_sorted"
}

# discover_matches <root> <name>
# Echoes newline-separated paths to dirs named <name> that directly
# contain SKILL.md under <root>, excluding the .git tree. Dies with
# code 3 if nothing matches.
discover_matches() {
    _root=$1
    _name=$2

    _matches=$(
        find "$_root" \
            -type d -name ".git" -prune -o \
            -path "*/$_name/SKILL.md" \
            -exec dirname {} +
    )

    if [ -z "$_matches" ]; then
        die 3 "error: skill '$_name' not found \
(no directory named '$_name' containing SKILL.md under $_root)"
    fi

    printf '%s\n' "$_matches"
}

# rank_matches <root> <matches>
# Sort match dirs by relative path shape.
# B1: .X/skills/<skill>; depth 2; parent .X/skills exactly.
# B2: skills/<skill>; depth 1; parent skills exactly.
# B3: <skill> at root; depth 0.
# B4: dotdir paths not in B1.
# B5: other non-dotdir paths.
# Bucket beats depth; then depth, then LC_ALL=C path.
# Awk emits bucket<TAB>depth<TAB>path; sort cuts keys.
# substr() keeps cache-root regex chars inert.
rank_matches() {
    _root=${1%/}
    _plen=${#_root}
    _tab=$(printf '\t') # Safe POSIX tab char delimiter for sort and cut

    printf '%s\n' "$2" | awk -v plen="$_plen" '
    {
        rel = substr($0, plen + 2)
        depth = gsub("/", "/", rel)
        first = rel; sub("/.*", "", first)
        parent = rel

        if (depth == 0) parent = ""
        else sub("/[^/]*$", "", parent)

        dot = (substr(first, 1, 1) == ".")
        bucket = 5

        if (dot && depth == 2 && parent == first "/skills") bucket = 1
        else if (!dot && depth == 1 && parent == "skills") bucket = 2
        else if (depth == 0) bucket = 3
        else if (dot) bucket = 4

        printf "%d\t%d\t%s\n", bucket, depth, $0
    }' | LC_ALL=C sort -t "$_tab" -k1,1n -k2,2n -k3 | cut -d "$_tab" -f3- || {
        die 1 "error: ranking pipeline failed"
    }
}

# prompt_user_for_match <root> <name> <count> <sorted_matches>
# Interactive: prints a numbered list and reads a choice. Echoes the
# selected match on stdout.
prompt_user_for_match() {
    _root=$1
    _name=$2
    _count=$3
    _sorted=$4

    log "Found $_count matches for '$_name':"
    _i=0
    while IFS= read -r _path; do
        _i=$((_i + 1))
        printf '  %d) %s\n' "$_i" "${_path#"$_root"/}" >&2
    done <<EOF
$_sorted
EOF

    _choice=$(prompt_choice "Select [1-$_count] (default: 1): " "$_count")

    _selected=$(printf '%s\n' "$_sorted" | sed -n "${_choice}p")
    log "Selected: ${_selected#"$_root"/}"
    printf '%s\n' "$_selected"
}

# ---- Copy ------------------------------------------------------------------

# strip_dot_git <dir>
# Removes <dir>/.git if present. Skills in their own subdir should never
# carry a .git tree, but cp -Rp can leak it if the source had one.
strip_dot_git() {
    if [ -d "$1/.git" ]; then
        rm -rf -- "$1/.git"
    fi
}

# copy_skill <src_dir> <dest_parent> <name>
# Copies <src_dir> to <dest_parent>/<name>, replacing any existing target.
copy_skill() {
    _src=$1
    _dest_parent=$2
    _name=$3

    _dest="${_dest_parent%/}/$_name"

    if [ ! -d "$_dest_parent" ]; then
        log "Creating destination directory: $_dest_parent"
        if ! mkdir -p -- "$_dest_parent"; then
            die 1 "error: cannot create destination '$_dest_parent'"
        fi
    fi

    if [ -e "$_dest" ]; then
        log "Removing existing $_dest"
        if ! rm -rf -- "$_dest"; then
            die 1 "error: cannot remove existing '$_dest'"
        fi
    fi

    if ! cp -Rp -- "$_src" "$_dest"; then
        die 1 "error: copy failed: $_src -> $_dest"
    fi

    strip_dot_git "$_dest"

    log "Installed: $_dest"
}

# ---- Main ------------------------------------------------------------------

# parse_args <args...>
# Walks the argument list and writes parsed values into globals
# REPO_ARG, SKILL_NAMES (space-separated), DEST_DIR, SHOW_BANNER.
# Skill names match [A-Za-z0-9._-] so a space-separated accumulator
# is unambiguous. Positionals may contain spaces (DEST_DIR is a
# user-supplied path) so they are tracked in three discrete vars.
#
# Flags recognized anywhere in argv:
#   -h, --help         -> usage 0 (exits)
#   --version          -> print_version then exit 0
#   --no-banner        -> sets SHOW_BANNER=0
#   --skill NAME       -> appends NAME to the skill list (repeatable)
#   --skill=NAME       -> REJECTED (exit 2)
#   --                 -> end of flags; rest are pure positional
# Any other -X flag dies with code 2. Dies with code 2 if:
#   - exactly 3 positionals AND no --skill: hard-break message
#   - arity outside {1,2}: usage 2 (stderr contains "Usage:")
#   - SKILL_NAMES empty after the walk
parse_args() {
    _pa_show_banner=1
    _pa_skill_list=""
    _pa_agent=""
    _pa_dest_override=""
    _pa_first_pos=""
    _pa_pos_count=0

    while [ $# -gt 0 ]; do
        case $1 in
            -h|--help)
                usage 0
                ;;
            --version)
                print_version
                exit 0
                ;;
            --no-banner)
                _pa_show_banner=0
                ;;
            --skill=*)
                die 2 "error: --skill=<name> is not supported; use '--skill <name>' (separate tokens)"
                ;;
            --skill)
                shift
                if [ $# -eq 0 ]; then
                    die 2 "error: --skill requires a name"
                fi
                case $1 in
                    ""|--*)
                        die 2 "error: --skill requires a name"
                        ;;
                esac
                if [ -z "$_pa_skill_list" ]; then
                    _pa_skill_list=$1
                else
                    _pa_skill_list="$_pa_skill_list $1"
                fi
                ;;
            --agent=*)
                die 2 "error: --agent=<name> is not supported; use '--agent <name>' (separate tokens)"
                ;;
            --agent)
                shift
                if [ $# -eq 0 ]; then
                    die 2 "error: --agent requires a name"
                fi
                case $1 in
                    ""|--*) die 2 "error: --agent requires a name" ;;
                esac
                resolve_agent_dest "$1" >/dev/null
                _pa_agent=$1
                ;;
            --dest=*)
                die 2 "error: --dest=<path> is not supported; use '--dest <path>' (separate tokens)"
                ;;
            --dest)
                shift
                if [ $# -eq 0 ]; then
                    die 2 "error: --dest requires a path"
                fi
                case $1 in
                    ""|--*) die 2 "error: --dest requires a path" ;;
                esac
                _pa_dest_override=$1
                ;;
            --)
                # End of flags; remaining tokens are pure positionals.
                shift
                while [ $# -gt 0 ]; do
                    _pa_pos_count=$((_pa_pos_count + 1))
                    case $_pa_pos_count in
                        1) _pa_first_pos=$1 ;;
                    esac
                    shift
                done
                break
                ;;
            -*)
                die 2 "error: unknown flag '$1'"
                ;;
            *)
                _pa_pos_count=$((_pa_pos_count + 1))
                case $_pa_pos_count in
                    1) _pa_first_pos=$1 ;;
                    2) _pa_second_pos=$1 ;;
                    3) _pa_third_pos=$1 ;;
                esac
                ;;
        esac
        shift
    done

    # REQ-003 scenario 1: exactly 3 positionals AND zero --skill ->
    # migration message. Tightened from -ge 3 to -eq 3 so that 4+
    # positionals fall through to the usage 2 branch below.
    if [ "$_pa_pos_count" -eq 3 ] && [ -z "$_pa_skill_list" ]; then
        die 2 "error: this signature was removed. Use:
  agent-skills.sh [--agent <name>] <repo> --skill <name> [--skill <name>...] [--dest <path>]"
    fi

    # Only the repository remains positional.
    if [ "$_pa_pos_count" -ne 1 ]; then
        usage 2
    fi

    if [ -z "$_pa_skill_list" ]; then
        die 2 "error: at least one --skill <name> is required"
    fi

    REPO_ARG=$_pa_first_pos
    if [ -n "$_pa_dest_override" ]; then
        DEST_DIR=$_pa_dest_override
    elif [ -n "$_pa_agent" ]; then
        DEST_DIR=$(resolve_agent_dest "$_pa_agent")
    else
        DEST_DIR=$(resolve_agent_dest opencode)
    fi
    AGENT_NAME=${_pa_agent:-opencode}
    SKILL_NAMES=$_pa_skill_list
    SHOW_BANNER=$_pa_show_banner
}

main() {
    parse_args "$@"

    print_banner

    # Validate ALL skill names BEFORE any I/O. validate_skill_name
    # dies 2 on bad input; this preserves atomic-batch semantics
    # (REQ-004 / REQ-006) and avoids a wasted network round-trip.
    # SC2086: SKILL_NAMES is space-separated; skill names match
    # [A-Za-z0-9._-] so word-splitting on whitespace is intentional.
    # shellcheck disable=SC2086
    for _m_name in $SKILL_NAMES; do
        validate_skill_name "$_m_name"
    done

    parse_repo_arg "$REPO_ARG"
    CACHE_DIR="${CACHE_ROOT%/}/$CACHE_KEY"

    log "repo:     $REPO_URL"
    log "cache:    $CACHE_DIR"
    log "agent:    $AGENT_NAME"
    log "dest-dir: $DEST_DIR"
    log "skills:   $SKILL_NAMES"

    # Single remote-fetch for the whole batch (REQ-005).
    clone_or_update "$CACHE_DIR" "$REPO_URL"

    # Atomic resolve-then-apply (fixes JD-001):
    #
    #   1. resolve_skills writes <name>\n<path>\n pairs to a temp
    #      file. find_skill_dir's prompts run here. Failure on any
    #      single name dies BEFORE the apply loop starts, so no copy
    #      has dirtied the destination.
    #   2. The apply loop consumes the pairs via
    #      `while IFS= read -r && read -r`. The `done < file`
    #      redirect (NOT a pipe) keeps us in the same shell, so
    #      state survives across iterations. Each iteration reads
    #      name then path; `&&` short-circuits the loop on EOF.
    #
    # Two-line-per-pair encoding (instead of one-line-per-path)
    # because copy_skill needs both <src> and <name>; we walk
    # them as explicit pairs to avoid parallel-list drift.
    #
    # Atomicity-on-signal gap (JD2-003): SIGINT/TERM delivered while
    # copy_skill is mid-run can leave a partial <dest>/<name>/ tree
    # on disk. The EXIT trap only removes $_pairs_tmp; it cannot
    # roll back a half-written copy. This is a pre-existing
    # limitation inherited from the single-skill main() and is out
    # of scope for this change.
    _pairs_tmp=$(mktemp) || { log "error: cannot create temp file" >&2; exit 1; }
    trap 'rm -f "$_pairs_tmp"' EXIT INT TERM

    # SC2086: SKILL_NAMES is space-separated; word-splitting is intentional.
    # shellcheck disable=SC2086
    resolve_skills "$CACHE_DIR" $SKILL_NAMES > "$_pairs_tmp" || exit $?

    while IFS= read -r _r_name && IFS= read -r _r_src; do
        copy_skill "$_r_src" "$DEST_DIR" "$_r_name"
    done < "$_pairs_tmp"

    log "Done."
}

main "$@"
