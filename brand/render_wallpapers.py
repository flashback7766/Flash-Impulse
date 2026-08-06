#!/usr/bin/env python3
"""Render the default wallpapers from the vector description in wallpaper.svg.

Why this exists instead of `rsvg-convert wallpaper.svg`: the artwork is almost
entirely wide, shallow gradients, and every SVG renderer we have writes 8-bit
output. A gradient that moves one step per ~100px turns those steps into visible
contour rings — mild on the light version, glaring once the dark version pulls
the same geometry down against a near-black ground.

So the geometry is evaluated here in float and quantised once, with triangular
dither, which scatters the step boundary into noise the eye integrates away.

    python3 brand/render_wallpapers.py

Writes both wallpapers into the quickshell assets directory.
"""

import os
import numpy as np
from PIL import Image

W, H = 3840, 2160
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "../dots/.config/quickshell/flash-impulse/assets/images")


def hex_rgb(s):
    s = s.lstrip("#")
    return np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255.0


# ---------------------------------------------------------------- palettes ---
# Light is the original artwork. Dark keeps the composition, the blue sphere and
# the orange seams untouched, and swaps the pale ground — plus the cream spheres
# that are made of the same pale family — for dark tones. The spheres keep their
# centre-lighter-than-rim ordering, so they still read as lit forms.
PALETTES = {
    "light": {
        "bg": ["#e0e3d6", "#e9e7d9", "#ece7d5"],
        "band": [("#e7cd9c", 0.50), ("#ead9bd", 0.20), ("#e8e6d8", 0.0)],
        "cream": ["#f5f0e5", "#eae2d3", "#ded4c3"],
        "creamWarm": ["#f3ecdd", "#eddec7", "#e6d2b4"],
    },
    "dark": {
        "bg": ["#12150f", "#171a13", "#1b1c14"],
        "band": [("#6b5326", 0.34), ("#4a4028", 0.14), ("#1b1c14", 0.0)],
        "cream": ["#333026", "#26231b", "#191710"],
        "creamWarm": ["#3a3223", "#2c2418", "#1e1810"],
        # Same sphere, dimmed to about half so it sits in the scene instead of
        # floating over it as a headlight; the stop ordering, and therefore the
        # lit-from-upper-left read, is unchanged.
        "blue": ["#65777f", "#4c6474", "#3b586c", "#375468"],
        # The seam colour is the light version's. Only the falloff is tighter:
        # over cream, the wide tail reads as a warm blush, but over a near-black
        # ground the same tail is a tan fog with no shape to it.
        "glow": [("#ff4d14", 1.0), ("#ff6f18", 1.0),
                 ("#ff8c22", 0.55), ("#ffb347", 0.0)],
    },
}

PALETTES["light"]["blue"] = ["#bfd6e1", "#8fb6cf", "#72a0bf", "#6b98b8"]
PALETTES["light"]["glow"] = [("#ff4d14", 1.0), ("#ff6f18", 1.0),
                             ("#ff9d2e", 0.75), ("#ffb347", 0.0)]

BLUE_OFFSETS = (0.0, 0.5, 0.85, 1.0)
GLOW_OFFSETS = (0.0, 0.22, 0.5, 1.0)

BLUR_SIGMA = 3.0


def ramp(t, stops):
    """Piecewise-linear stop interpolation, in sRGB space like SVG does."""
    offs = np.array([s[0] for s in stops], np.float32)
    cols = np.stack([s[1] for s in stops])          # (n, C)
    out = np.empty(t.shape + (cols.shape[1],), np.float32)
    out[:] = cols[0]
    for i in range(len(offs) - 1):
        a, b = offs[i], offs[i + 1]
        f = np.clip((t - a) / max(b - a, 1e-9), 0.0, 1.0)
        m = t >= a
        seg = cols[i] + (cols[i + 1] - cols[i]) * f[..., None]
        out = np.where(m[..., None], seg, out)
    return out


def linear_gradient(p0, p1, stops):
    """SVG linearGradient evaluated over the whole canvas."""
    x = np.arange(W, dtype=np.float32)[None, :]
    y = np.arange(H, dtype=np.float32)[:, None]
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    t = ((x - p0[0]) * dx + (y - p0[1]) * dy) / (dx * dx + dy * dy)
    return ramp(np.clip(t, 0, 1), stops)


def circle_field(cx, cy, r, gcx, gcy, gr, stops):
    """A radialGradient in objectBoundingBox units, over a circle's own bbox,
    together with the circle's antialiased coverage mask."""
    d = 2.0 * r
    ox, oy = cx - r, cy - r
    fx, fy = ox + gcx * d, oy + gcy * d
    frad = gr * d

    x = np.arange(W, dtype=np.float32)[None, :]
    y = np.arange(H, dtype=np.float32)[:, None]
    dist_grad = np.hypot(x - fx, y - fy)
    rgba = ramp(np.clip(dist_grad / frad, 0, 1), stops)

    # Analytic coverage: one pixel of feathering across the true edge.
    dist_edge = np.hypot(x - cx, y - cy)
    mask = np.clip(r + 0.5 - dist_edge, 0.0, 1.0).astype(np.float32)
    return rgba, mask


