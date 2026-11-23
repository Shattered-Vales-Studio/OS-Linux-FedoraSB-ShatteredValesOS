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

# step_homebrew
#   Installs Homebrew into /home/linuxbrew/.linuxbrew for the account that
#   owns that folder (see usr/lib/tmpfiles.d/shatteredvales-homebrew.conf).
#   Per user because brew updates itself and its packages in place. Cloned
#   directly rather than through Homebrew's install script, which asks for
#   sudo; a full clone because `brew update` does not support shallow ones.
#   Other accounts skip the step: Homebrew allows one owner per prefix.
#   Returns: 0 when installed or skipped, 1 on download failure
step_homebrew() {
    local prefix=/home/linuxbrew/.linuxbrew
    [[ -x "${prefix}/bin/brew" ]] && return 0
    [[ -O /home/linuxbrew ]] || return 0
    wait_for_network || return 1
    mkdir -p "${prefix}/bin"
    if [[ ! -d "${prefix}/Homebrew/.git" ]]; then
        rm -rf "${prefix}/Homebrew"
        git clone --quiet https://github.com/Homebrew/brew "${prefix}/Homebrew" || return 1
    fi
    ln -sfn ../Homebrew/bin/brew "${prefix}/bin/brew"
    "${prefix}/bin/brew" update --force --quiet || return 1
    notify "Homebrew installed" "Open a new terminal to use brew"
}

