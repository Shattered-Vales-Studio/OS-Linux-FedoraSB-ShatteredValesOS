# shellcheck shell=bash
#
# 50-studio.sh
#
# Purpose:
#   Studio Edition's per-user setup, sourced by Core's first-login.sh:
#   developer tools that update themselves and therefore cannot live in the
#   read-only /usr (Claude Code, the Unity CLI, rustup, Homebrew, mise,
#   JetBrains Toolbox), their MCP servers for Claude, Git LFS and npm
#   defaults, the ~/Source folder and the studio's file templates. Each runs
#   once per user and is retried at the next login until it succeeds.
#
# Inputs:
#   Core's first-login.sh helpers and registration arrays (notify,
#   wait_for_network, is_admin, STEPS).
#
# Usage:
#   Sourced by /usr/libexec/shatteredvales/first-login.sh; not run directly.
#
# Exit codes:
#   Not applicable; it only defines and registers functions.

# step_git_lfs
#   Registers Git LFS filters in the user's global git config so LFS works
#   in every clone without per-repo setup.
#   Returns: git exit status
step_git_lfs() {
    git lfs install --skip-repo
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
#   Installs Homebrew into /home/linuxbrew/.linuxbrew for the first
#   administrator who logs in (see usr/lib/tmpfiles.d/
#   shatteredvales-homebrew.conf). Per user because brew updates itself and
#   its packages in place. Cloned directly rather than through Homebrew's
#   install script, which asks for sudo; a full clone because `brew update`
#   does not support shallow ones. Skipped, and marked done, for everyday
#   accounts, for accounts in /etc/shatteredvales/homebrew-skip-users (the
#   installer's IT account) and once another account owns Homebrew.
#   Returns: 0 when installed or skipped, 1 on download failure
step_homebrew() {
    local parent=/home/linuxbrew prefix=/home/linuxbrew/.linuxbrew
    local skip=/etc/shatteredvales/homebrew-skip-users
    [[ -x "${prefix}/bin/brew" ]] && return 0
    is_admin || return 0
    if [[ -r "${skip}" ]] && grep -qx "${USER}" "${skip}"; then
        return 0
    fi
    if [[ -e "${prefix}" ]]; then
        [[ -O "${prefix}" ]] || return 0
    else
        [[ -w "${parent}" ]] || return 0
        mkdir "${prefix}" || return 0
    fi
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

STEPS+=(
    "git-lfs-v1 step_git_lfs"
    "claude-code-v1 step_claude_code"
    "mcp-servers-v1 step_mcp_servers"
    "unity-cli-v1 step_unity_cli"
    "unity-mcp-v1 step_unity_mcp"
    "npm-prefix-v1 step_npm_prefix"
    "rustup-v1 step_rustup"
    "homebrew-v1 step_homebrew"
    "mise-v1 step_mise"
    "jetbrains-toolbox-v1 step_jetbrains_toolbox"
    "source-dir-v1 step_source_dir"
    "github-reminder-v1 step_github_reminder"
    "source-bookmark-v1 step_source_bookmark"
    "file-templates-v1 step_file_templates"
)
