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
            log "error: no input received"
            exit 1
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

    log "error: too many invalid attempts"
    exit 1
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
# Resolves the repo argument into a clonable URL and a cache subpath
# (owner/repo). On success, sets globals REPO_URL and CACHE_SUBPATH.
# On failure, exits with code 2.
parse_repo_arg() {
    _arg=$1

    case $_arg in
        '')
            log "error: repo argument is empty"
            exit 2
            ;;
        # SSH form: git@host:owner/repo[.git]
        git@*)
            _rest=${_arg#*:}
            _path=${_rest%.git}
            _path=${_path#/}
            case $_path in
                */*)
                    REPO_URL=$_arg
                    CACHE_SUBPATH=$_path
                    ;;
                *)
                    log "error: cannot extract owner/repo from '$_arg'"
                    exit 2
                    ;;
            esac
            ;;
        # SSH form with protocol: ssh://[user@]host[:port]/owner/repo[.git]
        ssh://*)
            _rest=${_arg#ssh://}
            _path=${_rest#*/}
            _path=${_path%.git}
            _path=${_path#/}
            case $_path in
                */*)
                    REPO_URL=$_arg
                    CACHE_SUBPATH=$_path
                    ;;
                *)
                    log "error: cannot extract owner/repo from '$_arg'"
                    exit 2
                    ;;
            esac
            ;;
        # HTTPS / HTTP form
        https://*|http://*)
            _path=${_arg#*://}
            _path=${_path#*/}
            _path=${_path%.git}
            case $_path in
                */*)
                    REPO_URL=$_arg
                    CACHE_SUBPATH=$_path
                    ;;
                *)
                    log "error: cannot extract owner/repo from '$_arg'"
                    exit 2
                    ;;
            esac
            ;;
        # file:// form (useful for local testing/debugging). Cache key is
        # derived from the path's basename so different paths still cache
        # separately.
        file://*)
            _path=${_arg#file://}
            _path=${_path%.git}
            _base=${_path##*/}
            if [ -z "$_base" ] || [ "$_path" = "$_base" ]; then
                log "error: cannot extract repo name from '$_arg'"
                exit 2
            fi
            REPO_URL=$_arg
            CACHE_SUBPATH="local/$_base"
            ;;
        # Short form: owner/repo (exactly one slash, no protocol, no colon)
        */*)
            case $_arg in
                *:*)
                    log "error: invalid repo '$_arg' (URLs need a protocol)"
                    exit 2
                    ;;
                */*/*)
                    log "error: invalid repo '$_arg' \
(use a full URL for nested paths)"
                    exit 2
                    ;;
                *)
                    REPO_URL="https://github.com/${_arg}.git"
                    CACHE_SUBPATH=$_arg
                    ;;
            esac
            ;;
        *)
            log "error: invalid repo '$_arg' \
(expected owner/repo or a full URL)"
            exit 2
            ;;
    esac
}

# validate_skill_name <name>
# Exits with code 2 on invalid input. Accepted: [A-Za-z0-9._-], no leading
# dot, no path separators.
validate_skill_name() {
    _name=$1

    case $_name in
        '')
            log "error: skill name is empty"
            exit 2
            ;;
        .*)
            log "error: invalid skill name '$_name' (cannot start with a dot)"
            exit 2
            ;;
        */*)
            log "error: invalid skill name '$_name' (no path separators allowed)"
            exit 2
            ;;
        *)
            case $_name in
                *[!A-Za-z0-9._-]*)
                    log "error: invalid skill name '$_name' \
(only [A-Za-z0-9._-] allowed)"
                    exit 2
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
                log "error: git pull failed for $_cache_dir"
                exit 4
            fi
            return 0
        fi
        log "error: cache dir '$_cache_dir' exists but is not a git repo"
        log "       remove it manually to continue"
        exit 4
    fi

    log "Cloning $_url"
    if ! mkdir -p -- "$_cache_dir"; then
        log "error: cannot create cache dir '$_cache_dir'"
        exit 1
    fi

    if ! git clone --depth=1 "$_url" "$_cache_dir"; then
        # Clone failed mid-way: clean up the partial dir so the next run
        # can retry cleanly.
        rm -rf -- "$_cache_dir"
        log "error: git clone failed for $_url"
        exit 4
    fi
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
# Exits 3 if nothing matches; exits 5 if ambiguous in non-interactive
# mode; exits 1 on EOF or too many invalid attempts in interactive mode.
find_skill_dir() {
    _root=$1
    _name=$2

    _matches=$(find "$_root" \
        -path "*/$_name/SKILL.md" \
        -not -path "*/.git/*" \
        -exec dirname {} +)

    if [ -z "$_matches" ]; then
        log "error: skill '$_name' not found \
(no directory named '$_name' containing SKILL.md under $_root)"
        exit 3
    fi

    _count=$(printf '%s\n' "$_matches" | grep -c .)

    if [ "$_count" -eq 1 ]; then
        printf '%s\n' "$_matches"
        return 0
    fi

    # Multiple matches: sort by canonical-location priority, then
    # alphabetically within each bucket. Lower priority number = earlier.
    #   1) .agents/    2) .opencode/    3) .claude/    4) skills/    5) other
    _sorted=$(printf '%s\n' "$_matches" | awk -v root="$_root" '
        {
            rel = $0
            sub("^" root "/", "", rel)
            first = rel
            sub("/.*", "", first)
            pri = 5
            if (first == ".agents")   pri = 1
            else if (first == ".opencode") pri = 2
            else if (first == ".claude")   pri = 3
            else if (first == "skills")    pri = 4
            printf "%d\t%s\n", pri, $0
        }' | sort | cut -f2-)

    if [ ! -t 0 ]; then
        log "error: $_count skills named '$_name' found; \
cannot prompt (stdin is not a TTY)"
        log "  matches:"
        for _path in $(printf '%s\n' "$_sorted"); do
            log "    ${_path#"$_root"/}"
        done
        log "  re-run with a more specific skill name, or pick one of \
the above paths manually"
        exit 5
    fi

    # Interactive: present a numbered list and prompt.
    log "Found $_count matches for '$_name':"
    _i=0
    for _path in $(printf '%s\n' "$_sorted"); do
        _i=$((_i + 1))
        printf '  %d) %s\n' "$_i" "${_path#"$_root"/}" >&2
    done

    _choice=$(prompt_choice "Select [1-$_count] (default: 1): " "$_count")

    _selected=$(printf '%s\n' "$_sorted" | sed -n "${_choice}p")
    log "Selected: ${_selected#"$_root"/}"
    printf '%s\n' "$_selected"
    return 0
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
            log "error: cannot create destination '$_dest_parent'"
            exit 1
        fi
    fi

    if [ -e "$_dest" ]; then
        log "Removing existing $_dest"
        if ! rm -rf -- "$_dest"; then
            log "error: cannot remove existing '$_dest'"
            exit 1
        fi
    fi

    if ! cp -Rp -- "$_src" "$_dest"; then
        log "error: copy failed: $_src -> $_dest"
        exit 1
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

    CACHE_DIR="${CACHE_ROOT%/}/$CACHE_SUBPATH"

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
