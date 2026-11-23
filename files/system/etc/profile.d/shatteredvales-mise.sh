# shellcheck shell=bash
#
# shatteredvales-mise.sh
#
# Purpose:
#   Enables mise, the per-project tool version manager installed by
#   first-login into ~/.local/bin. In interactive bash, `mise activate`
#   switches Node, Python, Go, .NET and other versions as you cd into a
#   project with a mise.toml or .tool-versions file. Other shells, such as
#   the ones editors, scripts and Claude Code start, get mise's shims on
#   PATH, which pick the right version per directory without activation.
#
# Usage:
#   Automatic. Opt out by setting SV_MISE=0 in ~/.bashrc.
#
# Exit codes:
#   Not applicable; this file is sourced, never executed.

if [ "${SV_MISE:-1}" != 0 ] && [ -x "${HOME}/.local/bin/mise" ]; then
    if [ -n "${BASH_VERSION:-}" ] && [ -n "${PS1:-}" ]; then
        eval "$("${HOME}/.local/bin/mise" activate bash)"
    else
        case ":${PATH}:" in
            *":${HOME}/.local/share/mise/shims:"*) ;;
            *) export PATH="${HOME}/.local/share/mise/shims:${PATH}" ;;
        esac
    fi
fi
