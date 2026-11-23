#!/usr/bin/env bash
#
# ensure-groups.sh
#
# Purpose:
#   Gives every human account access to Docker and to libvirt (virt-manager
#   VMs without a password prompt). On image-based Fedora, groups created by
#   RPMs live in /usr/lib/group, which `usermod` cannot edit, so each group
#   must first be copied into /etc/group.
#
# Usage:
#   Run at boot by shatteredvales-groups.service.
#
# Exit codes:
#   0 always; a missing group is logged rather than blocking boot.

set -uo pipefail

readonly WORKSTATION_GROUPS=(docker libvirt)

# ensure_group_in_etc
#   Copies a group definition from /usr/lib/group into /etc/group.
#   Arguments: $1 group name
#   Returns: 0 if the group is in /etc/group, 1 if it does not exist anywhere
ensure_group_in_etc() {
    local group="$1" line
    grep -q "^${group}:" /etc/group && return 0
    line="$(grep "^${group}:" /usr/lib/group)" || return 1
    echo "${line}" >> /etc/group
}

# add_regular_users
#   Adds every regular account (UID 1000-59999) to a group. System accounts
#   are left alone.
#   Arguments: $1 group name
#   Returns: 0 always
add_regular_users() {
    local group="$1" user uid
    while IFS=: read -r user _ uid _; do
        if (( uid >= 1000 && uid < 60000 )) && ! id -nG "${user}" | grep -qw "${group}"; then
            usermod -aG "${group}" "${user}" && echo "Added ${user} to ${group}"
        fi
    done < /etc/passwd
}

# main
#   Ensures each workstation group exists in /etc/group and contains every
#   regular account.
#   Arguments: none
#   Returns: 0 even when a group is missing, so boot is never blocked
main() {
    local group
    for group in "${WORKSTATION_GROUPS[@]}"; do
        if ensure_group_in_etc "${group}"; then
            add_regular_users "${group}"
        else
            echo "Group ${group} not found; is its package installed?" >&2
        fi
    done
}

main "$@"
