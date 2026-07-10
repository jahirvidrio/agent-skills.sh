#!/bin/sh
# agent-skills.sh - Download an agent skill from a git repository.
#
# Usage:
#   agent-skills.sh <repo> <skill-name> <dest-dir>
#
# Arguments:
#   repo       Repository identifier. Recognized forms:
#                owner/repo            -> https://github.com/owner/repo.git
#                https://host/path     -> used as-is
#                git@host:owner/repo   -> used as-is
#   skill-name Name of the skill directory (must directly contain SKILL.md).
#   dest-dir   Destination directory. Created if missing. The skill lands at
#              dest-dir/<skill-name>, replacing any prior copy.
#
# Cache:
#   Repos are cached at $HOME/.cache/agent-skills/<owner>/<repo> and
#   reused across runs. Each invocation refreshes the cached clone with
#   `git pull --depth=1`.
#
# Exit codes:
#   0  success
#   1  generic error
#   2  invalid arguments
#   3  skill not found in repo
#   4  git clone/pull failed
#   5  ambiguous match (multiple skills with the requested name, and
#      stdin is not a TTY so the script cannot ask which one to use)
#
# Examples:
#   agent-skills.sh sickn33/agentic-awesome-skills my-skill ./skills
#   agent-skills.sh https://github.com/owner/repo.git my-skill /tmp/skills
#   agent-skills.sh git@github.com:owner/repo.git my-skill ./skills

set -eu

# ---- Configuration ---------------------------------------------------------

CACHE_ROOT="${HOME:?HOME must be set}/.cache/agent-skills"

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
    cat <<'EOF' >&2
                   _          _   _ _ _         _
 __ _ __ _ ___ _ _| |_ ___ __| |_(_) | |___  __| |_
/ _` / _` / -_) ' \  _|___(_-< / / | | (_-<_(_-< ' \
\__,_\__, \___|_||_\__|   /__/_\_\_|_|_/__(_)__/_||_|
     |___/


EOF
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
                # Empty input (just Enter) -> default to option 1
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
    _code=${1:-0}
    # Print the header comment block. Skip the shebang line; stop at the
    # first blank line; strip the leading "# " (or "#") from each line.
    while IFS= read -r _line; do
        case $_line in
            '#!'*) continue ;;
        esac
        if [ -z "$_line" ]; then
            break
        fi
        case $_line in
            '# '*) printf '%s\n' "${_line#\# }" >&2 ;;
            '#'*)  printf '%s\n' "${_line#\#}"  >&2 ;;
        esac
    done < "$0"
    exit "$_code"
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
            _pfx=$(extract_owner_repo_from_url "$_arg")
            REPO_URL=$(printf '%s\n' "$_pfx" | sed -n '1p')
            CACHE_KEY=$(printf '%s\n' "$_pfx" | sed -n '2p')
            ;;
        # Short form: owner/repo (exactly one slash, no protocol, no colon)
        */*)
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
# Resolves a full git URL into "<url>\n<cache-key>" on stdout. The cache
# key is owner/repo (or local/REPO for file://) — usable as a path
# segment under the cache root. Dies with code 2 on a malformed URL.
extract_owner_repo_from_url() {
    _url=$1

    case $_url in
        # SSH form: git@host:owner/repo[.git]
        git@*)
            _path=${_url#*:}
            _path=${_path%.git}
            _path=${_path#/}
            ;;
        # SSH form with protocol: ssh://[user@]host[:port]/owner/repo[.git]
        ssh://*)
            _path=${_url#ssh://}
            _path=${_path#*/}
            _path=${_path%.git}
            _path=${_path#/}
            ;;
        # HTTPS / HTTP form
        https://*|http://*)
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
            printf '%s\n%s\n' "$_url" "local/$_base"
            return 0
            ;;
        *)
            die 2 "error: cannot extract owner/repo from '$_url'"
            ;;
    esac

    case $_path in
        */*)
            printf '%s\n%s\n' "$_url" "$_path"
            ;;
        *)
            die 2 "error: cannot extract owner/repo from '$_url'"
            ;;
    esac
}

# validate_skill_name <name>
# Dies with code 2 on invalid input. Accepted: [A-Za-z0-9._-], no
# leading dot, no path separators.
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
}

# ---- Git operations --------------------------------------------------------

# clone_or_update <cache_dir> <url>
# If <cache_dir>/.git exists, runs git pull --depth=1. Otherwise clones to
# a temp dir inside the cache parent and moves the result into place.
clone_or_update() {
    _cache_dir=$1
    _url=$2

    if [ -d "$_cache_dir" ]; then
        if [ -d "$_cache_dir/.git" ]; then
            log "Updating cache: $_cache_dir"
            if ! git -C "$_cache_dir" pull --depth=1; then
                die 4 "error: git pull failed for $_cache_dir"
            fi
            return 0
        fi
        log "error: cache dir '$_cache_dir' exists but is not a git repo"
        log "       remove it manually to continue"
        exit 4
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

    _matches=$(find "$_root" \
        -path "*/$_name/SKILL.md" \
        -not -path "*/.git/*" \
        -exec dirname {} +)
    if [ -z "$_matches" ]; then
        die 3 "error: skill '$_name' not found \
(no directory named '$_name' containing SKILL.md under $_root)"
    fi
    printf '%s\n' "$_matches"
}

# rank_matches <root> <matches>
# Sorts <matches> by canonical-location priority, then alphabetically
# within each bucket:
#   1) .agents/    2) .opencode/    3) .claude/    4) skills/    5) other
# Echoes the sorted list on stdout. Dies with code 1 on pipeline failure.
# Uses substr() instead of sub() so cache paths containing regex
# metacharacters don't break ranking.
rank_matches() {
    _root=$1
    _plen=${#_root}
    printf '%s\n' "$2" | awk -v plen="$_plen" '
        {
            rel = substr($0, plen + 2)
            first = rel
            sub("/.*", "", first)
            pri = 5
            if (first == ".agents")   pri = 1
            else if (first == ".opencode") pri = 2
            else if (first == ".claude")   pri = 3
            else if (first == "skills")    pri = 4
            printf "%d\t%s\n", pri, $0
        }' | sort -k1,1n | cut -f2- || die 1 "error: ranking pipeline failed"
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

    # Defensive: strip any .git that may have leaked (shouldn't happen for
    # skills in their own subdir, but cheap to verify).
    if [ -d "$_dest/.git" ]; then
        rm -rf -- "$_dest/.git"
    fi

    log "Installed: $_dest"
}

# ---- Main ------------------------------------------------------------------

main() {
    print_banner

    case ${1:-} in
        -h|--help)
            usage 0
            ;;
    esac

    if [ $# -ne 3 ]; then
        usage 2
    fi

    REPO_ARG=$1
    SKILL_NAME=$2
    DEST_DIR=$3

    validate_skill_name "$SKILL_NAME"
    parse_repo_arg "$REPO_ARG"

    CACHE_DIR="${CACHE_ROOT%/}/$CACHE_KEY"

    log "repo:     $REPO_URL"
    log "skill:    $SKILL_NAME"
    log "cache:    $CACHE_DIR"
    log "dest-dir: $DEST_DIR"

    clone_or_update "$CACHE_DIR" "$REPO_URL"
    SKILL_DIR=$(find_skill_dir "$CACHE_DIR" "$SKILL_NAME")
    copy_skill "$SKILL_DIR" "$DEST_DIR" "$SKILL_NAME"

    log "Done."
}

main "$@"
