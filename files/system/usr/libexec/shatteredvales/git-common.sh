# shellcheck shell=bash
#
# git-common.sh
#
# Purpose:
#   Helpers shared by the sv-branch, sv-rebase and sv-lfs-init commands.
#
# Usage:
#   source /usr/libexec/shatteredvales/git-common.sh
#
# Exit codes:
#   Not applicable; this file is sourced, never executed.

# say
#   Prints a highlighted progress line.
#   Arguments: message words
#   Returns: 0 always
say() {
    printf '\n\033[1;33m==>\033[0m \033[1m%s\033[0m\n' "$*"
}

# die
#   Prints an error and exits.
#   Arguments: message words
#   Returns: does not return
die() {
    printf '\033[1;31mError:\033[0m %s\n' "$*" >&2
    exit 1
}

# require_repo
#   Moves to the top of the current Git repository.
#   Arguments: none
#   Returns: does not return outside a repository
require_repo() {
    local top
    top="$(git rev-parse --show-toplevel 2>/dev/null)" || die "Run this inside a Git repository."
    cd "${top}" || die "Cannot enter ${top}."
}

# integration_branch
#   Prints the branch features are cut from and merged into. The studio
#   guides call it Dev; repositories from the Claude template call it dev.
#   Arguments: $1 optional explicit branch name
#   Output: branch name (without origin/)
#   Returns: does not return if none exists on origin
integration_branch() {
    if [[ -n "${1:-}" ]]; then
        printf '%s' "$1"
        return 0
    fi
    local candidate
    for candidate in Dev dev; do
        if git show-ref --verify --quiet "refs/remotes/origin/${candidate}"; then
            printf '%s' "${candidate}"
            return 0
        fi
    done
    die "No Dev or dev branch on origin. Pass the base branch explicitly."
}

# require_clean_tree
#   Stops if there are uncommitted changes, as the guides require before
#   switching base or rebasing.
#   Arguments: none
#   Returns: does not return if the working tree is dirty
require_clean_tree() {
    if [[ -n "$(git status --porcelain)" ]]; then
        git status --short
        die "Commit or stash these changes first (git stash push -m \"wip\")."
    fi
}
