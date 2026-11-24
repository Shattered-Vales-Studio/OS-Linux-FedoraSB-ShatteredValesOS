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

## Release channels

| Tag | Who runs it | Updated |
|---|---|---|
| `:testing` | One or two canary machines | Every build from `main` (nightly) |
| `:latest` | Every other workstation | Weekly (Tuesdays) by the *promote-images* workflow, or on demand |
| `:stable-YYYYMMDD` | Nobody directly; rollback points | Each promotion |

Promotion re-tags the already-signed `:testing` image after verifying its
signature; nothing is rebuilt. To **hold** promotions while investigating a
problem, set the repository variable `PAUSE_PROMOTION` to `true`. To **roll
back** the whole studio, run *promote-images* manually with `source` set to
an earlier `stable-YYYYMMDD` tag. A single machine can always go back with
`rpm-ostree rollback`.

To make a machine a canary, use the `:testing` tag in the rebase commands
below; `sv-gpu-image apply` keeps whichever tag a machine is on.

## Moving an existing Silverblue machine onto the image

No reinstall needed: accounts, files, settings and Flatpak apps all stay.
On the machine, in a terminal:

```bash
curl -fsSLO https://raw.githubusercontent.com/Shattered-Vales-Studio/OS-Linux-FedoraSB-ShatteredValesOS/main/sv-migrate.sh
bash sv-migrate.sh
```

(`wget https://raw.githubusercontent.com/Shattered-Vales-Studio/OS-Linux-FedoraSB-ShatteredValesOS/main/sv-migrate.sh`
works too.) The script checks the machine, picks the NVIDIA or standard
image from the hardware, removes packages layered with `rpm-ostree install`
that would clash with the image (Node.js, RPM Fusion's NVIDIA driver,
`kernel-devel`, Fedora's Docker packages), prints the plan, and only then
asks to go ahead. After the restart the image switches itself to the
signature-verified copy, which applies at the next restart. Run `sv-doctor`
afterwards.

| Option | Does |
|---|---|
| `--dry-run` | Print the plan and change nothing |
| `--testing` | Use the canary channel instead of `:latest` |
| `--nvidia` / `--base` | Override the image picked from the hardware |
| `--remove-all-layered` | Also remove layered packages that do not clash; updates are faster and fully automatic without them |
| `--yes` | Do not ask before rebasing or restarting |

**NVIDIA machines with Secure Boot on:** the driver modules are signed with
BlueBuild's key, which the firmware must trust once. After the first boot
into the NVIDIA image run `blujust enroll-secure-boot-key`, reboot, choose
*Enroll MOK* in the blue screen and enter the password `bluebuild`. The
script reminds you when this applies.

Existing users keep their own GNOME settings; the new defaults (dock, button
layout, wallpaper, app folders) only apply to settings they have never
changed. To take the studio's app folders on an existing account, run
`dconf reset -f /org/gnome/desktop/app-folders/ && dconf reset /org/gnome/shell/app-picker-layout`
and log out straight away.

## New machines

Build a USB installer with
[Shattered-Vales-Studio/OS-Installer](https://github.com/Shattered-Vales-Studio/OS-Installer)
(`./build-iso.sh --edition studio ...`) and write it with balenaEtcher. The
Studio stick installs unattended and erases the internal disk.

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
  - Desktop apps: GTK 3, WebKitGTK and app-indicator headers (Tauri ready),
    MinGW Windows cross-compilers, flatpak-builder, rpm-build
  - Virtual machines: virt-manager with QEMU/KVM (users are added to the
    `libvirt` group at boot)
- **Flatpaks on first boot:** GNOME's core apps (image, PDF, video and audio
  viewers, Text Editor, Calculator, Calendar, Archive Manager, Disk Usage and
  more), Steam, Bitwarden, OBS, Remmina (RDP), Extension
  Manager, Flatseal, Blender, Krita, GIMP, Inkscape, Audacity, Godot (.NET),
  Android Studio, WiVRn (PC VR streaming to Quest), Postman, DBeaver,
  Qt Creator, Podman Desktop, BoxBuddy, Tiled, F3D, Flameshot, Parsec, Slack,
  Discord, VLC, HandBrake, MakeMKV (free for DVDs; Blu-ray needs its beta key
  or a licence). The first boot downloads several GB, so allow time on a fresh
  install.
- **ArtCraft at first login:** the 17 official Craft apps (PhotoCraft,
  VectorCraft, FilmCraft, WordCraft, GridCraft, DeckCraft, CADCraft and the
  rest, about 1.1 GB) install for each user as Flatpak bundles, checksum
  verified, exactly as ArtCraft Launcher installs them; the launcher then
  keeps them updated. Community apps (SolidCraft, MailCraft) are one click
  away in the launcher.
- **Default apps:** Craft apps open work files (PSD/KRA/EXR, SVG/AI, raw
  photos, PDF, Word/Excel/PowerPoint, DXF/DWG and more); GNOME's viewers open
  plain images, video and audio, with the Craft app offered second; 3D
  models open in F3D, `.blend` in Blender, code in VS Code, and email links
  in Thunderbird. Users can change any of these in Settings.
- **MCP servers for Claude:** at first login each user gets the Unity
  Editor MCP (Claude Code and Claude Desktop), Google Play Developer and
  Shopify Dev MCP. GitHub's MCP comes from the studio's Claude organization
  and signs in with the GitHub CLI's token automatically (no personal access
  token needed); the claude.ai connectors (Atlassian, Google Workspace,
  Slack, ...) follow each person's Claude sign-in.
