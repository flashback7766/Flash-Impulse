# Flash-Impulse brand assets

Original artwork, GPL-3.0 like the rest of the repo.

> The look — overlapping matte spheres, orange↔blue gradient hotspots on a soft
> sage/cream field — was worked out against a Samsung update-screen wallpaper as a
> reference. It is **not** a copy of any Samsung asset: these SVGs are drawn from
> scratch so they can ship under the repo's license. Do not commit Samsung (or other
> third-party) wallpapers here.

## Files

| File | Purpose |
|------|---------|
| `wallpaper.svg` | Source for the default desktop wallpaper |
| `logo.svg` | Source for the app/shell logo (squircle badge) |

Rendered outputs (regenerate with the commands below):

- `dots/.config/quickshell/flash-impulse/assets/images/default_wallpaper.png` — 3840×2160
- `dots/.config/quickshell/flash-impulse/assets/images/default_wallpaper_dark.png` — the same
  composition with a dark ground, swapped in with the theme
- `dots/.local/share/icons/flash-impulse.svg` — copy of `logo.svg`, resolved by
  `Quickshell.iconPath("flash-impulse")` in the About panel

## Regenerate

```bash
python3 brand/render_wallpapers.py
cp brand/logo.svg dots/.local/share/icons/flash-impulse.svg
```

`render_wallpapers.py` re-implements the geometry of `wallpaper.svg` in float rather than
shelling out to `rsvg-convert`, and writes both variants. The reason is banding: the
artwork is almost entirely wide, shallow gradients, and every SVG renderer here writes
8 bit, so a gradient that moves one code per ~100 px turns those steps into visible
contour rings — mild on the light version, obvious on the dark one against a near-black
ground. Rendering in float and quantising once with triangular dither scatters the step
boundary into noise instead. Measured along a column through the top-left sphere, the gap
between code changes went from 104 px to about 2.

The palette for the dark variant lives at the top of that script, next to the light one.

## Palette

Sampled from the rendered wallpaper; use these as the seed for the Material 3
Expressive theme (ROADMAP §7). The target is **soft pastel accents over a warm-neutral
base**, so the saturated orange is the "expressive" pop, used sparingly.

| Role | Hex | Notes |
|------|-----|-------|
| Accent / primary | `#ff7a1a` | Expressive orange; hot core `#ff4d14`, warm `#ffab3a` |
| Secondary | `#7fb0d0` | Matte blue sphere; deep rim `#6b98b8` |
| Surface (light) | `#e9e7d9` | Sage-cream base; cooler `#e0e3d6`, warmer `#ece7d5` |
| Warm surface | `#e6d2b4` | The lower-right diagonal band |
| On-surface (light) | `#3a3d34` | Warm-neutral text |

For **dark mode** (pastel accents on a dark, sage-tinted base):

| Role | Hex |
|------|-----|
| Background | `#1a1c17` |
| Surface | `#23261f` |
| Primary (pastel orange) | `#f2955c` |
| Secondary (pastel blue) | `#9cc2dc` |
| On-surface | `#e5e4d7` |

These are a starting point, not final tokens — §7 will wire them through
`Appearance.qml` / matugen.
