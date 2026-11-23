# Shattered Vales OS

The Shattered Vales Studio workstation image: Fedora Silverblue with the
studio's tools, branding and macOS-style desktop built in. Built nightly by
GitHub Actions with [BlueBuild](https://blue-build.org) and signed with cosign.

| Image | For |
|---|---|
| `ghcr.io/shattered-vales-studio/shatteredvales-os` | AMD / Intel graphics |
| `ghcr.io/shattered-vales-studio/shatteredvales-os-nvidia` | NVIDIA (RTX 20xx / GTX 16xx and newer) |

Both are built on [BlueBuild's base images](https://github.com/blue-build/base-images)
(Fedora Silverblue 45 with codecs; the NVIDIA one adds prebuilt open-kernel
drivers). Verify a pulled image with the committed key:

```bash
cosign verify --key cosign.pub ghcr.io/shattered-vales-studio/shatteredvales-os:latest
```

## Moving an existing Silverblue machine onto the image

No reinstall needed. Check which image the hardware needs, then:

```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/shattered-vales-studio/shatteredvales-os:latest
systemctl reboot
# After reboot, move to the signed image so updates are verified:
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/shattered-vales-studio/shatteredvales-os:latest
systemctl reboot
```

**NVIDIA machines with Secure Boot on:** the driver modules are signed with
BlueBuild's key, which the firmware must trust once. After the first boot
into the NVIDIA image run `blujust enroll-secure-boot-key`, reboot, choose
*Enroll MOK* in the blue screen and enter the password `bluebuild`.

Existing users keep their own GNOME settings; the new defaults (dock, button
layout, wallpaper) only apply to settings they have never changed.

## New machines

Use the unattended USB installer built from `installer-template/` (kept in a
separate private repo because it holds secrets).

## What's included

- **In the image:** Firefox, Thunderbird, Chromium, Tailscale, Docker Engine,
  VS Code, Unity Hub, Claude Desktop, ArtCraft Launcher, Bitwarden CLI, SSH
  server, codecs, and for the NVIDIA image, prebuilt NVIDIA drivers.
- **Developer tooling in the image:**
  - Version control: Git, Git LFS, Subversion, Perforce CLI (`p4`), GitHub CLI
  - Toolchains: GCC, Clang, CMake, Ninja, Meson, GDB, LLDB, Go, .NET 10 SDK,
    Node.js 26 LTS with npm and pnpm, Python with pipx and uv
  - Graphics and performance: RenderDoc, Vulkan tools and validation layers,
    MangoHud, GameMode
  - Android, WearOS and XR: adb/fastboot, OpenXR, Monado
  - Desktop apps: GTK 3, WebKitGTK and app-indicator headers (Tauri ready)
- **Flatpaks on first boot:** Steam, Bitwarden, OBS, Remmina (RDP), Extension
  Manager, Flatseal, Blender, Krita, GIMP, Inkscape, Audacity, Godot (.NET),
  Android Studio, WiVRn (PC VR streaming to Quest), Postman, DBeaver,
  Qt Creator, Podman Desktop. The first boot downloads several GB, so allow time on a fresh
  install.
- **Per user at first login:** Claude Code, Rust (rustup), JetBrains Toolbox
  (for Rider and other JetBrains IDEs), Git LFS hooks, and an npm global
  prefix in `~/.local` so `npm install -g` works on the read-only system.
- **Desktop:** bottom dock, logo menu top left, clock and tray icons top right,
  window buttons on the left, branded boot, login and lock screens in the
  website's black and gold (Cinzel and Lato fonts, gold-foil artwork).

## Useful commands on a workstation

| Command | Does |
|---|---|
| `sv-gpu-image status` | Shows detected GPU and whether the right image is installed |
| `sudo sv-gpu-image apply` | Switches to the matching image after a GPU change |
| `sv-first-login` | Re-runs per-user setup (e.g. for SSH-only accounts) |
| `rpm-ostree rollback` | Boots the previous image if an update misbehaves |

## Developing

See `CLAUDE.md` for the full workflow. In short: `just branding`, `just build`,
`just test`.
