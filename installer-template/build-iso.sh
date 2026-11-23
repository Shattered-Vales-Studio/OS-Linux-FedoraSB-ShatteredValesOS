#!/usr/bin/env bash
#
# build-iso.sh
#
# Purpose:
#   Produces a hands-off installer ISO: Fedora's network installer with the
#   organization kickstart embedded, so booting the USB installs and
#   configures a workstation with no prompts (the Linux equivalent of an
#   autounattend.xml Windows stick).
#
# Usage:
#   ./build-iso.sh <Fedora-Everything-netinst-x86_64-*.iso> [output.iso]
#
# Inputs:
#   secrets.env   Organization values (see secrets.env.example)
#   ks.cfg.in     Kickstart template
#
# Requirements:
#   docker (OrbStack works) or podman. The installer image matches the
#   Fedora version used by the OS image.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HERE
readonly INPUT_ISO="${1:?usage: build-iso.sh <fedora-netinst.iso> [output.iso]}"
readonly OUTPUT_ISO="${2:-shatteredvales-installer.iso}"

# Only these variables are substituted, so the $variables used by the
# kickstart's own shell scripts are left untouched.
# envsubst takes the variable names literally, so they must not expand here.
# shellcheck disable=SC2016
readonly SUBST_VARS='${SV_IMAGE_REGISTRY} ${SV_IMAGE_TAG} ${SV_LANG} ${SV_KEYBOARD}
${SV_TIMEZONE} ${SV_TARGET_DISK} ${SV_HOSTNAME_PREFIX} ${SV_ADMIN_USER}
${SV_ADMIN_GECOS} ${SV_ADMIN_PASSWORD_HASH} ${SV_ADMIN_SSH_PUBKEY}
${SV_TAILSCALE_AUTHKEY} ${SV_TAILSCALE_UP_ARGS}'

# container_cli
#   Prints the available container runtime.
container_cli() {
    if command -v docker >/dev/null; then echo docker
    elif command -v podman >/dev/null; then echo podman
    else echo "docker or podman is required" >&2; return 1
    fi
}

# main
#   Renders the kickstart from secrets.env and builds the installer ISO.
#   Arguments: as described in the script header
#   Returns: non-zero on any failure
main() {
    [[ -f "${HERE}/secrets.env" ]] || { echo "Create secrets.env from secrets.env.example" >&2; exit 1; }
    [[ -f "${INPUT_ISO}" ]] || { echo "Input ISO not found: ${INPUT_ISO}" >&2; exit 1; }

    local iso_dir iso_name cli
    iso_dir="$(cd "$(dirname "${INPUT_ISO}")" && pwd)"
    iso_name="$(basename "${INPUT_ISO}")"
    cli="$(container_cli)"

    # mkksiso rewrites the ISO's boot configuration, which needs loop/device
    # access, hence --privileged.
    "${cli}" run --rm --privileged --platform linux/amd64 \
        -v "${HERE}:/work:Z" -v "${iso_dir}:/iso:Z" -w /work \
        -e SUBST_VARS="${SUBST_VARS}" \
        registry.fedoraproject.org/fedora:latest bash -euo pipefail -c "
            dnf -y -q install lorax gettext >/dev/null
            set -a; source secrets.env; set +a
            mkdir -p build
            envsubst \"\${SUBST_VARS}\" < ks.cfg.in > build/ks.cfg
            # Removing the media check makes the default boot entry start
            # installing immediately instead of verifying the USB first.
            mkksiso --ks build/ks.cfg -r 'rd.live.check' \
                '/iso/${iso_name}' 'build/${OUTPUT_ISO}'
            rm -f build/ks.cfg
        "
    echo "Built ${HERE}/build/${OUTPUT_ISO}"
    echo "Write it with Fedora Media Writer, or: sudo dd if=build/${OUTPUT_ISO} of=/dev/rdiskN bs=4m"
}

main "$@"
