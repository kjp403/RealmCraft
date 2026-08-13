#!/usr/bin/env python
"""Recover Malacor, the Sun-Eater's sprite strips from the delivered art.

The art arrived the way character art always arrives here (see the extraction
notes on the Cleetus commit): a screen capture of the sheet open in an editor,
not an exported PNG. That means three problems, all handled below.

  * No alpha. The editor's transparency checkerboard is baked into RGB. This
    capture is ALSO recompressed -- 166k distinct colours, checker greys smeared
    around 105/158 instead of sitting on two exact values -- so the checkerboard
    cannot be keyed by colour equality the way a lossless capture can. It is
    removed by FLOOD FILL from each cell's border through "grey-ish and mid
    luminance" pixels, plus a second pass for interior pockets (the gap between
    his arm and torso is enclosed and the border fill can never reach it).
    Flood fill also protects the axe: its blade is bare steel grey and a pure
    colour test eats it.
  * Window chrome. Masked by POSITION (title bar + banner above y=59), never by
    colour -- a near-white test would also eat the sprite's own hot highlights.
  * The sheet is 8 DIRECTIONS, one static pose each, with no animation frames at
    all. Every clip is therefore SYNTHESISED, and the first attempt at that --
    deforming the whole body per frame -- was not animation: a best-fit single
    shift explained ~86% of every attack frame, meaning the axe never moved
    relative to the torso. So the pose is CUT INTO PARTS (see PARTS) and the
    limbs rotate independently: the axe arm carries a chop through ~62 degrees,
    the wings beat, the head turns. The whole-body deform survives underneath as
    the weight shift, following the grammar measured off cleetus_*.png:
        idle    baseline pinned, top moves        -> breathe, feet planted
        run     baseline hops <=2px               -> a stride, not a slide
        attack  baseline AND top pinned           -> internal motion only
        death   baseline held, top descends       -> collapses in place
        special baseline lifts 1-2px              -> rears up
    Anything that moves the body is anchored on the feet line so the baseline
    contract survives; verify_malacor.gd asserts it afterwards.

Per frame the order is: rotate the limbs, THEN deform and downscale. Everything
runs at FULL capture resolution and is downscaled once, at the end, through a
single shared scale + registration point -- so the boss never jitters in size or
drifts sideways between frames. The fit measures the widest silhouette any clip
reaches, not the resting one, or the strike frames lose their blade to the edge.

Usage:
    python tools/build_malacor_sprites.py --source <capture.png>
    python tools/build_malacor_sprites.py --source <capture.png> --contact out.png

Re-run it against a clean exported sheet when one exists; nothing here is
hand-tuned to the compression, only to the layout.
"""

from __future__ import annotations

import argparse
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw

# --- capture layout -------------------------------------------------------
# Cell bounds were solved from the capture, not assumed: rows come from the
# gutters in a background-flood projection, columns from the runs of near-zero
# foreground between sprites. They are exact for this capture and are re-derived
# (not trusted) whenever --source has different dimensions.
CAPTURE_SIZE = (1128, 619)
CHROME_BOTTOM = 59  # title bar + "MALACOR, THE SUN-EATER" banner end here
CELLS = [
    # name,        y0,  y1,   x0,   x1
    ("north", 59, 304, 22, 293),
    ("northeast", 59, 304, 309, 567),
    ("east", 59, 304, 595, 820),
    ("southeast", 59, 304, 829, 1109),
    ("south", 336, 588, 0, 267),
    ("southwest", 336, 588, 317, 586),
    ("west", 336, 588, 601, 829),
    ("northwest", 336, 588, 856, 1116),
]
# The pose every clip is animated from. The chassis is not directional -- it
# picks a facing with flip_h only -- so the camera-facing pose is the one the
# game actually shows.
HERO = "south"

