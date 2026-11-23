#!/usr/bin/env bash
#
# first-login.sh
#
# Purpose:
#   Per-user setup that cannot live in the read-only image. Runs from the
#   desktop autostart on every login but only does work for steps that have
#   not completed yet, so new steps added in later images reach existing
#   users automatically.
#
# Usage:
#   Runs automatically at login. Can be re-run manually with `sv-first-login`.
#
# State:
#   ~/.local/state/shatteredvales/<step>.done marks a finished step.

set -uo pipefail

readonly STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/shatteredvales"
readonly LOG_FILE="${STATE_DIR}/first-login.log"

# notify
#   Shows a desktop notification when a graphical session is available.
#   Arguments: $1 summary, $2 body
#   Returns: 0 always
notify() {
    if command -v notify-send >/dev/null && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
        notify-send --app-name="Shattered Vales" --icon=shatteredvales-logo "$1" "$2" || true
    fi
}

# run_step
#   Runs a setup function once per user and records success.
#   Arguments: $1 step id, $2 function name
#   Returns: the function's exit status; failures are retried next login
run_step() {
    local id="$1" fn="$2"
    [[ -f "${STATE_DIR}/${id}.done" ]] && return 0
    echo "== ${id} ($(date -Is))"
    if "${fn}"; then
        touch "${STATE_DIR}/${id}.done"
    else
        echo "Step ${id} failed; it will retry on next login"
        return 1
    fi
}

# wait_for_network
#   Waits up to two minutes for connectivity, since autostart can fire
#   before Wi-Fi or Tailscale is up.
#   Returns: 0 when online, 1 on timeout
wait_for_network() {
    nm-online -q -t 120
}

# step_claude_code
#   Installs Claude Code with Anthropic's native installer into the user's
#   home. It must be per user because it updates itself in place, which is
#   impossible inside the read-only /usr.
#   Returns: installer exit status
step_claude_code() {
    if [[ -x "${HOME}/.local/bin/claude" ]]; then
        return 0
    fi
    wait_for_network || return 1
    curl -fsSL https://claude.ai/install.sh | bash || return 1
    notify "Claude Code installed" "Open a new terminal and run: claude"
}

# step_git_lfs
#   Registers Git LFS filters in the user's global git config so LFS works
#   in every clone without per-repo setup.
#   Returns: git exit status
step_git_lfs() {
    git lfs install --skip-repo
}

# main
#   Runs every pending per-user setup step and logs to the state directory.
#   Arguments: none
#   Returns: 0 always; failed steps are retried at the next login
main() {
    mkdir -p "${STATE_DIR}"
    exec >>"${LOG_FILE}" 2>&1

    local failed=0
    run_step git-lfs-v1 step_git_lfs || failed=1
    run_step claude-code-v1 step_claude_code || failed=1

    if (( failed )); then
        notify "Workstation setup incomplete" "See ${LOG_FILE}. It will retry at next login."
    fi
}

main "$@"