def gaussian_blur(img, sigma):
    """Separable gaussian on premultiplied float RGBA, edges clamped."""
    radius = int(np.ceil(sigma * 3))
    k = np.exp(-0.5 * (np.arange(-radius, radius + 1) / sigma) ** 2)
    k /= k.sum()
    for axis in (0, 1):
        pad = [(0, 0)] * img.ndim
        pad[axis] = (radius, radius)
        p = np.pad(img, pad, mode="edge")
        acc = np.zeros_like(img)
        for i, w in enumerate(k):
            sl = [slice(None)] * img.ndim
            sl[axis] = slice(i, i + img.shape[axis])
            acc += w * p[tuple(sl)]
        img = acc
    return img


def over(dst_rgb, src_rgba):
    """Source-over of a straight-alpha layer onto an opaque backdrop."""
    a = src_rgba[..., 3:4]
    return dst_rgb * (1.0 - a) + src_rgba[..., :3] * a


def premul(rgb, alpha):
    return np.concatenate([rgb * alpha[..., None], alpha[..., None]], axis=-1)


def unpremul(p):
    a = np.maximum(p[..., 3:4], 1e-6)
    return np.concatenate([p[..., :3] / a, p[..., 3:4]], axis=-1)


def layer_over(base_premul, add_premul):
    a = add_premul[..., 3:4]
    return add_premul + base_premul * (1.0 - a)


def render(variant):
    pal = PALETTES[variant]

    # Ground.
    bg_stops = [(o, hex_rgb(c)) for o, c in zip((0.0, 0.5, 1.0), pal["bg"])]
    img = linear_gradient((0, 0), (W, H), bg_stops)

    # Diagonal band in the bottom-right corner.
    band_stops = [(o, np.concatenate([hex_rgb(c), [a]]))
                  for o, (c, a) in zip((0.0, 0.5, 1.0), pal["band"])]
    band = linear_gradient((2380, H), (W, 0), band_stops)
    x = np.arange(W, dtype=np.float32)[None, :]
    y = np.arange(H, dtype=np.float32)[:, None]
    # Triangle (3840,0) (3840,2160) (2380,2160): everything right of the
    # hypotenuse, feathered by a pixel.
    edge = (x - 2380) * H - y * (W - 2380)
    tri = np.clip(0.5 - edge / np.hypot(H, W - 2380), 0.0, 1.0)
    band[..., 3] *= tri
    img = over(img, band)

    # --- spheres, blurred as one group (the SVG's filter="url(#soft)") -------
    group = np.zeros((H, W, 4), np.float32)
    blue_stops = [(o, hex_rgb(c)) for o, c in zip(BLUE_OFFSETS, pal["blue"])]
    cream_stops = [(o, hex_rgb(c)) for o, c in zip((0.0, 0.6, 1.0), pal["cream"])]
    warm_stops = [(o, hex_rgb(c)) for o, c in zip((0.0, 0.55, 1.0), pal["creamWarm"])]

    for (cx, cy, r), (gcx, gcy, gr), stops in (
        ((2740, 1000, 920), (0.37, 0.32, 0.85), blue_stops),
        ((760, 520, 780), (0.40, 0.34, 0.90), cream_stops),
        ((820, 1660, 640), (0.42, 0.36, 0.90), warm_stops),
        ((1760, 1060, 720), (0.40, 0.34, 0.90), cream_stops),
    ):
        rgb, mask = circle_field(cx, cy, r, gcx, gcy, gr, stops)
        group = layer_over(group, premul(rgb, mask))
    group = gaussian_blur(group, BLUR_SIGMA)
    img = over(img, unpremul(group))

    # --- orange seams, clipped to the sphere in front, blurred as one group --
    glow_stops = [(o, np.concatenate([hex_rgb(c), [a]]))
                  for o, (c, a) in zip(GLOW_OFFSETS, pal["glow"])]
    seams = np.zeros((H, W, 4), np.float32)
    for (cx, cy, r), (clip_cx, clip_cy, clip_r) in (
        ((1150, 640, 620), (1760, 1060, 720)),
        ((1120, 1560, 560), (1760, 1060, 720)),
        ((1360, 1360, 520), (820, 1660, 640)),
    ):
        rgba, mask = circle_field(cx, cy, r, 0.5, 0.5, 0.5, glow_stops)
        clip = np.clip(clip_r + 0.5 - np.hypot(x - clip_cx, y - clip_cy), 0.0, 1.0)
        seams = layer_over(seams, premul(rgba[..., :3], rgba[..., 3] * mask * clip))
    seams = gaussian_blur(seams, BLUR_SIGMA)
    img = over(img, unpremul(seams))

    return np.clip(img, 0.0, 1.0)


def quantise(img, seed):
    """Float -> 8 bit with triangular-PDF dither.

    Plain rounding is what produced the contour rings: a gradient this shallow
    holds the same code for ~100 px, so the eye sees a hard edge where it flips.
    A dither of +-1 LSB moves that edge into per-pixel noise instead, which at
    4K is far below what anyone can see and costs about a megabyte of PNG.
    """
    rng = np.random.default_rng(seed)
    v = img * 255.0
    noise = rng.random(v.shape, np.float32) - rng.random(v.shape, np.float32)
    return np.round(np.clip(v + noise, 0, 255)).astype(np.uint8)


if __name__ == "__main__":
    for variant, seed, name in (("light", 1, "default_wallpaper.png"),
                                ("dark", 2, "default_wallpaper_dark.png")):
        out = quantise(render(variant), seed)
        path = os.path.abspath(os.path.join(OUT, name))
        Image.fromarray(out).save(path, optimize=True)
        print(f"{name}: mean {out.mean():6.2f}  "
              f"{os.path.getsize(path) / 1e6:.2f} MB  -> {path}")
