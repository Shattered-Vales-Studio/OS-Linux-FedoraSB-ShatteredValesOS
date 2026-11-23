#!/usr/bin/env bash
#
# install-bitwarden-cli.sh
#
# Purpose:
#   Installs the Bitwarden CLI (`bw`) as a standalone binary. Bitwarden
#   ships it as a zip rather than an RPM, and the native binary avoids
#   pulling Node.js into the image.
#
# Usage:
#   Run by the BlueBuild script module during the image build.
#
# Inputs:
#   None. Always installs the latest release Bitwarden publishes.
#
# Exit codes:
#   0 on success, non-zero on download or extraction failure.

set -euo pipefail

readonly DOWNLOAD_URL="https://vault.bitwarden.com/download/?app=cli&platform=linux"

# Global rather than local so the EXIT trap can still see it after main returns.
WORK="$(mktemp -d)"
readonly WORK
trap 'rm -rf "${WORK}"' EXIT

# main
#   Downloads the CLI zip, installs the binary to /usr/bin and checks that it
#   runs.
#   Arguments: none
#   Returns: non-zero on any failure
main() {
    curl -fsSL -o "${WORK}/bw.zip" "${DOWNLOAD_URL}"
    # python3 is always present in Fedora Atomic, unlike unzip.
    python3 -m zipfile -e "${WORK}/bw.zip" "${WORK}/out"
    install -m 0755 "${WORK}/out/bw" /usr/bin/bw
    # bw writes a config directory on first run; keep it out of the image.
    BITWARDENCLI_APPDATA_DIR="${WORK}/appdata" /usr/bin/bw --version
}

main "$@"
