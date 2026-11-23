# CLAUDE.md — Shattered Vales OS

You are working on the Shattered Vales Studio workstation OS: a custom Fedora
Atomic (Silverblue) image built with BlueBuild, published to GHCR, and
installed on studio machines. Read this whole file before making changes.

## How the system works

- `recipes/recipe-base.yml` and `recipes/recipe-nvidia.yml` differ **only** in
  `name` and `base-image`. Every other change goes in `recipes/common/*.yml`
  so the two images can never drift.
- `files/system/` is copied to `/` in the image. `files/scripts/` holds
  build-time scripts run by `type: script` modules.
- `branding/` is the single source for colors, fonts and artwork. Every value
  mirrors a token in the website's `assets/css/variables.css`. The gold-foil
  gradient is used only in rendered artwork; GNOME Shell text and controls use
  the flat accent so every pairing stays at WCAG AAA. Check contrast for any
  new color pairing before using it.
  `just branding` renders PNGs into `files/system`. Never hand-edit those
  generated files; change `branding/` and re-render.
- Brand values reach the image through `/usr/share/shatteredvales/brand.env`
  (a copy made by the renderer). Templates use `@BRAND_*@` placeholders that
  build scripts substitute.
- `installer-template/` is a template for a separate **private** repo. Never
  put real secrets in this repository.

## Bootstrap tasks (do these first, in order, and report back)

The initial scaffold was written without access to a build environment.
Treat everything below as unverified until you have checked it.

1. **Verify module schemas.** Fetch the current BlueBuild docs
   (https://blue-build.org/reference/modules/) and confirm the syntax used for
   `dnf` (including `repos.files`), `default-flatpaks`,
   `gnome-extensions`, `fonts`, `files`, `script`, `systemd` and `signing`.
   Fix any mismatch. Run `just validate`.
2. **Verify base images.** Confirm
   `ghcr.io/blue-build/base-images/fedora-silverblue` and
   `ghcr.io/blue-build/base-images/fedora-silverblue-nvidia-open` publish a tag
   for the current stable Fedora. Set `image-version` in both recipes to that
   version. (Universal Blue retired its NVIDIA Silverblue images in 2025; do
   not switch back to `ghcr.io/ublue-os/*-nvidia*`.)
3. **Extract branding from https://shatteredvales.studio.** Download the
   site's HTML and CSS with curl. Fill every `VERIFY` value in
   `branding/brand.env`: background, surface, accent and text colors, the
   font families, and the closest GNOME accent name. Update the font list in
   `recipes/common/desktop.yml` to match. Download the logo into
   `branding/source/logo.svg`, create a single-color white
   `branding/source/logo-symbolic.svg`, and download the font files from
   Google Fonts into `branding/source/fonts/`. Ask the user if the logo is
   only available as a raster image or the wordmark differs from
   `BRAND_NAME_LINE1/2`.
4. **Render branding:** `just branding`. Show the user the lock screen header,
   wallpaper and boot watermark PNGs for approval before going further.
5. **Verify third-party sources** used at build time still resolve:
   the Docker, Tailscale, VS Code, Unity Hub and claude-desktop-unofficial
   repos; the `storytold/craft-launcher` release asset naming; the Bitwarden
   CLI download URL. Check that the ArtCraft RPM and Unity Hub install paths
   are handled (both may install into `/opt`).
6. **Verify GNOME settings keys** against the extension versions for the
   chosen Fedora release: the Logo Menu schema path and key names, and Just
   Perfection's `clock-menu-position` values. Adjust
   `files/system/etc/dconf/db/local.d/10-shatteredvales-desktop`.
7. **Build and test locally:** `just build` then `just test`. On the user's
   Apple Silicon Mac this runs under OrbStack with amd64 emulation and is
   slow; that is expected.
8. **Signing:** walk the user through `just keys`, committing `cosign.pub`,
   and adding `SIGNING_SECRET` in the GitHub repo settings.
9. **First CI build:** push and watch both matrix jobs. Fix failures from the
   logs; do not disable `verify-image.sh` to get a green build.

## Commands

| Command | Purpose |
|---|---|
| `just branding` | Render artwork from `branding/` |
| `just validate` | Schema-check recipes |
| `just build [base\|nvidia]` | Build an image locally (linux/amd64) |
| `just test [base\|nvidia]` | Smoke-test a local build |
| `just lint` | shellcheck every script |

## Testing limits

- The Mac can **build** and **inspect** images, not boot them. Real boot
  testing (Plymouth, GDM, lock screen, extensions, NVIDIA) needs an x86_64
  machine or a VM on one of the studio's Linux workstations
  (GNOME Boxes or virt-manager).
- When you change anything visual, tell the user exactly what to check on
  real hardware, since you cannot see it.
- `bootc container lint` fails with "Function not implemented (os error 38)"
  under amd64 emulation on Apple Silicon, even on the untouched base image.
  It is an emulator limitation, not an image fault; CI runs it natively. For
  local checks, build a throwaway copy of `build/Containerfile.<variant>`
  without the `verify-image.sh` step, then run the script and `just test`
  against it and expect only the lint check to fail. Never weaken the gate.

## Rules

- Keep the two recipes identical apart from `name` and `base-image`.
- Never bake self-updating tools (Claude Code, rustup-style installers) into
  `/usr`; it is read-only on workstations. Per-user tools go in
  `files/system/usr/libexec/shatteredvales/first-login.sh` as a new
  versioned step (`run_step <name>-v1 <function>`). Bump the suffix to force
  a step to run again for everyone.
- Packages that install into `/opt` are relocated to `/usr/lib/opt` by the
  BlueBuild CLI (v0.9.23+) for every module, including scripts. dnf `optfix`
  is deprecated and does nothing; do not add it. Add the relocated payload
  to `REQUIRED_PATHS` in `verify-image.sh` so a regression fails the build.
- `verify-image.sh` is the release gate. When adding software, add it to
  `REQUIRED_RPMS` or `REQUIRED_PATHS` there.
- GNOME Shell CSS selectors and extension settings change between GNOME
  releases. On every Fedora major bump, re-check
  `files/system/usr/share/shatteredvales/theme/shell-overrides.css.in` and
  the dconf extension keys, and test on hardware before merging.
- Never commit `cosign.key`, `secrets.env`, password hashes or Tailscale keys.
- Builds from `main` publish only `:testing` (`alt-tags` in both recipes).
  `:latest` moves only through `.github/workflows/promote.yml`, which
  verifies the signature and re-tags by digest. Never make CI push `:latest`
  directly; that would skip the canary week for every workstation.
- System-wide defaults that users may override go in `/etc` config files
  (`/etc/gitconfig`, dconf `local.d`), never into users' home folders.

## Code standards (organization policy)

- Every script starts with a header block stating its purpose, inputs, usage
  and exit codes. Every function has a doc comment describing what it does,
  its arguments and its return value.
- Inline comments explain **why**, never restate what the code does.
- Never write change-tracking comments ("added", "updated per request",
  "new logic"). Code is always written as a clean final artifact.
- Shell: `set -euo pipefail` (except where failures are deliberately
  tolerated, which must be commented), quoted expansions, shellcheck-clean.
