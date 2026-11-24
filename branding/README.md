# Branding sources (Studio Edition)

Studio Edition's artwork is rendered by Core Edition's renderer with Core's
fonts, logo and wallpaper generator, so every edition shares one look.
This folder holds only what makes Studio different:

| File | What it is |
|---|---|
| `brand.env` | A copy of Core's `branding/brand.env` with Studio's edition block: name, id, image name, repository, the company wordmark ("Shattered Vales / Studio Inc.", drawn in foil) and the edition gold (contrast ratios beside it) |
| `icons/shatteredvales-new-project.glyph`, `icons/shatteredvales-github-setup.glyph` | SVG elements of the New Project and GitHub Setup launcher glyphs, drawn on Core's dark tile |

`just branding` fetches Core into `build/core` (git-ignored; set `CORE_REF`
to render with a Core branch) and renders. Never hand-edit the generated
files; change this folder and re-render. When Core's `brand.env` gains a
value, copy it here too.

## Generated outputs

Only the artwork that names the edition is written into `files/system`;
wallpapers, account pictures, logo icons, the boot-menu frame and fonts
and the terminal logo come from Core's image.

| Output | Used by |
|---|---|
| `usr/share/shatteredvales/lockscreen-header.png` | Logo and "Shattered Vales / Studio Inc." above the lock clock |
| `usr/share/plymouth/themes/shatteredvales/watermark.png` | Boot splash |
| `usr/share/pixmaps/shatteredvales-gdm-logo.png` | Login screen logo (mark, OS name, Studio Edition) |
| `usr/share/pixmaps/fedora_logo_med.png`, `fedora_whitelogo_med.png` | Settings > About lockup with the gold edition line (light and dark mode) |
| `usr/share/shatteredvales/grub-theme/logo.png`, `theme.txt` | Boot menu logo and its placement |
| `usr/share/icons/hicolor/scalable/apps/shatteredvales-{new-project,github-setup}.svg` | Studio launchers |
| `usr/share/shatteredvales/brand.env` | Build scripts inside the image |
