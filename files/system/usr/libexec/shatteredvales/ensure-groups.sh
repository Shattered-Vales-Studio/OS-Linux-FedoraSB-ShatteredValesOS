#!/usr/bin/env bash
#
# ensure-groups.sh
#
# Purpose:
#   Gives every human account access to Docker. On image-based Fedora,
#   groups created by RPMs live in /usr/lib/group, which `usermod` cannot
#   edit, so the docker group must first be copied into /etc/group.
#
# Exit codes:
#   0 always; a missing group is logged rather than blocking boot.

set -uo pipefail

readonly GROUP=docker

# ensure_group_in_etc
#   Copies the group definition from /usr/lib/group into /etc/group.
#   Returns: 1 if the group does not exist anywhere
ensure_group_in_etc() {
    grep -q "^${GROUP}:" /etc/group && return 0
    local line
    line="$(grep "^${GROUP}:" /usr/lib/group)" || return 1
    echo "${line}" >> /etc/group
}

# main
#   Adds every regular account (UID 1000-59999) to ${GROUP}.
#   Arguments: none
#   Returns: 0 even when the group is missing, so boot is never blocked
main() {
    if ! ensure_group_in_etc; then
        echo "Group ${GROUP} not found; is docker-ce installed?" >&2
        exit 0
    fi

    # Regular accounts start at UID 1000; system accounts are left alone.
    local user
    while IFS=: read -r user _ uid _; do
        if (( uid >= 1000 && uid < 60000 )) && ! id -nG "${user}" | grep -qw "${GROUP}"; then
            usermod -aG "${GROUP}" "${user}" && echo "Added ${user} to ${GROUP}"
        fi
    done < /etc/passwd
}

main "$@"