- **Devices:** adb and fastboot work without root for Meta Quest headsets,
  WearOS watches and Android phones of any brand.
- **Per user at first login:** Claude Code, the Unity CLI, Rust (rustup), JetBrains Toolbox
  (for Rider and other JetBrains IDEs), Git LFS hooks, and an npm global
  prefix in `~/.local` so `npm install -g` works on the read-only system.
- **Homebrew:** installed at first login into `/home/linuxbrew/.linuxbrew`
  by the first administrator who logs in, except the installer's IT
  account (Homebrew allows one owner per machine; other accounts can run
  what it installs). Use it for command-line
  tools instead of `rpm-ostree install`, which slows every update. Brew's
  tools come after the system's on `PATH`, so a formula never replaces the
  image's own Python or GCC; add `eval "$(brew shellenv)"` to `~/.bashrc` to
  put brew first.
- **mise:** per-project tool versions. Add a `mise.toml` (or
  `.tool-versions`) to a repository, run `mise install`, and Node, Python,
  Go, .NET, Java and others switch automatically when you `cd` into it;
  scripts and Claude Code get the same versions through mise's shims. Set
  `SV_MISE=0` to turn it off.
- **Ubuntu containers:** `sv-box` opens an Ubuntu 24.04 container with build
  tools, your home folder and, on NVIDIA machines, the GPU, for SDKs that
  only support Ubuntu. Nothing is installed on the OS itself.
- **GitHub setup:** *GitHub Setup* in the app grid (or `sv-github setup`)
  follows the studio guides: Git identity, GitHub CLI sign-in, an SSH key
  uploaded with `gh`, and `~/Source`. The same key signs every commit and
  tag, so GitHub marks them *Verified*; accounts set up earlier turn this on
  with `sv-github signing`. `sv-github add-profile <alias>` adds a
  second GitHub account per *Managing Multiple GitHub SSH Keys*;
  `sv-github clone <alias> <owner/repo>` and `sv-github use <alias>` apply it.
- **Git defaults:** `/etc/gitconfig` holds the settings from the *Daily Git
  Terminal Workflow* guide, Git LFS, and Unity Smart Merge for whichever
  Unity editor is installed. Users' own `git config --global` still wins.
- **New projects:** *New Claude Project* in the app grid (or
  `sv-new-project [repo-name]`) creates a repository from
  `Template-ClaudeProject`, runs its setup script, and starts Claude Code in
  the template's design interview. Without a name it makes a local-only
  folder you can publish later.