# --- output contract ------------------------------------------------------
FRAME = 64
BASELINE_ROW = 63  # character.tscn parks feet on the frame's last row
OUT_DIR = "assets/sprites/characters/malacor"
SLUG = "malacor"
# Horizontal breathing room, in frame pixels, left on EACH side of the fitted
# pose. His wingspan is wider than he is tall, so width is what binds the fit --
# without a margin the wingtips sit flat on the frame border and the first clip
# that widens or leans him shears them off. Sized for the worst case below
# (death's widen=1.10 plus attack's lean); build_* asserts no frame reaches the
# edge afterwards.
FIT_MARGIN = 2
# Alpha at or below this is snapped to zero. Lanczos rings a 1-4/255 haze out
# past the silhouette -- invisible on screen, but it is still "opaque" to
# anything that tests alpha > 0, which is what Godot's own image bounds and
# verify_malacor.gd's border check do. Clearing it makes the sprite's real
# extent and its measured extent the same thing.
ALPHA_FLOOR = 8
# Vertical headroom the fit must reserve for the clips that leave the standing
# pose: the biggest hop in `lift` and the biggest `squash`. At 64px the wingspan
# made WIDTH the binding constraint and this was slack; at 100px height binds, so
# without it the run hop and the special's rear-up clip straight off the top.
MAX_LIFT = 2
MAX_SQUASH = 1.04
# Slack for rounding. The affine, the downscale and the baseline snap each round
# independently, and 'special' stacks a squash and a lift, so an analytically
# exact budget still lands its peak frame a pixel or two over the top edge.
FIT_GUARD = 3

# Checkerboard test: low saturation AND mid luminance. Deliberately loose on
# both -- the recompression smears the two greys across roughly 86..182.
CHECKER_SAT = 26
CHECKER_LUM = (86, 182)


# --------------------------------------------------------------------------
# capture -> clean poses
# --------------------------------------------------------------------------
def _label(mask: np.ndarray):
    """4-connected components. Returns (labels, [ [(y,x),...], ... ])."""
    h, w = mask.shape
    lab = np.zeros((h, w), np.int32)
    comps = []
    cur = 0
    for sy in range(h):
        row = mask[sy]
        for sx in range(w):
            if not row[sx] or lab[sy, sx]:
                continue
            cur += 1
            lab[sy, sx] = cur
            dq = deque([(sy, sx)])
            px = []
            while dq:
                y, x = dq.popleft()
                px.append((y, x))
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not lab[ny, nx]:
                        lab[ny, nx] = cur
                        dq.append((ny, nx))
            comps.append(px)
    return lab, comps


def _background(rgb: np.ndarray) -> np.ndarray:
    """True where the cell is transparency checkerboard rather than sprite."""
    a = rgb.astype(np.int16)
    sat = a.max(axis=2) - a.min(axis=2)
    lum = a.mean(axis=2)
    checkerish = (sat <= CHECKER_SAT) & (lum >= CHECKER_LUM[0]) & (lum <= CHECKER_LUM[1])
    h, w = checkerish.shape
    _, comps = _label(checkerish)
    bg = np.zeros((h, w), bool)
    for px in comps:
        ys = np.fromiter((p[0] for p in px), int, len(px))
        xs = np.fromiter((p[1] for p in px), int, len(px))
        if ys.min() == 0 or ys.max() == h - 1 or xs.min() == 0 or xs.max() == w - 1:
            bg[ys, xs] = True  # reaches the border: outside the silhouette
            continue
        # Interior pocket. Only clear it if it really is checkerboard -- it has
        # to carry BOTH grey tiers. A flat grey patch of armour has one.
        if len(px) >= 25:
            L = lum[ys, xs]
            if (L < 128).sum() >= 5 and (L > 136).sum() >= 5:
                bg[ys, xs] = True
    return bg


def _largest_component(mask: np.ndarray) -> np.ndarray:
    _, comps = _label(mask)
    if not comps:
        return mask
    big = max(comps, key=len)
    out = np.zeros_like(mask)
    ys = np.fromiter((p[0] for p in big), int, len(big))
    xs = np.fromiter((p[1] for p in big), int, len(big))
    out[ys, xs] = True
    return out


def extract_poses(capture: Image.Image) -> dict[str, Image.Image]:
    """Cut the 8 directional poses out of the capture, alpha'd and trimmed."""
    arr = np.asarray(capture.convert("RGB"))
    poses = {}
    for name, y0, y1, x0, x1 in CELLS:
        cell = arr[y0:y1, x0:x1]
        # Keeping only the largest foreground blob drops the compression specks
        # that survive the checker test along the cell edges; body, wings and
        # axe are one connected silhouette in every pose.
        fg = _largest_component(~_background(cell))
        alpha = np.where(fg, 255, 0).astype(np.uint8)
        ys, xs = np.where(alpha > 0)
        im = Image.fromarray(np.dstack([cell, alpha]))
        poses[name] = im.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    return poses


