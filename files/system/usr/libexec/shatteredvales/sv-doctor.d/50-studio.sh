# shellcheck shell=bash
#
# 50-studio.sh
#
# Purpose:
#   Studio Edition's checks for sv-doctor, sourced by Core's sv-doctor:
#   Docker and VM group membership, and GitHub sign-in, SSH access and
#   commit signing.
#
# Inputs:
#   Core's sv-doctor report helper and EDITION_CHECKS array.
#
# Usage:
#   Sourced by /usr/bin/sv-doctor; not run directly.
#
# Exit codes:
#   Not applicable; it only defines and registers functions.

# check_group
#   Confirms the user is in a group in this session.
#   Arguments: $1 group, $2 check name, $3 what the group grants
#   Returns: 0 always
check_group() {
    if id -nG | grep -qw "$1"; then
        report PASS "$2" "In the $1 group"
    elif getent group "$1" | grep -qw "${USER}"; then
        report WARN "$2" "Added to $1 but not yet active; log out and back in"
    else
        report FAIL "$2" "Not in the $1 group ($3); restart, or ask IT to run ensure-groups"
    fi
}

# check_docker_group
#   Reports whether the user can run docker without sudo.
#   Arguments: none
#   Returns: 0 always
check_docker_group() {
    check_group docker "Docker" "needed to run docker without sudo"
}

# check_libvirt_group
#   Reports whether the user can manage VMs without a password.
#   Arguments: none
#   Returns: 0 always
check_libvirt_group() {
    check_group libvirt "VMs" "needed for virt-manager without a password"
}

# check_github
#   Reports Git identity, GitHub CLI sign-in, SSH access and commit signing.
#   Arguments: none
#   Returns: 0 always
check_github() {
    local email login
    email="$(git config --global user.email || true)"
    if [[ -n "${email}" ]]; then
        report PASS "Git identity" "$(git config --global user.name) <${email}>"
    else
        report WARN "Git identity" "Not set; run GitHub Setup (sv-github setup)"
    fi
    if login="$(gh api user --jq .login 2>/dev/null)"; then
        report PASS "GitHub CLI" "Signed in as ${login}"
    else
        report WARN "GitHub CLI" "Not signed in; run GitHub Setup (sv-github setup)"
    fi
    if sv-github test >/dev/null 2>&1; then
        report PASS "GitHub SSH" "Key accepted by GitHub"
    else
        report WARN "GitHub SSH" "SSH key not set up or not accepted; run GitHub Setup"
    fi
    if [[ "$(git config --global commit.gpgsign || true)" == true \
          && "$(git config --global gpg.format || true)" == ssh ]]; then
        report PASS "Commit signing" "Commits are signed (Verified on GitHub)"
    else
        report WARN "Commit signing" "Commits are not signed; run: sv-github signing"
    fi
}

EDITION_CHECKS+=(check_docker_group check_libvirt_group check_github)