# step_mise
#   Installs mise (per-project versions of Node, Python, Go, .NET and more)
#   into ~/.local/bin with its official installer. Per user because mise
#   updates itself (`mise self-update`). Activation lives in
#   /etc/profile.d/shatteredvales-mise.sh.
#   Returns: installer exit status
step_mise() {
    [[ -x "${HOME}/.local/bin/mise" ]] && return 0
    wait_for_network || return 1
    curl -fsSL https://mise.run | MISE_INSTALL_PATH="${HOME}/.local/bin/mise" sh || return 1
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

# is_generated_avatar
#   Tells a picture the user chose apart from the initials avatar GNOME
#   Initial Setup generates. Generated avatars are drawn as a circle with
#   transparent corners; photos and GNOME's stock pictures are opaque
#   squares, which GNOME crops to a circle only when displaying them.
#   Arguments: $1 path to the current account picture
#   Returns: 0 if the picture is a generated initials avatar, 1 otherwise
is_generated_avatar() {
    python3 -I - "$1" <<'PY'
import sys
import gi
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf
try:
    pixbuf = GdkPixbuf.Pixbuf.new_from_file(sys.argv[1])
except Exception:
    sys.exit(1)
if not pixbuf.get_has_alpha():
    sys.exit(1)
pixels = pixbuf.get_pixels()
# Alpha of the top-left pixel (RGBA, so byte 3).
sys.exit(0 if pixels[3] == 0 else 1)
PY
}

# is_admin
#   Tells whether this account is an administrator (a member of wheel).
#   Arguments: none
#   Returns: 0 for administrators, 1 otherwise
is_admin() {
    id -nG | tr ' ' '\n' | grep -qx wheel
}

# sync_user_icon
#   Gives the account the studio logo as its picture when it has none, only
#   GNOME's generated initials avatar, or one of the studio's own defaults:
#   red for administrators, gold for everyone else, so the login screen
#   shows which accounts can change the computer. Runs at every login so the
#   colour follows the account when it is made or unmade an administrator.
#   Pictures the user chose are never replaced.
#   Arguments: none
#   Returns: 0 when the picture is set or kept, 1 if setting it failed
sync_user_icon() {
    local user_path icon default=/usr/share/shatteredvales/avatar.png
    local admin=/usr/share/shatteredvales/avatar-admin.png picture
    user_path="$(busctl --system call org.freedesktop.Accounts /org/freedesktop/Accounts \
        org.freedesktop.Accounts FindUserById x "$(id -u)" | cut -d'"' -f2)" || return 1
    icon="$(busctl --system get-property org.freedesktop.Accounts "${user_path}" \
        org.freedesktop.Accounts.User IconFile | cut -d'"' -f2)" || return 1
    picture="${default}"
    is_admin && picture="${admin}"
    # AccountsService stores a copy, so the current picture is compared by
    # content with the defaults rather than by path.
    if [[ -s "${icon}" ]]; then
        cmp -s "${icon}" "${picture}" && return 0
        if ! cmp -s "${icon}" "${default}" && ! cmp -s "${icon}" "${admin}" \
            && ! is_generated_avatar "${icon}"; then
            return 0
        fi
    fi
    busctl --system call org.freedesktop.Accounts "${user_path}" \
        org.freedesktop.Accounts.User SetIconFile s "${picture}" >/dev/null
}

# step_unity_cli
#   Installs the Unity CLI (`unity`) with Unity's official installer into
#   ~/.local/bin. Per user because it updates itself (`unity self-update`).
#   sv-unity uses it, since Unity Hub 4 no longer has a command line.
#   Returns: installer exit status
step_unity_cli() {
    if [[ -x "${HOME}/.local/bin/unity" ]]; then
        return 0
    fi
    wait_for_network || return 1
    curl -fsSL https://unity.com/install.sh | bash || return 1
}

# step_mcp_servers
#   Adds the studio's local MCP servers to Claude Code for this user (user
#   scope, so they work in every project and users can add their own).
#   Both run through npx, so they're always current and nothing is
#   installed globally. GitHub and the claude.ai connectors (Atlassian,
#   Google Workspace, Slack, ...) are not added here: they come with the
#   user's Claude organization sign-in.
#   Returns: 0 when every server is configured, 1 otherwise
step_mcp_servers() {
    local claude="${HOME}/.local/bin/claude" failed=0
    [[ -x "${claude}" ]] || return 1
    # name, then the command that starts the server
    local -a servers=(
        "google-play-developer|npx -y google-play-developer-mcp"
        "shopify-dev-mcp|npx -y @shopify/dev-mcp@latest"
    )
    local entry name
    for entry in "${servers[@]}"; do
        name="${entry%%|*}"
        "${claude}" mcp get "${name}" >/dev/null 2>&1 && continue
        # The command is split on spaces deliberately: none of these
        # arguments contain spaces.
        # shellcheck disable=SC2086
        "${claude}" mcp add --scope user --transport stdio "${name}" -- ${entry#*|} \
            || failed=1
    done
    return "${failed}"
}

# step_unity_mcp
#   Registers the Unity Editor's MCP server (`unity mcp`, part of the Unity
#   CLI) in Claude Code and Claude Desktop, so either can drive an open
#   Unity Editor. Runs after the Unity CLI is installed.
#   Returns: 0 when both clients are configured, 1 otherwise
step_unity_mcp() {
    local unity="${HOME}/.local/bin/unity"
    [[ -x "${unity}" && -x "${HOME}/.local/bin/claude" ]] || return 1
    # UNITY_NO_CONSENT_PROMPT skips the CLI's first-run analytics question
    # without answering it on the user's behalf; --yes only confirms adding
    # the entry this step exists to add.
    UNITY_NO_CONSENT_PROMPT=1 PATH="${HOME}/.local/bin:${PATH}" \
        "${unity}" mcp configure claude-code --yes --non-interactive || return 1
    UNITY_NO_CONSENT_PROMPT=1 "${unity}" mcp configure claude --yes --non-interactive || return 1
}

# sync_share_bookmarks
#   Adds the shares listed in /etc/shatteredvales/network-shares to the
#   Files sidebar. Runs at every login rather than once, so shares an admin
#   adds later reach existing users. Windows paths (\\server\share) are
#   converted to smb:// addresses; bookmarks already present are left alone.
#   Arguments: none
#   Returns: 0 always
sync_share_bookmarks() {
    local list=/etc/shatteredvales/network-shares
    local bookmarks="${XDG_CONFIG_HOME:-${HOME}/.config}/gtk-3.0/bookmarks"
    local address name url
    [[ -r "${list}" ]] || return 0
    mkdir -p "$(dirname "${bookmarks}")"
    touch "${bookmarks}"
    while read -r address name; do
        [[ -z "${address}" || "${address}" == \#* ]] && continue
        if [[ "${address}" == \\\\* ]]; then
            url="smb://$(sed -e 's#^\\\\##' -e 's#\\#/#g' <<<"${address}")"
        else
            url="${address}"
        fi
        # Compared as a whole first field, since addresses contain dots and
        # other characters grep would treat as a pattern.
        awk -v u="${url}" '$1 == u {found = 1} END {exit !found}' "${bookmarks}" && continue
        echo "${url}${name:+ ${name}}" >> "${bookmarks}"
        echo "Added share bookmark ${url}"
    done < "${list}"
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
    run_step mcp-servers-v1 step_mcp_servers || failed=1
    run_step unity-cli-v1 step_unity_cli || failed=1
    run_step unity-mcp-v1 step_unity_mcp || failed=1
    run_step npm-prefix-v1 step_npm_prefix || failed=1
    run_step rustup-v1 step_rustup || failed=1
    run_step homebrew-v1 step_homebrew || failed=1
    run_step mise-v1 step_mise || failed=1
    run_step jetbrains-toolbox-v1 step_jetbrains_toolbox || failed=1
    run_step source-dir-v1 step_source_dir || failed=1
    run_step github-reminder-v1 step_github_reminder || failed=1
    run_step source-bookmark-v1 step_source_bookmark || failed=1
    run_step file-templates-v1 step_file_templates || failed=1
    # Last, because it downloads about 1 GB.
    run_step artcraft-apps-v1 step_artcraft_apps || failed=1
    sync_share_bookmarks
    sync_user_icon || failed=1

    if (( failed )); then
        notify "Workstation setup incomplete" "See ${LOG_FILE}. It will retry at next login."
    fi
}

main "$@"