# --------------------------------------------------------------------------
# frame construction
# --------------------------------------------------------------------------
def alpha_bleed(im: Image.Image, iters: int = 14) -> np.ndarray:
    """Push opaque colour outward into the transparent margin.

    Required, not cosmetic: transparent pixels still hold their checkerboard
    RGB, so any resample that touches them drags grey into the silhouette.
    Bleeding first (rather than premultiplying) also avoids the divide-by-tiny-
    alpha speckle that premultiply/unpremultiply produces on a binary matte.
    """
    arr = np.asarray(im).astype(np.float32)
    rgb, al = arr[..., :3].copy(), arr[..., 3]
    known = al > 8
    rgb[~known] = 0
    for _ in range(iters):
        if known.all():
            break
        k = known.astype(np.float32)
        num = np.zeros_like(rgb)
        den = np.zeros_like(k)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            num += np.roll(np.roll(rgb * k[..., None], dy, axis=0), dx, axis=1)
            den += np.roll(np.roll(k, dy, axis=0), dx, axis=1)
        fill = (den > 0) & ~known
        rgb[fill] = num[fill] / den[fill][..., None]
        known |= fill
    return np.dstack([rgb, al]).astype(np.uint8)


def fire_gain(rgb: np.ndarray, gain: float) -> np.ndarray:
    """Drive the emissive parts (lava veins, wing membrane, axe flame) only.

    Weighted by how warm AND how bright a pixel already is, so the cold armour
    plate stays put while the fire flares. Above ~1.3 it also bleaches toward a
    warm white, which is what sells an impact frame at 64px.
    """
    a = rgb.astype(np.float32)
    R, B = a[..., 0], a[..., 2]
    warm = np.clip((R - B) / 90.0, 0, 1) * np.clip((R - 60.0) / 120.0, 0, 1)
    out = a * (1.0 + (gain - 1.0) * warm)[..., None]
    if gain > 1.3:
        t = (np.clip((gain - 1.3) / 1.2, 0, 1) * warm)[..., None]
        out = out * (1 - t) + np.array([255.0, 240.0, 205.0]) * t
    return np.clip(out, 0, 255)


def ash(rgb: np.ndarray, t: float) -> np.ndarray:
    """Fade toward cooled-out cinder. t=0 untouched, t=1 dead grey."""
    if t <= 0:
        return rgb.astype(np.float32)
    a = rgb.astype(np.float32)
    grey = a.mean(axis=2, keepdims=True) * 0.55
    return a * (1 - t) + grey * t


# --- cutout rig ------------------------------------------------------------
# The sheet has ONE static pose, so deforming the whole body was the only motion
# available and it showed: a best-fit single shift explained ~86% of every attack
# frame, i.e. the axe never moved relative to the torso. These polygons cut the
# pose into limbs that rotate independently, which is what makes a swing a swing.
#
# Traced against the extracted `south` pose (262x230) — they are tied to THIS
# capture's geometry, so re-solve them if the source art is ever replaced.
#
# Each pivot sits ON or just inside its own cut line. That is the whole trick:
# the seam barely moves while the far end travels, so the joint does not tear.
# Outer edges run PAST the art (negative y, x beyond the pose) on purpose: a
# polygon that stops on the silhouette leaves slivers of wingtip and horn behind
# in the body plate, and those slivers then hang in the air as the limb rotates
# away from them.
# name -> (polygon, pivot, z). z below BODY_Z draws behind the torso.
BODY_Z = 2
PARTS: dict[str, tuple[list[tuple[int, int]], tuple[int, int], int]] = {
    "wing_l": ([(96, -14), (50, -14), (8, 38), (4, 98), (34, 148), (80, 158), (96, 120)],
               (100, 74), 0),
    "wing_r": ([(186, -14), (232, -14), (274, 38), (278, 98), (248, 148), (202, 158),
                (186, 120)], (182, 74), 0),
    "head": ([(100, -14), (182, -14), (185, 44), (170, 64), (150, 71), (124, 71),
              (104, 58), (97, 28)], (141, 69), 3),
    # Stops short of x=118 below y~170: the left LEG lives there and stays with
    # the body, or a swing takes his leg with it.
    "axe_arm": ([(74, 56), (118, 74), (141, 118), (153, 146), (130, 169), (100, 178),
                 (66, 220), (14, 226), (0, 180), (6, 130), (36, 92)], (120, 96), 4),
    "off_arm": ([(172, 76), (212, 70), (240, 102), (248, 150), (232, 182), (200, 186),
                 (178, 150), (170, 110)], (180, 98), 4),
}
## Torso box the hole-patch is confined to, in pose coordinates.
TORSO_BOX = (52, 196, 98, 192)  # y0, y1, x0, x1


