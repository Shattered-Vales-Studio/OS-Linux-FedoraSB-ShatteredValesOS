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

# step_npm_prefix
#   Points npm's global install prefix at ~/.local so `npm install -g`
#   works; the default prefix is under the read-only /usr. ~/.local/bin is
#   already on Fedora's default PATH.
#   Returns: npm exit status
step_npm_prefix() {
    npm config set prefix "${HOME}/.local"
}

# step_rustup
#   Installs the Rust toolchain with rustup into ~/.cargo. Per user because
#   rustup updates itself and the toolchains in place. rustup adds
#   ~/.cargo/bin to the shell profile itself.
#   Returns: installer exit status
step_rustup() {
    if [[ -x "${HOME}/.cargo/bin/rustup" ]]; then
        return 0
    fi
    wait_for_network || return 1
    curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y || return 1
    notify "Rust installed" "Open a new terminal to use cargo and rustc"
}

# step_jetbrains_toolbox
#   Downloads JetBrains Toolbox (used to install and update Rider and other
#   JetBrains IDEs), verifies its published SHA-256 and starts it once. On
#   first run Toolbox installs itself into ~/.local/share/JetBrains/Toolbox
#   and adds its own launcher and autostart entry. Per user because it
#   updates itself in place.
#   Returns: 0 on success, 1 on download, checksum or extraction failure
step_jetbrains_toolbox() {
    local install_dir="${HOME}/.local/share/JetBrains/Toolbox"
    if [[ -x "${install_dir}/bin/jetbrains-toolbox" ]]; then
        return 0
    fi
    wait_for_network || return 1

    local meta url sum_url work
    meta="$(curl -fsSL 'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release')" || return 1
    url="$(jq -r '.TBA[0].downloads.linux.link' <<<"${meta}")"
    sum_url="$(jq -r '.TBA[0].downloads.linux.checksumLink' <<<"${meta}")"
    [[ "${url}" == https://* && "${sum_url}" == https://* ]] || return 1

    work="$(mktemp -d)"
    if ! curl -fsSL -o "${work}/toolbox.tar.gz" "${url}" \
        || ! (cd "${work}" && curl -fsSL "${sum_url}" | awk '{print $1"  toolbox.tar.gz"}' | sha256sum -c --quiet -) \
        || ! tar -xzf "${work}/toolbox.tar.gz" -C "${work}" --strip-components=1; then
        rm -rf "${work}"
        return 1
    fi

    # Detached so the login script finishes while Toolbox completes its own
    # installation in the background.
    setsid "${work}/bin/jetbrains-toolbox" >/dev/null 2>&1 < /dev/null &
    notify "JetBrains Toolbox installed" "Use it to install Rider and other JetBrains IDEs"
}

# step_source_dir
#   Creates ~/Source, the studio's folder for repositories (see "Your First
#   Day" Step 6).
#   Returns: mkdir exit status
step_source_dir() {
    mkdir -p "${HOME}/Source"
}

# step_github_reminder
#   Points new users at GitHub Setup once, unless they already have a key.
#   Returns: 0 always
step_github_reminder() {
    if [[ ! -f "${HOME}/.ssh/id_ed25519" ]]; then
        notify "Connect to GitHub" "Open GitHub Setup from the app grid, or run: sv-github setup"
    fi
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
    run_step npm-prefix-v1 step_npm_prefix || failed=1
    run_step rustup-v1 step_rustup || failed=1
    run_step jetbrains-toolbox-v1 step_jetbrains_toolbox || failed=1
    run_step source-dir-v1 step_source_dir || failed=1
    run_step github-reminder-v1 step_github_reminder || failed=1

    if (( failed )); then
        notify "Workstation setup incomplete" "See ${LOG_FILE}. It will retry at next login."
    fi
}

main "$@"
