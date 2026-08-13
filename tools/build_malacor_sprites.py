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
    all. Every clip below is therefore SYNTHESISED from the south pose using the
    house grammar measured off cleetus_*.png:
        idle    baseline pinned 63, top moves        -> breathe, feet planted
        run     baseline hops 63,62,61,61,62,63      -> whole body lifts <=2px
        attack  baseline AND top pinned              -> internal motion only
        death   baseline held, top descends 14->27   -> collapses in place
        special baseline lifts 1-2px                 -> rears up
    Anything that moves the body is anchored on the feet line so the baseline
    contract survives; verify_malacor.gd asserts it afterwards.

Every transform runs at FULL capture resolution and is downscaled once, at the
end, through a single shared scale + registration point -- so the boss never
jitters in size or drifts sideways between frames.

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
from PIL import Image

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
FIT_MARGIN = 4
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


class Rig:
    """Places every synthesised frame on ONE shared scale and anchor.

    Frames are built at capture resolution and resolved through the same
    (scale, pose-centre, feet-line) triple, so a leaning frame and a squashed
    frame still land on the same ground at the same size.
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
        # Fit the untransformed pose into the frame. Width binds: the wingspan
        # is wider than he is tall.
        self.scale = min(
            (frame - FIT_MARGIN * 2) / w,
            (self.baseline + 1 - MAX_LIFT - FIT_GUARD) / MAX_SQUASH / h,
        )
        self.bled = alpha_bleed(canvas)

    def frame(self, *, lean=0.0, squash=1.0, widen=1.0, lift=0,
              fire=1.0, ash_t=0.0, alpha=1.0) -> Image.Image:
        rgb = self.bled[..., :3].astype(np.float32)
        if fire != 1.0:
            rgb = fire_gain(rgb, fire)
        if ash_t:
            rgb = ash(rgb.astype(np.uint8), ash_t)
        src = np.dstack([np.clip(rgb, 0, 255), self.bled[..., 3]]).astype(np.uint8)
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
    return {
        # Feet planted, only the mass above them moves: a slow settle with an
        # ember pulse. Wings draw in a hair as he exhales.
        "idle": [
            dict(squash=1.000, widen=1.000, fire=1.00),
            dict(squash=0.988, widen=0.992, fire=1.06),
            dict(squash=0.976, widen=0.984, fire=1.12),
            dict(squash=0.988, widen=0.992, fire=1.06),
        ],
        # Whole-body hop of <=2px on cleetus's exact cadence, wings beating
        # against the lift and a slight forward lean at the top of the stride.
        "run": [
            dict(lift=0, widen=1.00, lean=0.000),
            dict(lift=1, widen=0.97, lean=0.012),
            dict(lift=2, widen=0.94, lean=0.022),
            dict(lift=2, widen=0.94, lean=0.022),
            dict(lift=1, widen=0.97, lean=0.012),
            dict(lift=0, widen=1.00, lean=0.000),
        ],
        # Baseline AND top pinned: no translation at all, the swing reads purely
        # as a lean through the axe with the fire flashing over on impact.
        "attack": [
            dict(lean=+0.000, widen=1.000, fire=1.00),
            dict(lean=-0.045, widen=1.020, fire=1.08),
            dict(lean=-0.072, widen=1.032, fire=1.20),
            dict(lean=+0.050, widen=0.972, fire=1.52),
            dict(lean=+0.078, widen=0.950, fire=1.70),
            dict(lean=+0.062, widen=0.978, fire=1.40),
            dict(lean=+0.030, widen=0.996, fire=1.18),
            dict(lean=+0.000, widen=1.000, fire=1.00),
        ],
        # Collapses in place: the ground line holds while the top sinks toward
        # it and the fire goes out to cinder. The cool-down stops well short of
        # black -- the last frame is HELD as the corpse until the body is
        # removed, and a fully ashed one disappears into a dark arena floor.
        "death": [
            dict(squash=1.00, widen=1.00, fire=1.00, ash_t=0.00),
            dict(squash=0.94, widen=1.01, fire=0.90, ash_t=0.08),
            dict(squash=0.84, widen=1.03, fire=0.72, ash_t=0.20),
            dict(squash=0.74, widen=1.03, fire=0.55, ash_t=0.32),
            dict(squash=0.66, widen=1.04, fire=0.42, ash_t=0.44),
            dict(squash=0.62, widen=1.05, fire=0.34, ash_t=0.52),
        ],
        # The collapse played backwards, burning the whole way up -- which is
        # exactly what hostile_npc.rp_spawn_effect() documents "emerge" to be.
        "emerge": [
            dict(squash=0.62, widen=1.05, fire=1.70),
            dict(squash=0.70, widen=1.04, fire=1.58),
            dict(squash=0.80, widen=1.03, fire=1.44),
            dict(squash=0.90, widen=1.02, fire=1.30),
            dict(squash=0.97, widen=1.00, fire=1.15),
            dict(squash=1.00, widen=1.00, fire=1.00),
        ],
        # The cast pose. Rears up off the baseline by 1-2px and throws the
        # wings open while the star in his chest goes white-hot.
        "special": [
            dict(lift=0, squash=1.00, widen=1.00, fire=1.15),
            dict(lift=1, squash=1.02, widen=1.03, fire=1.45),
            dict(lift=2, squash=1.04, widen=1.06, fire=1.72),
            dict(lift=2, squash=1.04, widen=1.06, fire=1.85),
            dict(lift=1, squash=1.02, widen=1.04, fire=1.60),
            dict(lift=0, squash=1.00, widen=1.01, fire=1.32),
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
    built = {}
    clipped = []
    for clip, specs in clip_specs().items():
        frames = [rig.frame(**s) for s in specs]
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
