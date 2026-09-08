#!/usr/bin/env python3
"""Shading primitives for the gem and jewellery icon generators.

WHY THIS EXISTS
---------------
The first pass drew flat polygon fills with a hard black outline, and
composited a finished stone on top of a finished band. Two things were wrong
with that and both are structural, not tuning:

  * FLAT. A facet filled with one colour has no light in it. Real stone icons
    live on a wide value range -- deep shadow through a near-white specular --
    plus a rim light on the shadow side, which is the single cue that reads as
    "three-dimensional object" rather than "coloured shape".
  * DETACHED. Pasting a stone over a band leaves the two objects sharing no
    light, no contact shadow and no metal crossing in front of the stone. The
    eye reads two stickers. A setting has to OVERLAP its stone -- claws in
    front, a cup behind, a shadow where they meet.

So everything here works on a float32 RGBA buffer at the supersampled size:
polygons get real gradients, metal gets a shaded cross-section instead of a
flat stroke, and shadows are blurred masks rather than drawn shapes. Composite
order can then interleave stone and metal, which is what "attached" means.

Coordinates are supersampled pixels throughout; the callers downsample once at
the end.
"""

from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# Light direction, shared by every surface in the set so a stone and the claw
# holding it are lit from the same place. Slightly in front (+z) of upper-left.
LIGHT = np.array([-0.52, -0.68, 0.52], dtype=np.float32)
LIGHT /= np.linalg.norm(LIGHT)


class Canvas:
    """Float RGBA accumulation buffer. Values 0..1, alpha straight (not
    premultiplied) -- `over` does the compositing."""

    def __init__(self, size: int):
        self.size = size
        self.rgb = np.zeros((size, size, 3), dtype=np.float32)
        self.a = np.zeros((size, size), dtype=np.float32)
        ax = np.arange(size, dtype=np.float32)
        self.X, self.Y = np.meshgrid(ax, ax)

    def over(self, rgb, alpha) -> None:
        """Source-over: [param rgb] may be a colour triple or a full array."""
        src = np.asarray(rgb, dtype=np.float32)
        if src.ndim == 1:
            src = np.broadcast_to(src, self.rgb.shape)
        a = np.clip(alpha, 0.0, 1.0)[..., None]
        out_a = a[..., 0] + self.a * (1.0 - a[..., 0])
        safe = np.maximum(out_a, 1e-6)[..., None]
        self.rgb = (src * a + self.rgb * self.a[..., None] * (1.0 - a)) / safe
        self.a = out_a

    def image(self, out_size: int) -> Image.Image:
        rgb = np.clip(self.rgb * 255.0 + 0.5, 0, 255).astype(np.uint8)
        a = np.clip(self.a * 255.0 + 0.5, 0, 255).astype(np.uint8)
        im = Image.fromarray(np.dstack([rgb, a]), "RGBA")
        return im.resize((out_size, out_size), Image.LANCZOS)


def poly_mask(size: int, pts, feather: float = 0.9) -> np.ndarray:
    """Antialiased coverage mask for a polygon, as float 0..1.

    Drawn at 4x and boxed down: PIL has no antialiased polygon fill, and a hard
    mask makes every facet edge crawl once the icon is downsampled.
    """
    ss = 4
    m = Image.new("L", (size * ss, size * ss), 0)
    ImageDraw.Draw(m).polygon([(x * ss, y * ss) for x, y in pts], fill=255)
    m = m.resize((size, size), Image.BOX)
    if feather > 0:
        m = m.filter(ImageFilter.GaussianBlur(feather))
    return np.asarray(m, dtype=np.float32) / 255.0


def stroke_mask(size: int, pts, width: float, closed: bool = True,
                feather: float = 0.8) -> np.ndarray:
    ss = 2
    m = Image.new("L", (size * ss, size * ss), 0)
    seq = [(x * ss, y * ss) for x, y in pts]
    if closed:
        seq = seq + [seq[0]]
    ImageDraw.Draw(m).line(seq, fill=255, width=max(1, int(width * ss)),
                           joint="curve")
    m = m.resize((size, size), Image.BOX)
    if feather > 0:
        m = m.filter(ImageFilter.GaussianBlur(feather))
    return np.asarray(m, dtype=np.float32) / 255.0


def ramp(canvas: Canvas, pts, direction, lo: float, hi: float) -> np.ndarray:
    """0..1 linear ramp along [param direction] across a polygon's own extent.

    Normalising to the FACET's extent rather than the icon's is what keeps a
    small facet from receiving a single flat slice of a global gradient.
    """
    dx, dy = direction
    proj = canvas.X * dx + canvas.Y * dy
    vals = [p[0] * dx + p[1] * dy for p in pts]
    lo_v, hi_v = min(vals), max(vals)
    if hi_v - lo_v < 1e-3:
        return np.full_like(proj, 0.5)
    t = (proj - lo_v) / (hi_v - lo_v)
    return lo + (hi - lo) * np.clip(t, 0.0, 1.0)


def fill_facet(canvas: Canvas, pts, colour, *, contrast: float = 0.34,
               direction=None) -> None:
    """A facet with light across it instead of one flat tone."""
    if direction is None:
        direction = (-LIGHT[0], -LIGHT[1])
    m = poly_mask(canvas.size, pts)
    t = ramp(canvas, pts, direction, 1.0 + contrast * 0.5, 1.0 - contrast * 0.5)
    col = np.asarray(colour, dtype=np.float32)[None, None, :] * t[..., None]
    canvas.over(np.clip(col, 0.0, 1.0), m)


