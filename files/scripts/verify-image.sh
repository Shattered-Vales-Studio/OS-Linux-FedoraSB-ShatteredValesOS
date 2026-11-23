#!/usr/bin/env bash
#
# verify-image.sh
#
# Purpose:
#   Final build gate. Fails the build when the image is not a valid bootc
#   image or when anything the organization depends on is missing, so a
#   broken image is never published to workstations.
#
# Exit codes:
#   0 when every check passes, 1 otherwise.

set -euo pipefail

readonly REQUIRED_RPMS=(
    tailscale docker-ce golang git git-lfs nano firefox thunderbird code unityhub
    claude-desktop-unofficial openssh-server
    gnome-shell-extension-dash-to-dock gnome-shell-extension-appindicator
    subversion p4-cli gcc gcc-c++ cmake ninja-build clang gdb
    renderdoc vulkan-tools vulkan-validation-layers mangohud gamemode
    android-tools openxr monado dotnet-sdk-10.0
    nodejs26 nodejs26-npm pnpm chromium gh pipx uv
    webkit2gtk4.1-devel gtk3-devel libayatana-appindicator-gtk3-devel
    mingw64-gcc mingw64-gcc-c++ flatpak-builder rpm-build
    virt-manager libvirt-daemon-kvm qemu-kvm
)

readonly REQUIRED_PATHS=(
    /usr/bin/unityhub
    /usr/bin/artcraft-launcher
    # p4-cli installs into /opt; this proves BlueBuild relocated it.
    /usr/lib/opt/perforce/bin/p4
    /usr/bin/node
    /usr/share/fonts/google-fonts/Cinzel
    /usr/share/fonts/google-fonts/Lato
    "/usr/share/fonts/google-fonts/JetBrains Mono"
    # Studio Git defaults, GitHub setup and managed browser bookmarks.
    /etc/gitconfig
    /usr/bin/sv-github
    /usr/bin/unityyamlmerge
    /usr/share/applications/shatteredvales-github-setup.desktop
    /usr/share/applications/shatteredvales-new-project.desktop
    /usr/bin/sv-new-project
    /usr/bin/sv-doctor
    /usr/bin/sv-update
    /usr/libexec/shatteredvales/update-reminder.sh
    /usr/lib/systemd/user/shatteredvales-update-reminder.timer
    /etc/dconf/db/local.d/locks/10-shatteredvales-screenlock
    /etc/profile.d/shatteredvales-prompt.sh
    /etc/profile.d/shatteredvales-source.sh
    /etc/xdg/mimeapps.list
    /etc/docker/daemon.json
    /usr/bin/sv-branch
    /usr/bin/sv-rebase
    /usr/bin/sv-lfs-init
    /usr/bin/sv-clean
    /usr/bin/sv-unity
    /usr/bin/sv-env
    /usr/bin/sv-quest
    /etc/profile.d/shatteredvales-claude.sh
    /usr/lib/udev/rules.d/70-shatteredvales-android.rules
    /usr/libexec/shatteredvales/git-common.sh
    /usr/share/shatteredvales/artcraft-apps.list
    /usr/share/shatteredvales/templates/repo/gitattributes-game
    /usr/share/shatteredvales/templates/new-document/README.md
    /etc/firefox/policies/policies.json
    /etc/chromium/policies/managed/shatteredvales-bookmarks.json
    # Desktop files referenced by favorite-apps in the dconf defaults.
    /usr/share/applications/org.mozilla.firefox.desktop
    /usr/share/applications/net.thunderbird.Thunderbird.desktop
    /usr/share/applications/com.microsoft.VSCode.desktop
    /usr/share/applications/unityhub.desktop
    /usr/share/applications/claude-desktop-unofficial.desktop
    /usr/share/applications/org.gnome.Ptyxis.desktop
    /usr/bin/bw
    /usr/bin/sv-gpu-image
    /usr/libexec/shatteredvales/first-login.sh
    /etc/xdg/autostart/shatteredvales-first-login.desktop
    # Creates the docker group on machines that rebase onto the image.
    /usr/lib/sysusers.d/shatteredvales.conf
    /usr/share/plymouth/themes/shatteredvales/watermark.png
    /usr/share/backgrounds/shatteredvales/wallpaper.png
    /usr/share/shatteredvales/lockscreen-header.png
    /usr/share/shatteredvales/avatar.png
    /etc/dconf/db/local
    /etc/dconf/db/gdm
)

# main
#   Checks required RPMs, paths, the Plymouth theme and bootc lint.
#   Arguments: none
#   Returns: 0 when every check passes, 1 otherwise
main() {
    local failed=0 item

    for item in "${REQUIRED_RPMS[@]}"; do
        rpm -q "${item}" >/dev/null || { echo "MISSING RPM: ${item}"; failed=1; }
    done
    for item in "${REQUIRED_PATHS[@]}"; do
        [[ -e "${item}" ]] || { echo "MISSING PATH: ${item}"; failed=1; }
    done
    grep -q '^Theme=shatteredvales' /etc/plymouth/plymouthd.conf \
        || { echo "Plymouth theme not set"; failed=1; }

    bootc container lint || failed=1

    if (( failed )); then
        echo "Image verification failed" >&2
        exit 1
    fi
    echo "Image verification passed"
}

main "$@"
