# CLAUDE.md — Shattered Vales OS Studio Edition

You are working on Shattered Vales OS **Studio Edition**: the studio's
workstation OS, a custom Fedora Atomic (Silverblue) image built with
BlueBuild, published to GHCR as `shatteredvales-os(-nvidia)` and installed
on studio machines. It is built on **Core Edition**
(`Shattered-Vales-Studio/OS-Linux-FedoraSB-ShatteredValesOS_CoreEdition`),
which carries everything the editions share; read Core's CLAUDE.md too.
Read this whole file before making changes.

## How the system works

- Both recipes use Core's promoted image (`shatteredvales-os-core(-nvidia)`,
  `image-version: latest`) as their base and only add or replace. Core's
  changes and Fedora releases reach Studio at its next build after Core is
  promoted. **Anything that every edition should have belongs in Core**,
  not here; this repository holds only what is Studio-specific: developer
  tooling, Docker, Unity, Claude, the studio's Flatpaks, the `sv-*` tools,
  Git defaults, app folders and the screen-lock policy.
- `recipes/recipe-base.yml` and `recipes/recipe-nvidia.yml` differ **only** in
  `name`, `description` and `base-image`. Every other change goes in
  `recipes/common/*.yml` so the two images can never drift.
- `files/system/` is copied over Core's tree (first, so the repo files in
  `/etc/yum.repos.d` exist before the package steps). `files/scripts/` holds
  Studio's build-time scripts. Studio extends Core through drop-ins rather
  than copies of Core's files:
  - desktop defaults: `etc/dconf/db/local.d/50-shatteredvales-studio`
    (overrides Core's `10-…`, the later name wins), plus
    `20-shatteredvales-app-folders` and `locks/`;
  - per-user setup: `usr/libexec/shatteredvales/first-login.d/50-studio.sh`
    (registers `STEPS` with Core's framework);
  - support checks: `usr/libexec/shatteredvales/sv-doctor.d/50-studio.sh`
    (registers `EDITION_CHECKS`);
  - release gate: `usr/share/shatteredvales/verify.d/studio.list` and
    `usr/libexec/shatteredvales/verify.d/*.sh`.
  Firefox's policy, `mimeapps.list`, Chromium's policies and
  `artcraft-apps.list` are whole files that replace Core's.
- Studio's Flatpaks are a second `default-flatpaks` configuration that
  BlueBuild appends to Core's; list only apps Core does not install.
- The recipes re-run Core's build steps from the image
  (`/usr/libexec/shatteredvales/build/apply-branding.sh`, then signing and
  `verify-image.sh`), so Studio's brand.env, artwork and dconf files apply.
- `branding/` holds Studio's `brand.env` (Core's with Studio's edition
  block) and `icons/*.glyph` for the studio launchers. The lock screen and
  boot splash show the company name, "Shattered Vales / Studio Inc.", in
  foil (`BRAND_NAME_LINE2_STYLE="foil"`); "Studio Edition" appears in the
  edition gold wherever "Shattered Vales OS" does (Settings > About, login
  screen, boot menu, banners, os-release). `just branding` renders with
  Core's renderer, fonts and logo, writing only the edition-specific
  artwork into `files/system`. Never hand-edit those generated files.
  Check contrast for any new colour pairing before using it (AAA 7:1).
- Moving a Silverblue machine onto Studio uses Core's
  `sv-migrate.sh --edition studio`.
- USB installers live in the public `Shattered-Vales-Studio/OS-Installer`
  repo. Never put real secrets (admin hashes, Tailscale or other keys) in
  any repository.

## Commands

| Command | Purpose |
|---|---|
| `just branding` | Render Studio's artwork with Core's renderer (`CORE_REF=<branch>` optional) |
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

- Keep the two recipes identical apart from `name`, `description` and
  `base-image`.
- Never bake self-updating tools (Claude Code, rustup-style installers) into
  `/usr`; it is read-only on workstations. Per-user tools go in
  `first-login.d/50-studio.sh` as a new versioned step
  (`STEPS+=("<name>-v1 <function>")`). Bump the suffix to force a step to
  run again for everyone.
- Packages that install into `/opt` are relocated to `/usr/lib/opt` by the
  BlueBuild CLI (v0.9.23+) for every module, including scripts. dnf `optfix`
  is deprecated and does nothing; do not add it. Add the relocated payload
  as a `path` rule in `verify.d/studio.list` so a regression fails the build.
- The release gate is Core's `verify-image.sh`. When adding Studio software
  or files, add an `rpm` or `path` rule to `verify.d/studio.list`.
- GNOME's settings and extension keys can change between releases. When Core
  moves to a new Fedora release, re-check Studio's dconf keys and app
  folders on Core's `:testing` before Core is promoted.
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
