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
)

readonly REQUIRED_PATHS=(
    /usr/bin/unityhub
    /usr/bin/artcraft-launcher
    # p4-cli installs into /opt; this proves BlueBuild relocated it.
    /usr/lib/opt/perforce/bin/p4
    /usr/bin/node
    /usr/share/fonts/google-fonts/Cinzel
    /usr/share/fonts/google-fonts/Lato
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
    /usr/share/plymouth/themes/shatteredvales/watermark.png
    /usr/share/backgrounds/shatteredvales/wallpaper.png
    /usr/share/shatteredvales/lockscreen-header.png
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
