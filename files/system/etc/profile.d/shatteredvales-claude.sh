# shellcheck shell=bash
#
# shatteredvales-claude.sh
#
# Purpose:
#   Lets the GitHub MCP server that the studio's Claude organization
#   provides sign in without anyone creating a personal access token. That
#   server reads GITHUB_PERSONAL_ACCESS_TOKEN; this wrapper fills it from the
#   GitHub CLI's sign-in (set up by GitHub Setup / sv-github) when Claude
#   Code starts. Claude Code can already run `gh` as the user, so this gives
#   it no access it didn't have. The token is passed only to Claude Code,
#   never exported to the rest of the session.
#
# Usage:
#   Automatic in interactive bash. A token you set yourself is left alone.
#
# Exit codes:
#   Not applicable; this file is sourced, never executed.

if [ -n "${BASH_VERSION:-}" ] && [ -n "${PS1:-}" ]; then
    # claude
    #   Runs Claude Code with GITHUB_PERSONAL_ACCESS_TOKEN taken from the
    #   GitHub CLI when it isn't already set.
    #   Arguments: passed through to Claude Code
    #   Returns: Claude Code's exit status
    claude() {
        if [ -z "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ] && command -v gh >/dev/null; then
            GITHUB_PERSONAL_ACCESS_TOKEN="$(gh auth token 2>/dev/null)" command claude "$@"
        else
            command claude "$@"
        fi
    }
fi