- **Policies:** the screen locks after 30 minutes idle (users cannot change
  this). Desktops never suspend on mains power, so overnight builds and
  remote access keep working; laptops still sleep on battery. A
  notification asks people to restart when an update has waited 3+ days.
- **Files:** `~/Source` in the sidebar, and right-click > *New Document*
  templates (README, Markdown, text, Unity C#, Godot, shell and Python
  scripts that follow the studio documentation standard). In a terminal,
  `cd <repo>` reaches any repository in `~/Source` from anywhere.
- **Windows shares:** Windows PCs and NAS boxes appear under *Network* in
  Files (the firewall allows WS-Discovery, UDP 3702). Any share opens with
  *Other Locations* > *Connect to Server* and `smb://server/share`; tick
  *Remember forever* to keep the password in your keyring. Shares listed in
  `/etc/shatteredvales/network-shares` (one per line, `\\server\share` or
  `smb://` form, optional sidebar name) are pinned in every user's Files
  sidebar at login. Dolphin is installed for people who prefer it.
- **Docker:** container logs rotate (3 files of 10 MB) instead of filling the disk.
- **Terminal:** a Git-aware bash prompt with the branch in brand gold. Set
  `SV_PROMPT=0` to keep your own.
- **Browsers:** Firefox and Chromium show a managed *Shattered Vales*
  bookmarks folder (website, guides, staff resources) on the toolbar.
- **Desktop:** bottom dock, logo menu top left, clock and tray icons top right,
  window buttons on the left, branded boot, login and lock screens in the
  website's black and gold (Cinzel, Lato and JetBrains Mono, gold-foil
  artwork).

## Useful commands on a workstation

| Command | Does |
|---|---|
| `sv-gpu-image status` | Shows detected GPU and whether the right image is installed |
| `sudo sv-gpu-image apply` | Switches to the matching image after a GPU change |
| `sv-first-login` | Re-runs per-user setup (e.g. for SSH-only accounts) |
| `sv-doctor` | Health check for support; `sv-doctor --copy` copies the report to paste into a message |
| `sv-update` | Shows the waiting OS update and what it changes; `now` updates immediately, `rollback` goes back. *System Update* in the app grid runs `sv-update now` |
| `sv-branch <issue>` | Creates `feature/issue-<n>-<title>` from the latest `Dev` |
| `sv-rebase` | The guide's safe rebase onto `Dev`: backup, fetch, rebase, push with lease; `--continue` after conflicts |
| `sv-lfs-init unity\|godot\|blender` | Adds the LFS guide's `.gitattributes` (with lockable art) and engine `.gitignore` to a repo |
| `sv-unity [open]` | Installs the Unity editor version a project needs (plus Android build support), optionally opens it |
| `sv-env <item> -- <cmd>` | Runs a command with secrets from the Bitwarden vault as environment variables; no `.env` files |
| `sv-quest run <file.apk>` | Installs a build on a Quest, launches it and follows the Unity log; `wifi`, `devices`, `log`, `launch` too |
| `sv-clean` | Frees disk space from caches only (Docker, npm, NuGet, uv, Go, thumbnails, old logs), asking first |
| `sv-new-project [name]` | New project from the Claude template, straight into the design interview |
| `sv-github setup` | Connects the account to GitHub (same as *GitHub Setup*) |
| `sv-github list` | Shows GitHub profiles; `sv-github test [alias]` checks one |
| `sv-github signing` | Turns on Verified (signed) commits for an account set up before signing was added |
| `sv-box [enter\|create\|run\|export\|list\|rm]` | Ubuntu containers for Ubuntu-only SDKs; plain `sv-box` enters the default one, creating it first |
| `brew install <tool>` | Command-line tools without layering packages onto the OS |
| `mise use node@22` | Pins a tool version for the current project (writes `mise.toml`) |
| `rpm-ostree rollback` | Boots the previous image if an update misbehaves |

## Developing

See `CLAUDE.md` for the full workflow. In short: `just branding`, `just build`,
`just test`.