def shadow(canvas: Canvas, mask: np.ndarray, *, offset=(0.0, 0.0),
           blur: float = 6.0, strength: float = 0.55, colour=(0.03, 0.02, 0.05)
           ) -> None:
    """Soft contact shadow from an existing mask -- what tells the eye two
    parts touch rather than merely overlap."""
    im = Image.fromarray((np.clip(mask, 0, 1) * 255).astype(np.uint8), "L")
    if offset != (0.0, 0.0):
        im = im.transform(im.size, Image.AFFINE,
                          (1, 0, -offset[0], 0, 1, -offset[1]),
                          resample=Image.BILINEAR)
    im = im.filter(ImageFilter.GaussianBlur(blur))
    canvas.over(np.asarray(colour, dtype=np.float32),
                np.asarray(im, dtype=np.float32) / 255.0 * strength)


def inner_glow(canvas: Canvas, mask: np.ndarray, colour, *, width: float = 5.0,
               strength: float = 0.8, direction=None) -> np.ndarray:
    """A rim of light just inside a silhouette edge.

    Directional: full strength where the edge faces [param direction], fading
    to nothing on the opposite side. This is the rim light, and it does more
    for "solid object" than any amount of interior shading.
    """
    im = Image.fromarray((np.clip(mask, 0, 1) * 255).astype(np.uint8), "L")
    eroded = im.filter(ImageFilter.MinFilter(_odd(width)))
    rim = np.clip(np.asarray(im, np.float32) - np.asarray(eroded, np.float32),
                  0, 255) / 255.0
    rim = np.asarray(Image.fromarray((rim * 255).astype(np.uint8), "L")
                     .filter(ImageFilter.GaussianBlur(width * 0.35)),
                     np.float32) / 255.0
    if direction is not None:
        gy, gx = np.gradient(np.clip(mask, 0, 1))
        n = np.sqrt(gx * gx + gy * gy) + 1e-6
        facing = -(gx / n * direction[0] + gy / n * direction[1])
        rim = rim * np.clip(facing, 0.0, 1.0)
    canvas.over(np.asarray(colour, dtype=np.float32), rim * strength)
    return rim


def _odd(v: float) -> int:
    k = max(3, int(round(v)))
    return k if k % 2 else k + 1


# --------------------------------------------------------------------------
# metal
# --------------------------------------------------------------------------
def band_shade(canvas: Canvas, cx: float, cy: float, rx: float, ry: float,
               half: float, dark, light, *, spec: float = 0.85,
               tilt: float = 0.0) -> np.ndarray:
    """A round metal band, shaded as a tube rather than stroked as a flat ring.

    The cross-section normal is what makes it metal: across the band's width
    the surface turns away from the viewer, so it runs dark at both edges with
    a bright specular line where the normal points at the light. A flat stroke
    can never do this, which is why the first pass read as plastic.

    Returns the band's coverage mask so callers can shadow off it.
    """
    dx = (canvas.X - cx) / max(rx, 1e-3)
    dy = (canvas.Y - cy) / max(ry, 1e-3)
    d = np.sqrt(dx * dx + dy * dy)
    r_scale = 0.5 * (rx + ry)
    u = np.clip((d - 1.0) * r_scale / max(half, 1e-3), -1.0, 1.0)

    cover = np.clip((1.0 - np.abs(u)) * max(half, 1.0) * 0.9, 0.0, 1.0)

    theta = np.arctan2(dy, dx)
    nz = np.sqrt(np.clip(1.0 - u * u, 0.0, 1.0))
    nx = u * np.cos(theta + tilt)
    ny = u * np.sin(theta + tilt)
    diff = np.clip(nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2], 0.0, 1.0)

    half_v = np.array([LIGHT[0], LIGHT[1], LIGHT[2] + 1.0], dtype=np.float32)
    half_v /= np.linalg.norm(half_v)
    sp = np.clip(nx * half_v[0] + ny * half_v[1] + nz * half_v[2], 0.0, 1.0)
    sp = sp ** 26.0 * spec

    d0 = np.asarray(dark, dtype=np.float32)
    d1 = np.asarray(light, dtype=np.float32)
    body = d0[None, None, :] + (d1 - d0)[None, None, :] * (diff ** 0.85)[..., None]
    # bounce off the inner wall keeps the shadow side from going dead
    bounce = np.clip(-u, 0.0, 1.0)[..., None] * 0.16 * d1[None, None, :]
    col = np.clip(body + bounce + sp[..., None] * 0.9, 0.0, 1.0)
    canvas.over(col, cover)
    return cover


def chain_shade(canvas: Canvas, pts, width: float, dark, light,
                *, spec: float = 0.7) -> np.ndarray:
    """A chain, shaded across its thickness the same way a band is."""
    core = stroke_mask(canvas.size, pts, width, closed=False, feather=0.6)
    wide = stroke_mask(canvas.size, pts, width * 2.0, closed=False, feather=width * 0.5)
    # distance-from-centreline proxy: the wide stroke falls off, the core does not
    u = np.clip(1.0 - core, 0.0, 1.0)
    d0 = np.asarray(dark, dtype=np.float32)
    d1 = np.asarray(light, dtype=np.float32)
    lit = np.clip(1.0 - u * 1.5, 0.0, 1.0) ** 0.8
    col = d0[None, None, :] + (d1 - d0)[None, None, :] * lit[..., None]
    gy, gx = np.gradient(core)
    n = np.sqrt(gx * gx + gy * gy) + 1e-6
    facing = np.clip(-(gx / n * LIGHT[0] + gy / n * LIGHT[1]), 0.0, 1.0)
    col = np.clip(col + (facing * (1.0 - core) * spec)[..., None] * 0.55, 0.0, 1.0)
    canvas.over(col, np.clip(core + wide * 0.0, 0.0, 1.0))
    return core
