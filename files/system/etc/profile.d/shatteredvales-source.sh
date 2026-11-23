# shellcheck shell=bash
#
# shatteredvales-source.sh
#
# Purpose:
#   Lets `cd <repo>` reach any repository in ~/Source from any folder, the
#   studio's convention for where repositories live ("Your First Day",
#   Step 6). Interactive bash only.
#
# Usage:
#   Automatic. Opt out by setting SV_SOURCE_CDPATH=0 in ~/.bashrc.
#
# Exit codes:
#   Not applicable; this file is sourced, never executed.

# Deliberately not exported: an exported CDPATH changes `cd` inside every
# script the shell starts, which breaks scripts that cd to relative paths.
if [ -n "${BASH_VERSION:-}" ] && [ -n "${PS1:-}" ] && [ "${SV_SOURCE_CDPATH:-1}" != 0 ] \
    && [ -d "${HOME}/Source" ]; then
    CDPATH=".:${HOME}/Source"
fi
