# Flash-Impulse brand assets

Original artwork, GPL-3.0 like the rest of the repo.

> The look is *inspired by* the Samsung One UI 8.5 update-screen aesthetic (overlapping
> matte spheres, orange↔blue gradient hotspots on a soft sage/cream field). It is **not**
> a copy of any Samsung asset — these SVGs are drawn from scratch so they can ship under
> the repo's license. Do not commit Samsung (or other third-party) wallpapers here.

## Files

| File | Purpose |
|------|---------|
| `wallpaper.svg` | Source for the default desktop wallpaper |
| `logo.svg` | Source for the app/shell logo (One UI squircle badge) |

Rendered outputs (regenerate with the commands below):

- `dots/.config/quickshell/ii/assets/images/default_wallpaper.png` — 3840×2160
- `dots/.local/share/icons/flash-impulse.svg` — copy of `logo.svg`, resolved by
  `Quickshell.iconPath("flash-impulse")` in the About panel

## Regenerate

```bash
# Wallpaper
rsvg-convert -w 3840 -h 2160 brand/wallpaper.svg \
  -o dots/.config/quickshell/ii/assets/images/default_wallpaper.png

# Logo (SVG is used directly; just keep the icon copy in sync)
cp brand/logo.svg dots/.local/share/icons/flash-impulse.svg
```

## Palette

Sampled from the rendered wallpaper; use these as the seed for the Material 3
Expressive × One UI theme (ROADMAP §7). One UI leans on **soft pastel accents over a
warm-neutral base**, so the saturated orange is the "expressive" pop, used sparingly.

| Role | Hex | Notes |
|------|-----|-------|
| Accent / primary | `#ff7a1a` | Expressive orange; hot core `#ff4d14`, warm `#ffab3a` |
| Secondary | `#7fb0d0` | Matte blue sphere; deep rim `#6b98b8` |
| Surface (light) | `#e9e7d9` | Sage-cream base; cooler `#e0e3d6`, warmer `#ece7d5` |
| Warm surface | `#e6d2b4` | The lower-right diagonal band |
| On-surface (light) | `#3a3d34` | Warm-neutral text |

For **dark mode** (the One UI target — pastel accents on a dark, sage-tinted base):

| Role | Hex |
|------|-----|
| Background | `#1a1c17` |
| Surface | `#23261f` |
| Primary (pastel orange) | `#f2955c` |
| Secondary (pastel blue) | `#9cc2dc` |
| On-surface | `#e5e4d7` |

These are a starting point, not final tokens — §7 will wire them through
`Appearance.qml` / matugen.
