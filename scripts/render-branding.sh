#!/usr/bin/env bash
#
# render-branding.sh
#
# Purpose:
#   Generates every branded image in the OS from branding/source and
#   branding/brand.env, and stages them under files/system. The artwork
#   reproduces the website's look: the logo and an uppercase Cinzel wordmark
#   filled with the gold-foil gradient, a soft gold glow, and the radial
#   page-background gradient. Rendering runs in a Fedora container so the
#   output is identical on macOS and Linux and no image tools need to be
#   installed on the host.
#
# Inputs:
#   branding/brand.env, branding/source/logo.svg,
#   branding/source/logo-symbolic.svg, branding/source/fonts/*.ttf
#
# Usage:
#   scripts/render-branding.sh            (from the repo root, or `just branding`)
#
# Requirements:
#   docker (OrbStack works) or podman on the host.
#
# Exit codes:
#   0 on success, 1 if a required source file is missing or rendering fails.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT

# container_cli
#   Prints the available container runtime.
#   Arguments: none
#   Output: "docker" or "podman" on stdout
#   Returns: 1 if neither docker nor podman is installed
container_cli() {
    if command -v docker >/dev/null; then echo docker
    elif command -v podman >/dev/null; then echo podman
    else echo "docker or podman is required" >&2; return 1
    fi
}