def cut_parts(pose: Image.Image) -> tuple[np.ndarray, dict[str, np.ndarray]]:
    """Split the pose into a body plate and the rotatable parts."""
    w, h = pose.size
    a = np.asarray(pose)
    masks: dict[str, np.ndarray] = {}
    for name, (poly, _pivot, _z) in PARTS.items():
        m = Image.new("L", (w, h), 0)
        ImageDraw.Draw(m).polygon(poly, fill=255)
        masks[name] = (np.asarray(m) > 0) & (a[..., 3] > 8)

    body = a.copy()
    for m in masks.values():
        body[m] = 0

    # Patch the torso only where a FRONT part was lifted off it. Wings sit
    # BEHIND the body, so removing one leaves no hole — inpainting those smeared
    # torso colour out into the open space the wing occupies, and the fill then
    # drew over the wing as a pale block.
    front = np.zeros((h, w), bool)
    for name, (_poly, _pivot, z) in PARTS.items():
        if z >= BODY_Z:
            front |= masks[name]
    box = np.zeros((h, w), bool)
    box[TORSO_BOX[0]:TORSO_BOX[1], TORSO_BOX[2]:TORSO_BOX[3]] = True
    body = inpaint(body, front & box)

    parts: dict[str, np.ndarray] = {}
    for name, m in masks.items():
        p = a.copy()
        p[~m] = 0
        parts[name] = p
    return body, parts


def inpaint(arr: np.ndarray, holes: np.ndarray, iters: int = 18) -> np.ndarray:
    """Grow known colour into [param holes] so a swung limb reveals no bite."""
    rgb = arr[..., :3].astype(np.float32)
    al = arr[..., 3].astype(np.float32)
    known = al > 8
    for _ in range(iters):
        need = holes & ~known
        if not need.any():
            break
        k = known.astype(np.float32)
        num = np.zeros_like(rgb)
        den = np.zeros_like(k)
        an = np.zeros_like(k)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            num += np.roll(np.roll(rgb * k[..., None], dy, 0), dx, 1)
            den += np.roll(np.roll(k, dy, 0), dx, 1)
            an += np.roll(np.roll(al * k, dy, 0), dx, 1)
        f = need & (den > 0)
        rgb[f] = num[f] / den[f][..., None]
        al[f] = an[f] / den[f]
        known |= f
    return np.dstack([rgb, al]).astype(np.uint8)


