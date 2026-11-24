# shellcheck shell=sh
#
# shatteredvales-brew.sh
#
# Purpose:
#   Puts Homebrew's tools on PATH once first-login has installed it into
#   /home/linuxbrew/.linuxbrew. Brew paths go after the system's, unlike
#   `brew shellenv`, so a formula such as python or gcc never shadows the
#   image's own copy that system scripts and Flatpak builds rely on.
#   Developers who want brew first can add `eval "$(brew shellenv)"` to
#   ~/.bashrc.
#
# Usage:
#   Automatic for login and interactive shells.
#
# Exit codes:
#   Not applicable; this file is sourced, never executed.

if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    HOMEBREW_PREFIX=/home/linuxbrew/.linuxbrew
    HOMEBREW_CELLAR="${HOMEBREW_PREFIX}/Cellar"
    HOMEBREW_REPOSITORY="${HOMEBREW_PREFIX}/Homebrew"
    export HOMEBREW_PREFIX HOMEBREW_CELLAR HOMEBREW_REPOSITORY
    case ":${PATH}:" in
        *":${HOMEBREW_PREFIX}/bin:"*) ;;
        *) PATH="${PATH}:${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin" ;;
    esac
    export PATH
    # The trailing colon keeps the system manual and info paths searched too.
    export MANPATH="${MANPATH:-}:${HOMEBREW_PREFIX}/share/man"
    export INFOPATH="${HOMEBREW_PREFIX}/share/info:${INFOPATH:-}"
fi
