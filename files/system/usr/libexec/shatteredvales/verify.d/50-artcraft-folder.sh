#!/usr/bin/env bash
#
# 50-artcraft-folder.sh
#
# Purpose:
#   Release-gate check for Studio Edition: confirms every app in the
#   ArtCraft install list is also in the ArtCraft app grid folder, so a
#   newly added Craft app cannot end up loose in the grid.
#
# Usage:
#   Run by /usr/libexec/shatteredvales/build/verify-image.sh at build time.
#
# Exit codes:
#   0 when the folder lists every app, 1 otherwise.

set -euo pipefail

readonly FOLDERS=/etc/dconf/db/local.d/20-shatteredvales-app-folders
readonly LIST=/usr/share/shatteredvales/artcraft-apps.list

# main
#   Compares the install list with the folder's apps.
#   Arguments: none
#   Returns: 0 when every app is in the folder, 1 otherwise
main() {
    local apps id flatpak_id _ status=0
    apps="$(sed -n '/^\[org\/gnome\/desktop\/app-folders\/folders\/ArtCraft\]/,/^\[/p' "${FOLDERS}" | grep '^apps=')"
    while read -r id flatpak_id _; do
        [[ -z "${id}" || "${id}" == \#* ]] && continue
        [[ "${apps}" == *"'${flatpak_id}.desktop'"* ]] \
            || { echo "ArtCraft folder is missing ${flatpak_id}.desktop"; status=1; }
    done < "${LIST}"
    return "${status}"
}

main "$@"