class Rig:
    """Poses the cutout, then places every frame on ONE shared scale and anchor.

    Per-frame order is: rotate the limbs, THEN apply the whole-body deform and
    downscale. Both resolve through the same (scale, pose-centre, feet-line)
    triple, so a leaning frame and a squashed frame still land on the same
    ground at the same size.
    """

    def __init__(self, pose: Image.Image, frame: int = FRAME, baseline: int = -1,
                 pad: int = 60):
        self.frame_px = frame
        # character.tscn draws the sprite with offset (0, -30), centred, so the
        # frame row that actually lands on the ground is 31 + frame/2 -- NOT the
        # last row. They coincide only near 64px, which is why every shipped
        # 64px skin bakes its feet at 63 and why the 100px trpg sheets (feet at
        # 58-69 instead of 81) visibly float above their shadows.
        self.baseline = baseline if baseline >= 0 else default_baseline(frame)
        self.pad = pad
        w, h = pose.size
        canvas = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
        canvas.paste(pose, (pad, pad))
        self.canvas = canvas
        self.cx = pad + w / 2.0  # pose centre, canvas coords
        self.feet = pad + h  # ground line, canvas coords (exclusive row)

        # Cutout layers, padded into canvas space so a rotated limb has room.
        body, parts = cut_parts(pose)
        self._body = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        self._body.paste(Image.fromarray(body), (pad, pad))
        self._parts: dict[str, Image.Image] = {}
        self._pivots: dict[str, tuple[float, float]] = {}
        for name, arr in parts.items():
            layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
            layer.paste(Image.fromarray(arr), (pad, pad))
            self._parts[name] = layer
            px, py = PARTS[name][1]
            self._pivots[name] = (px + pad, py + pad)
        self._behind = [n for n in PARTS if PARTS[n][2] < BODY_Z]
        self._front = sorted(
            (n for n in PARTS if PARTS[n][2] >= BODY_Z), key=lambda n: PARTS[n][2]
        )
        # Fit the untransformed pose into the frame. Width binds: the wingspan
        # is wider than he is tall.
        self.scale = min(
            (frame - FIT_MARGIN * 2) / w,
            (self.baseline + 1 - MAX_LIFT - FIT_GUARD) / MAX_SQUASH / h,
        )
        self._bled_cache: dict[tuple, np.ndarray] = {}

    def fit_poses(self, poses: list[dict]) -> None:
        """Re-fit the scale to the widest silhouette any clip actually reaches.

        Fitting the NEUTRAL pose is not enough once limbs rotate: the axe at the
        end of its swing reaches well past where it hangs at rest, and the fit
        has to already know that or the strike frames — the ones players look
        at — are the ones that lose their blade to the frame edge.
        """
        x0, y0, x1, y1 = self.cx, self.feet, self.cx, self.feet
        for pose in poses:
            al = self.pose_layers(pose or {})[..., 3]
            rows = np.where(al.max(axis=1) > ALPHA_FLOOR)[0]
            cols = np.where(al.max(axis=0) > ALPHA_FLOOR)[0]
            if not len(rows) or not len(cols):
                continue
            x0, x1 = min(x0, cols[0]), max(x1, cols[-1])
            y0, y1 = min(y0, rows[0]), max(y1, rows[-1])
        w = max(1.0, float(x1 - x0 + 1))
        h = max(1.0, float(y1 - y0 + 1))
        self.cx = (x0 + x1 + 1) / 2.0
        self.scale = min(
            (self.frame_px - FIT_MARGIN * 2) / w,
            (self.baseline + 1 - MAX_LIFT - FIT_GUARD) / MAX_SQUASH / h,
        )

    def pose_layers(self, pose: dict[str, float]) -> np.ndarray:
        """Composite the cutout at the given per-part rotations, alpha-bled.

        Cached on the rotation tuple: clips reuse the neutral pose constantly
        (every non-moving frame), and bleeding is the expensive step.
        """
        key = tuple(sorted((n, round(float(d), 2)) for n, d in pose.items() if d))
        hit = self._bled_cache.get(key)
        if hit is not None:
            return hit
        out = Image.new("RGBA", self.canvas.size, (0, 0, 0, 0))
        for name in self._behind:
            out.alpha_composite(self._rotated(name, pose.get(name, 0.0)))
        out.alpha_composite(self._body)
        for name in self._front:
            out.alpha_composite(self._rotated(name, pose.get(name, 0.0)))
        bled = alpha_bleed(out)
        self._bled_cache[key] = bled
        return bled

    def _rotated(self, name: str, deg: float) -> Image.Image:
        if deg == 0.0:
            return self._parts[name]
        return self._parts[name].rotate(
            deg, resample=Image.BICUBIC, center=self._pivots[name]
        )

    def frame(self, *, lean=0.0, squash=1.0, widen=1.0, lift=0,
              fire=1.0, ash_t=0.0, alpha=1.0, pose=None) -> Image.Image:
        bled = self.pose_layers(pose or {})
        rgb = bled[..., :3].astype(np.float32)
        if fire != 1.0:
            rgb = fire_gain(rgb, fire)
        if ash_t:
            rgb = ash(rgb.astype(np.uint8), ash_t)
        src = np.dstack([np.clip(rgb, 0, 255), bled[..., 3]]).astype(np.uint8)
        im = Image.fromarray(src)
        W, H = im.size

        # One affine, anchored on the feet line and the pose centre, carrying
        # lean (shear that grows with height), squash (vertical) and widen
        # (horizontal). PIL's matrix maps DESTINATION -> SOURCE, hence inverses.
        inv_w, inv_s = 1.0 / widen, 1.0 / squash
        # x_src = cx + (x_dst - cx)/widen + lean * (y_dst - feet)/squash
        # y_src = feet + (y_dst - feet)/squash
        mat = (
            inv_w, lean * inv_s, self.cx * (1 - inv_w) - lean * inv_s * self.feet,
            0.0, inv_s, self.feet * (1 - inv_s),
        )
        im = im.transform((W, H), Image.AFFINE, mat, resample=Image.BICUBIC)

        nw, nh = max(1, round(W * self.scale)), max(1, round(H * self.scale))
        arr = np.asarray(im)
        small = np.dstack([
            np.asarray(Image.fromarray(arr[..., :3]).resize((nw, nh), Image.LANCZOS)),
            np.asarray(Image.fromarray(arr[..., 3]).resize((nw, nh), Image.LANCZOS)),
        ])
        small = small.copy()
        if alpha != 1.0:
            small[..., 3] = (small[..., 3].astype(np.float32) * alpha).astype(np.uint8)
        faint = small[..., 3] <= ALPHA_FLOOR
        small[faint] = 0

        # Register: pose centre -> frame centre, feet line -> the baseline row.
        F = self.frame_px
        out = np.zeros((F, F, 4), np.uint8)
        ox = int(round(F / 2.0 - self.cx * self.scale))
        oy = int(round((self.baseline + 1) - self.feet * self.scale))
        sx0, sy0 = max(0, -ox), max(0, -oy)
        dx0, dy0 = max(0, ox), max(0, oy)
        cw = min(nw - sx0, F - dx0)
        ch = min(nh - sy0, F - dy0)
        if cw > 0 and ch > 0:
            out[dy0:dy0 + ch, dx0:dx0 + cw] = small[sy0:sy0 + ch, sx0:sx0 + cw]

        # Snap the baseline, THEN hop by whole pixels. Rounding the affine's
        # sub-pixel placement was silently eating half the run's 2px hop and
        # landing it asymmetrically; the clip only reads as a stride if the
        # cadence is exactly the authored one, so it is enforced here instead of
        # hoped for. Resampled alpha also feathers the bottom edge by a row,
        # which the snap absorbs.
        rows = np.where(out[..., 3].max(axis=1) > 8)[0]
        if len(rows):
            shift = self.baseline - int(rows[-1]) - int(lift)
            if shift:
                out = np.roll(out, shift, axis=0)
                if shift > 0:
                    out[:shift] = 0
                elif shift < 0:
                    out[shift:] = 0
        return Image.fromarray(out)


