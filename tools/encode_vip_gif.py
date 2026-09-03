"""Encode the VIP title showcase GIF from a captured PNG sequence.

Two steps, because Godot cannot write GIFs and the frames have to come out of a
real rasteriser:

    godot --path . --mode=client res://tools/render_vip_titles_gif.tscn
    python tools/encode_vip_gif.py <dir it printed> previews/vip-titles.gif

The render tool prints the frame directory as `GIF_FRAMES <abs path>` — it writes
into `user://`, which is outside the project, so nothing half-captured can end up
committed or picked up by an import pass.

Usage:
    python tools/encode_vip_gif.py FRAMES_DIR [DEST.gif] [FPS]
"""

import glob
import os
import sys

from PIL import Image

DEFAULT_DEST = "previews/vip-titles.gif"
DEFAULT_FPS = 20


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    src = sys.argv[1]
    dest = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_DEST
    fps = int(sys.argv[3]) if len(sys.argv) > 3 else DEFAULT_FPS

    paths = sorted(glob.glob(os.path.join(src, "f*.png")))
    if not paths:
        print("no f*.png frames in %s — did the render tool run?" % src)
        return 1
    frames = [Image.open(p).convert("RGB") for p in paths]

    # ONE PALETTE for the whole animation, sampled from the middle of the loop.
    # Quantising each frame on its own gives every frame its own 256 colours, and
    # the flat dark ground then shimmers between near-identical greys — the
    # background visibly crawls, which reads as an encoding fault rather than as
    # part of the effect. The middle frame is used because the first one is the
    # least representative: the emitters are still filling in.
    master = frames[len(frames) // 2].quantize(colors=255, method=Image.MEDIANCUT)

    # NO DITHER. Floyd-Steinberg doubled this file (4.3 MB -> 2.1 MB without) for
    # no visible gain: the source is flat pixel art on a dark ground, 255 colours
    # cover its gradients without banding, and the dither noise is pure LZW cost
    # on every single frame.
    quantised = [f.quantize(palette=master, dither=Image.NONE) for f in frames]

    quantised[0].save(
        dest,
        save_all=True,
        append_images=quantised[1:],
        duration=int(round(1000.0 / fps)),
        loop=0,
        optimize=True,
        # Restore to background between frames. The moving row leaves the old
        # nameplate behind without it — the titles smear across the frame instead
        # of travelling.
        disposal=2,
    )
    print("wrote %s  %dx%d  %d frames @ %d fps  %.2f MB" % (
        dest, frames[0].width, frames[0].height, len(frames), fps,
        os.path.getsize(dest) / 1048576.0,
    ))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
