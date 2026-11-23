# shellcheck shell=bash
# The GIT_PS1_* settings are read by git-prompt.sh, which shellcheck cannot see.
# shellcheck disable=SC2034
#
# shatteredvales-prompt.sh
#
# Purpose:
#   Studio bash prompt: user@host, the current folder, and inside a Git
#   repository the branch and its state, with the branch in brand gold
#   (#c5a059). Sourced by /etc/bashrc for every interactive bash shell.
#
# Usage:
#   Automatic. To keep your own prompt, set SV_PROMPT=0 in ~/.bashrc before
#   /etc/bashrc is sourced, or set PS1 after it.
#
# Exit codes:
#   Not applicable; this file is sourced, never executed.

# Only interactive bash shells, and only when the user has not opted out.
if [ -n "${BASH_VERSION:-}" ] && [ -n "${PS1:-}" ] && [ "${SV_PROMPT:-1}" != 0 ] \
    && [ -r /usr/share/git-core/contrib/completion/git-prompt.sh ]; then

    # shellcheck source=/dev/null
    . /usr/share/git-core/contrib/completion/git-prompt.sh

    # Markers after the branch: * unstaged, + staged, % untracked,
    # $ stash present, and </>/= for behind/ahead/in sync with upstream.
    GIT_PS1_SHOWDIRTYSTATE=1
    GIT_PS1_SHOWSTAGEDSTATE=1
    GIT_PS1_SHOWUNTRACKEDFILES=1
    GIT_PS1_SHOWSTASHSTATE=1
    GIT_PS1_SHOWUPSTREAM=auto

    # Brand gold as 24-bit colour (Ptyxis and every modern terminal support
    # it), muted grey for user@host; \[ \] keep line editing aligned.
    __sv_gold='\[\e[38;2;197;160;89m\]'
    __sv_muted='\[\e[38;2;163;163;163m\]'
    __sv_bold='\[\e[1m\]'
    __sv_reset='\[\e[0m\]'

    # Inside a toolbox or distrobox container, prefix the prompt with the
    # same hexagon Ptyxis uses, so a container shell is never mistaken for
    # the host.
    __sv_prefix=''
    if [ -f /run/.containerenv ] || [ -f /.dockerenv ]; then
        __sv_prefix='⬢ '
    fi

    PROMPT_COMMAND="__git_ps1 '${__sv_prefix}${__sv_muted}\u@\h${__sv_reset} ${__sv_bold}\w${__sv_reset}' '${__sv_reset} \\\$ ' ' ${__sv_gold}(%s)'${PROMPT_COMMAND:+; ${PROMPT_COMMAND}}"

    unset __sv_gold __sv_muted __sv_bold __sv_reset __sv_prefix
fi