# --------------------------------------------------------------------------
# the clips
# --------------------------------------------------------------------------
# Each entry is a list of Rig.frame kwargs. The comments record the house rule
# each clip is honouring -- they are measured from cleetus_*.png, not invented.
def clip_specs() -> dict[str, list[dict]]:
    """Per-frame limb rotations (degrees CCW) plus the whole-body deform.

    `pose` is the articulation and does the real work; squash/widen/lean/lift
    remain for the weight shift underneath it. Wings mirror (one +, one -) so a
    flap opens and closes rather than sliding the pair sideways.
    """
    def wings(d: float) -> dict:
        return {"wing_l": -d, "wing_r": d}

    return {
        # Breathing. Wings settle in and out, head dips, weapon arm sags on the
        # exhale. Feet planted; the body only squashes a hair under it.
        "idle": [
            dict(pose=wings(0.0) | {"head": 0.0, "axe_arm": 0.0, "off_arm": 0.0},
                 squash=1.000, fire=1.00),
            dict(pose=wings(3.0) | {"head": -1.0, "axe_arm": -1.5, "off_arm": 1.0},
                 squash=0.992, fire=1.06),
            dict(pose=wings(5.0) | {"head": -1.6, "axe_arm": -2.5, "off_arm": 1.6},
                 squash=0.984, fire=1.12),
            dict(pose=wings(3.0) | {"head": -1.0, "axe_arm": -1.5, "off_arm": 1.0},
                 squash=0.992, fire=1.06),
        ],
        # A stride, not a slide: wings beat through a full open/close, arms
        # counter-swing against each other, body hops <=2px on cleetus's cadence.
        "run": [
            dict(pose=wings(-6.0) | {"axe_arm": 7.0, "off_arm": -7.0, "head": 1.0},
                 lift=0, widen=1.00),
            dict(pose=wings(4.0) | {"axe_arm": 2.0, "off_arm": -2.0, "head": 0.0},
                 lift=1, widen=0.99),
            dict(pose=wings(13.0) | {"axe_arm": -5.0, "off_arm": 5.0, "head": -1.5},
                 lift=2, widen=0.98),
            dict(pose=wings(13.0) | {"axe_arm": -7.0, "off_arm": 7.0, "head": -1.5},
                 lift=2, widen=0.98),
            dict(pose=wings(4.0) | {"axe_arm": -2.0, "off_arm": 2.0, "head": 0.0},
                 lift=1, widen=0.99),
            dict(pose=wings(-6.0) | {"axe_arm": 7.0, "off_arm": -7.0, "head": 1.0},
                 lift=0, widen=1.00),
        ],
        # The chop. The axe arm carries it through ~62 degrees while the body
        # counter-leans into the swing and the fire flashes over on impact.
        # Baseline AND top stay pinned, per the house rule for attack.
        "attack": [
            dict(pose={"axe_arm": 0.0}, lean=+0.000, fire=1.00),
            dict(pose={"axe_arm": -14.0, "off_arm": 4.0, "head": 2.0} | wings(-4.0),
                 lean=-0.030, fire=1.08),
            dict(pose={"axe_arm": -26.0, "off_arm": 7.0, "head": 3.0} | wings(-7.0),
                 lean=-0.048, fire=1.20),
            dict(pose={"axe_arm": -16.0, "off_arm": 5.0, "head": 1.0} | wings(-3.0),
                 lean=-0.020, fire=1.35),
            dict(pose={"axe_arm": +18.0, "off_arm": -6.0, "head": -3.0} | wings(6.0),
                 lean=+0.038, fire=1.34),
            dict(pose={"axe_arm": +36.0, "off_arm": -9.0, "head": -4.0} | wings(9.0),
                 lean=+0.056, fire=1.45),
            dict(pose={"axe_arm": +24.0, "off_arm": -6.0, "head": -2.0} | wings(5.0),
                 lean=+0.036, fire=1.28),
            dict(pose={"axe_arm": +8.0, "off_arm": -2.0, "head": 0.0} | wings(2.0),
                 lean=+0.014, fire=1.15),
        ],
        # Collapses in place: wings fold down, arms drop, head sinks, and the
        # body squashes toward the ground line it never leaves. The cool-down
        # stops short of black -- the last frame is HELD as the corpse.
        "death": [
            dict(pose={}, squash=1.00, widen=1.00, fire=1.00, ash_t=0.00),
            dict(pose=wings(-10.0) | {"head": 4.0, "axe_arm": 6.0, "off_arm": -5.0},
                 squash=0.94, widen=1.01, fire=0.90, ash_t=0.08),
            dict(pose=wings(-22.0) | {"head": 9.0, "axe_arm": 13.0, "off_arm": -11.0},
                 squash=0.84, widen=1.03, fire=0.72, ash_t=0.20),
            dict(pose=wings(-34.0) | {"head": 14.0, "axe_arm": 20.0, "off_arm": -17.0},
                 squash=0.74, widen=1.03, fire=0.55, ash_t=0.32),
            dict(pose=wings(-44.0) | {"head": 18.0, "axe_arm": 26.0, "off_arm": -22.0},
                 squash=0.66, widen=1.04, fire=0.42, ash_t=0.44),
            dict(pose=wings(-50.0) | {"head": 21.0, "axe_arm": 30.0, "off_arm": -25.0},
                 squash=0.62, widen=1.05, fire=0.34, ash_t=0.52),
        ],
        # The collapse played backwards, burning the whole way up -- which is
        # exactly what hostile_npc.rp_spawn_effect() documents "emerge" to be.
        "emerge": [
            dict(pose=wings(-50.0) | {"head": 21.0, "axe_arm": 30.0, "off_arm": -25.0},
                 squash=0.62, widen=1.05, fire=1.45),
            dict(pose=wings(-38.0) | {"head": 16.0, "axe_arm": 23.0, "off_arm": -19.0},
                 squash=0.70, widen=1.04, fire=1.38),
            dict(pose=wings(-26.0) | {"head": 11.0, "axe_arm": 16.0, "off_arm": -13.0},
                 squash=0.80, widen=1.03, fire=1.44),
            dict(pose=wings(-15.0) | {"head": 6.0, "axe_arm": 9.0, "off_arm": -8.0},
                 squash=0.90, widen=1.02, fire=1.30),
            dict(pose=wings(-5.0) | {"head": 2.0, "axe_arm": 3.0, "off_arm": -3.0},
                 squash=0.97, widen=1.00, fire=1.15),
            dict(pose={}, squash=1.00, widen=1.00, fire=1.00),
        ],
        # The cast. Wings throw open, both arms lift, head goes back, and the
        # star in his chest goes white-hot. Rears 1-2px off the baseline.
        "special": [
            dict(pose={}, lift=0, squash=1.00, fire=1.15),
            dict(pose=wings(14.0) | {"axe_arm": -10.0, "off_arm": 10.0, "head": 3.0},
                 lift=1, squash=1.02, fire=1.45),
            dict(pose=wings(26.0) | {"axe_arm": -19.0, "off_arm": 19.0, "head": 6.0},
                 lift=2, squash=1.04, fire=1.42),
            dict(pose=wings(30.0) | {"axe_arm": -22.0, "off_arm": 22.0, "head": 7.0},
                 lift=2, squash=1.04, fire=1.55),
            dict(pose=wings(20.0) | {"axe_arm": -14.0, "off_arm": 14.0, "head": 4.0},
                 lift=1, squash=1.02, fire=1.38),
            dict(pose=wings(8.0) | {"axe_arm": -5.0, "off_arm": 5.0, "head": 1.0},
                 lift=0, squash=1.00, fire=1.32),
        ],
    }


