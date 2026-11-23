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

# install_craft_app
#   Installs one Craft app as a user Flatpak bundle from its latest GitHub
#   release, after checking the bundle against the release's SHA256SUMS.txt.
#   Uses github.com download URLs rather than the API, which allows only 60
#   unauthenticated requests an hour per IP and would run out when a whole
#   office logs in at once.
#   Arguments: $1 app id, $2 GitHub owner/repo, $3 work directory
#   Returns: 0 on success, 1 on download, checksum or install failure
install_craft_app() {
    local id="$1" repo="$2" work="$3" base sums line file sum
    base="https://github.com/${repo}/releases/latest/download"
    sums="$(curl -fsSL --retry 2 "${base}/SHA256SUMS.txt")" || return 1
    line="$(grep -E "  ${id}-[0-9][^ ]*-linux-x86_64\.flatpak$" <<<"${sums}" | head -n1)"
    [[ -n "${line}" ]] || { echo "No x86_64 Flatpak in the latest ${repo} release"; return 1; }
    file="${line##* }"
    sum="${line%% *}"
    curl -fsSL --retry 2 -o "${work}/${file}" "${base}/${file}" || return 1
    echo "${sum}  ${work}/${file}" | sha256sum -c --quiet - || return 1
    # The same command ArtCraft Launcher runs, so it recognises and updates
    # these installs as its own.
    flatpak install --user -y --noninteractive --reinstall --bundle "${work}/${file}" || return 1
    rm -f "${work:?}/${file}"
}

# step_artcraft_apps
#   Installs the studio's default Craft apps (listed in
#   /usr/share/shatteredvales/artcraft-apps.list) for this user. Apps the
#   user already has are skipped; failures are retried at the next login.
#   Returns: 0 if every app is installed, 1 otherwise
step_artcraft_apps() {
    local list=/usr/share/shatteredvales/artcraft-apps.list id flatpak_id repo work failed=0
    wait_for_network || return 1
    # Bundles pull their runtime from the user's Flathub remote.
    flatpak remote-add --user --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo || return 1
    notify "Installing ArtCraft apps" "About 1 GB in the background; ArtCraft Launcher keeps them updated afterwards."
    work="$(mktemp -d)"
    while read -r id flatpak_id repo; do
        [[ -z "${id}" || "${id}" == \#* ]] && continue
        if flatpak info --user "${flatpak_id}" >/dev/null 2>&1 \
            || flatpak info --system "${flatpak_id}" >/dev/null 2>&1; then
            continue
        fi
        echo "Installing ${id} from ${repo}"
        install_craft_app "${id}" "${repo}" "${work}" || { echo "Failed: ${id}"; failed=1; }
    done < "${list}"
    rm -rf "${work}"
    (( failed == 0 )) || return 1
    notify "ArtCraft apps installed" "Open ArtCraft Launcher to see the suite and check for updates."
}

# step_source_bookmark
#   Adds ~/Source to the Files sidebar.
#   Returns: 0 always
step_source_bookmark() {
    local bookmarks="${XDG_CONFIG_HOME:-${HOME}/.config}/gtk-3.0/bookmarks"
    mkdir -p "$(dirname "${bookmarks}")" "${HOME}/Source"
    grep -q "file://${HOME}/Source" "${bookmarks}" 2>/dev/null \
        || echo "file://${HOME}/Source Source" >> "${bookmarks}"
}

# step_file_templates
#   Copies the studio's file templates into the user's Templates folder so
#   they appear under right-click > New Document in Files. Existing files
#   with the same name are kept.
#   Returns: cp exit status
step_file_templates() {
    local templates
    templates="$(xdg-user-dir TEMPLATES 2>/dev/null)"
    # xdg-user-dir falls back to $HOME when the folder is not configured;
    # never drop templates loose in the home folder.
    [[ -n "${templates}" && "${templates}" != "${HOME}" ]] || templates="${HOME}/Templates"
    mkdir -p "${templates}"
    cp -n /usr/share/shatteredvales/templates/new-document/* "${templates}/"
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
    run_step source-bookmark-v1 step_source_bookmark || failed=1
    run_step file-templates-v1 step_file_templates || failed=1
    # Last, because it downloads about 1 GB.
    run_step artcraft-apps-v1 step_artcraft_apps || failed=1

    if (( failed )); then
        notify "Workstation setup incomplete" "See ${LOG_FILE}. It will retry at next login."
    fi
}

main "$@"
