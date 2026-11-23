# Installer template

Copy this folder into a **separate private repository**. It holds secrets
(admin password hash, Tailscale auth key) and must never be committed to the
public image repo with real values.

## What the USB does

1. Boots Fedora's network installer with the embedded kickstart.
2. Detects an NVIDIA GPU and picks `shatteredvales-os-nvidia` or `shatteredvales-os`.
3. Picks the internal disk (largest NVMe, else largest non-USB disk), wipes it.
4. Names the machine `<prefix>-<last 8 of serial>`.
5. Pulls and installs the image, then switches to the signed image.
6. Creates the IT admin account with your SSH key, locks root.
7. On first boot, joins the tailnet and deletes the auth key.
8. Flatpaks install in the background; each user's first login installs Claude Code.

## Building

1. Download the **Fedora Everything netinstall** ISO (x86_64) for the same
   Fedora version as the image.
2. `cp secrets.env.example secrets.env` and fill it in.
3. `./build-iso.sh ~/Downloads/Fedora-Everything-netinst-x86_64-44-*.iso`
4. Write `build/shatteredvales-installer.iso` to a USB stick.

The install needs wired ethernet (the image is several GB). Test in a VM
before trusting a new build with real hardware: the disk is erased without a prompt.