def default_baseline(frame: int) -> int:
    """Frame row that sits on the ground for a given frame size.

    Solved from character.tscn rather than assumed: the AnimatedSprite2D is
    centred with offset (0, -30) and scaled by visual_scale, so frame row r
    lands at local y = (r - 30 - frame/2) * visual_scale. Ground is y ~= 0.
    Gives 63 at 64px, which is exactly the convention every shipped skin uses.
    """
    return 31 + frame // 2


def strip(frames: list[Image.Image], frame: int) -> Image.Image:
    out = Image.new("RGBA", (frame * len(frames), frame), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        out.paste(f, (i * frame, 0))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", required=True, help="the delivered sheet capture")
    ap.add_argument("--frame", type=int, default=FRAME)
    ap.add_argument("--outdir", default=OUT_DIR)
    ap.add_argument("--contact", default="", help="also write a zoomed contact sheet here")
    args = ap.parse_args()

    cap = Image.open(args.source)
    if cap.size != CAPTURE_SIZE:
        print(f"!! source is {cap.size}, layout was solved for {CAPTURE_SIZE}.")
        print("   Re-solve CELLS before trusting the output.")
        return 2

    print(f"frame {args.frame}px, ground row {default_baseline(args.frame)}")
    poses = extract_poses(cap)
    os.makedirs(args.outdir, exist_ok=True)

    # Keep the directional set at game resolution. The chassis cannot use it
    # today (it picks a facing with flip_h, not an 8-way index) but it is the
    # only surviving record of the other seven poses, and it is what a
    # directional body would be built from later.
    dirs = []
    for name, *_ in CELLS:
        r = Rig(poses[name], args.frame)
        dirs.append(r.frame())
    strip(dirs, args.frame).save(os.path.join(args.outdir, f"{SLUG}_directions.png"))

    rig = Rig(poses[HERO], args.frame)
    specs = clip_specs()
    rig.fit_poses([f.get("pose", {}) for c in specs.values() for f in c])
    built = {}
    clipped = []
    for clip, frames_spec in specs.items():
        frames = [rig.frame(**fs) for fs in frames_spec]
        path = os.path.join(args.outdir, f"{SLUG}_{clip}.png")
        strip(frames, args.frame).save(path)
        built[clip] = frames
        # A frame whose alpha reaches a side border has had wingtip sheared off
        # by widen/lean. Caught here rather than in review: it is a 1px tell in a
        # 64px sprite and invisible until the clip plays.
        for i, f in enumerate(frames):
            al = np.asarray(f)[..., 3]
            if al[:, 0].max() > 0 or al[:, -1].max() > 0 or al[0, :].max() > 0:
                clipped.append(f"{clip}[{i}]")
        print(f"  {clip:8s} {len(frames)} frames -> {path}")

    if clipped:
        print(f"!! frames touching a frame border (raise FIT_MARGIN): {', '.join(clipped)}")
        return 1

    if args.contact:
        rows = [("directions", dirs)] + list(built.items())
        wide = max(len(f) for _, f in rows)
        z = max(1, 256 // args.frame)
        F = args.frame
        sheet = Image.new("RGBA", (wide * F * z, len(rows) * F * z), (26, 28, 36, 255))
        for r, (_, frames) in enumerate(rows):
            for c, f in enumerate(frames):
                big = f.resize((F * z, F * z), Image.NEAREST)
                sheet.alpha_composite(big, (c * F * z, r * F * z))
        sheet.save(args.contact)
        print(f"  contact -> {args.contact}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