# render_inside
#   Body executed inside the container. Kept as a single function (with
#   nested helpers) so it can be shipped into the container with
#   `declare -f` and the whole pipeline stays readable in one file.
#   Arguments: none
#   Returns: non-zero on any rendering failure
render_inside() {
    set -euo pipefail
    dnf -y -q install ImageMagick librsvg2-tools >/dev/null
    cd /work
    # shellcheck source=/dev/null
    source branding/brand.env

    local src=branding/source out=files/system
    local tmp; tmp="$(mktemp -d)"
    local -a stops
    read -r -a stops <<<"${BRAND_FOIL_STOPS}"

    local f
    for f in "${src}/logo.svg" "${src}/logo-symbolic.svg" \
             "${BRAND_FONT_FILE}" "${BRAND_FONT_BOLD_FILE}" "${BRAND_DISPLAY_FONT_FILE}"; do
        [[ -f "${f}" ]] || { echo "Missing ${f}" >&2; exit 1; }
    done

    # foil_svg
    #   Writes a copy of the logo whose fill is the foil gradient. The
    #   gradient spans the full 0..viewBox width, matching the site, where
    #   the gradient covers the logo element's whole box through a mask.
    #   Arguments: $1 output path
    #   Returns: 0 on success
    foil_svg() {
        local width offsets="" i n=${#stops[@]}
        width="$(grep -oE 'viewBox="[^"]+"' "${src}/logo.svg" | awk '{print $3}')"
        for (( i = 0; i < n; i++ )); do
            offsets+="<stop offset=\"$(( i * 100 / (n - 1) ))%\" stop-color=\"${stops[i]}\"/>"
        done
        sed -e '/^<!--/d' \
            -e "s|<g>|<defs><linearGradient id=\"foil\" gradientUnits=\"userSpaceOnUse\" x1=\"0\" y1=\"0\" x2=\"${width}\" y2=\"0\">${offsets}</linearGradient></defs><g>|" \
            -e "s|fill=\"${BRAND_ACCENT}\"|fill=\"url(#foil)\"|gI" \
            "${src}/logo.svg" > "$1"
        grep -q 'url(#foil)' "$1" || { echo "logo.svg fill is not ${BRAND_ACCENT}" >&2; return 1; }
    }

    # tile_icon
    #   Writes a scalable app icon: a rounded tile filled with the site's
    #   page gradient and a thin gold edge, with a line glyph stroked in the
    #   foil gradient, on a 128x128 canvas.
    #   Arguments: $1 icon name, $2 SVG elements for the glyph (unstyled;
    #              stroke and fill come from the enclosing group)
    #   Returns: 0 on success
    tile_icon() {
        local offsets="" i n=${#stops[@]}
        for (( i = 0; i < n; i++ )); do
            offsets+="<stop offset=\"$(( i * 100 / (n - 1) ))%\" stop-color=\"${stops[i]}\"/>"
        done
        cat > "${out}/usr/share/icons/hicolor/scalable/apps/$1.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
  <defs>
    <linearGradient id="foil" gradientUnits="userSpaceOnUse" x1="24" y1="24" x2="104" y2="104">${offsets}</linearGradient>
    <radialGradient id="page" cx="64" cy="64" r="80" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="${BRAND_BG_GLOW}"/><stop offset="100%" stop-color="${BRAND_BG}"/>
    </radialGradient>
  </defs>
  <rect x="8" y="8" width="112" height="112" rx="26" fill="url(#page)" stroke="${BRAND_ACCENT}" stroke-opacity="0.45" stroke-width="2"/>
  <g fill="none" stroke="url(#foil)" stroke-width="7" stroke-linecap="round" stroke-linejoin="round">$2</g>
</svg>
SVG
    }

    # foilify
    #   Replaces the colour of every opaque pixel in a PNG with the foil
    #   gradient, keeping its alpha. Used for rasterised text, which cannot
    #   carry an SVG gradient through ImageMagick's label renderer.
    #   Arguments: $1 input PNG, $2 output PNG
    #   Returns: 0 on success
    foilify() {
        local size
        size="$(magick identify -format '%wx%h' "$1")"
        magick "${stops[@]/#/xc:}" +append -filter Triangle -resize "${size}!" \
            \( "$1" -alpha extract \) -alpha off -compose CopyOpacity -composite "$2"
    }

    # glow
    #   Adds the site's soft gold halo (drop-shadow 0 0 14px at 14% gold)
    #   behind a transparent PNG. The canvas grows so the halo is not cut.
    #   Arguments: $1 input PNG, $2 output PNG, $3 blur radius in px
    #   Returns: 0 on success
    glow() {
        magick "$1" \( +clone -background "${BRAND_ACCENT}" -shadow "14x$3+0+0" \) \
            +swap -background none -layers merge +repage "$2"
    }

    # wordmark
    #   Renders the two-line name in uppercase Cinzel Bold with the site's
    #   0.1em letter spacing, both lines at the same size as on the site.
    #   Arguments: $1 point size, $2 output PNG
    #   Returns: 0 on success
    wordmark() {
        local pt="$1" kern line i
        kern="$(awk -v p="${pt}" 'BEGIN { printf "%.1f", p * 0.1 }')"
        i=0
        for line in "${BRAND_NAME_LINE1}" "${BRAND_NAME_LINE2}"; do
            magick -background none -fill white -font "${BRAND_DISPLAY_FONT_FILE}" \
                -pointsize "${pt}" -kerning "${kern}" label:"${line^^}" -trim +repage \
                "${tmp}/wm-line${i}.png"
            i=$((i + 1))
        done
        magick "${tmp}/wm-line0.png" \( -size "1x$(( pt / 4 ))" xc:none \) "${tmp}/wm-line1.png" \
            -background none -gravity center -append "${tmp}/wm-white.png"
        foilify "${tmp}/wm-white.png" "$2"
    }

    mkdir -p "${out}/usr/share/backgrounds/shatteredvales" \
             "${out}/usr/share/shatteredvales" \
             "${out}/usr/share/plymouth/themes/shatteredvales" \
             "${out}/usr/share/pixmaps" \
             "${out}/usr/share/icons/hicolor/scalable/apps"

    foil_svg "${tmp}/logo-foil.svg"
    local h
    for h in 1024 512 256 192; do
        rsvg-convert -h "${h}" "${tmp}/logo-foil.svg" -o "${tmp}/logo-${h}.png"
    done

    # Lock screen header: logo above the wordmark, at the top of a tall
    # transparent canvas. GNOME Shell's St toolkit only accepts pixel values
    # for background-position and otherwise centres the image on the clock,
    # so the canvas is exactly the clock's min-height in
    # shell-overrides.css.in (480x920): centred, its top edge meets the top
    # of the clock and the header sits above the time. Rendered at 2x so it
    # stays sharp on HiDPI displays.
    wordmark 72 "${tmp}/wm-lock.png"
    magick "${tmp}/logo-256.png" -trim +repage "${tmp}/logo-lock.png"
    magick "${tmp}/logo-lock.png" \( -size 1x28 xc:none \) "${tmp}/wm-lock.png" \
        -background none -gravity center -append "${tmp}/lock-raw.png"
    glow "${tmp}/lock-raw.png" "${tmp}/lock-glow.png" 14
    magick "${tmp}/lock-glow.png" -resize 960x440 -background none -gravity center \
        -extent 960x440 -gravity north -extent 960x1840 \
        "${out}/usr/share/shatteredvales/lockscreen-header.png"

    # Boot splash watermark. Plymouth draws it 1:1 on the framebuffer, so
    # it is sized for a 1080p panel and stays proportionate on 4K.
    wordmark 56 "${tmp}/wm-boot.png"
    magick "${tmp}/logo-512.png" -trim +repage -resize x300 "${tmp}/logo-boot.png"
    magick "${tmp}/logo-boot.png" \( -size 1x36 xc:none \) "${tmp}/wm-boot.png" \
        -background none -gravity center -append "${tmp}/boot-raw.png"
    glow "${tmp}/boot-raw.png" "${out}/usr/share/plymouth/themes/shatteredvales/watermark.png" 14

    # 4K wallpaper: the site's radial page gradient (glow colour at the
    # centre fading to the background at 70% of the half-diagonal) with a quiet
    # foil logo. Rendered at 16 bits and dithered to 8 so the dark gradient
    # does not band on 8-bit panels.
    magick -size 3840x2160 -depth 16 \
        -define gradient:radii=1542,1542 "radial-gradient:${BRAND_BG_GLOW}-${BRAND_BG}" \
        \( "${tmp}/logo-1024.png" -trim +repage -resize x900 \
           -channel A -evaluate multiply 0.35 +channel \) \
        -gravity center -composite \
        -attenuate 0.6 +noise Uniform -dither FloydSteinberg -depth 8 \
        "${out}/usr/share/backgrounds/shatteredvales/wallpaper.png"

    # Login screen logo: GDM shows it at roughly 48px tall under the user
    # list, so it is the mark beside the OS name on one line, rendered at 2x.
    magick -background none -fill white -font "${BRAND_DISPLAY_FONT_FILE}" \
        -pointsize 96 -kerning 9.6 label:"${BRAND_OS_NAME^^}" -trim +repage "${tmp}/gdm-text-white.png"
    foilify "${tmp}/gdm-text-white.png" "${tmp}/gdm-text.png"
    magick "${tmp}/logo-256.png" -trim +repage -resize x150 "${tmp}/logo-gdm.png"
    magick "${tmp}/logo-gdm.png" \( -size 28x1 xc:none \) "${tmp}/gdm-text.png" \
        -background none -gravity center +append -resize x96 \
        "${out}/usr/share/pixmaps/shatteredvales-gdm-logo.png"

    # Default account picture: the logo on the site's page gradient. GNOME
    # crops account pictures to a circle, so the mark stays inside the
    # inscribed circle with room to spare.
    magick -size 512x512 -define gradient:radii=256,256 \
        "radial-gradient:${BRAND_BG_GLOW}-${BRAND_BG}" \
        \( "${tmp}/logo-1024.png" -trim +repage -resize 300x300 \) \
        -gravity center -composite "${out}/usr/share/shatteredvales/avatar.png"

    cp "${src}/logo-symbolic.svg" "${out}/usr/share/pixmaps/shatteredvales-logo-symbolic.svg"
    cp "${tmp}/logo-foil.svg" "${out}/usr/share/icons/hicolor/scalable/apps/shatteredvales-logo.svg"
    local size
    for size in 48 64 128 256; do
        mkdir -p "${out}/usr/share/icons/hicolor/${size}x${size}/apps"
        rsvg-convert -w "${size}" -h "${size}" -a "${tmp}/logo-foil.svg" \
            -o "${out}/usr/share/icons/hicolor/${size}x${size}/apps/shatteredvales-logo.png"
    done

    # Studio launcher icons: a dark tile in the site's surface colours with
    # a gold-foil line glyph, so each studio tool is recognisable in the app
    # grid while matching the logo. Glyphs are generic shapes (a document,
    # a Git branch), never third-party logos.
    tile_icon "shatteredvales-new-project" \
        '<path d="M44 30h26l18 18v48a4 4 0 0 1-4 4H44a4 4 0 0 1-4-4V34a4 4 0 0 1 4-4z"/><path d="M70 30v18h18"/><path d="M64 62v26M51 75h26"/>'
    tile_icon "shatteredvales-github-setup" \
        '<circle cx="46" cy="38" r="9"/><circle cx="46" cy="92" r="9"/><circle cx="84" cy="52" r="9"/><path d="M46 47v36"/><path d="M84 61c0 16-38 10-38 22"/>'

    cp branding/brand.env "${out}/usr/share/shatteredvales/brand.env"
    rm -rf "${tmp}"
    echo "Branding rendered into ${out}"
}

# main
#   Runs render_inside in a throwaway Fedora container with the repo
#   mounted at /work.
#   Arguments: none
#   Returns: the container's exit status
main() {
    local cli; cli="$(container_cli)"
    "${cli}" run --rm -v "${ROOT}:/work:Z" registry.fedoraproject.org/fedora:latest \
        bash -c "$(declare -f render_inside); render_inside"
}

main "$@"
