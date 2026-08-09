#!/usr/bin/env python3
"""Convert Mecha Golem GIF pack into horizontal PNG strips used by SpriteFrames.

Usage:
  python3 tools/import_mecha_gifs.py /path/to/Mecha_Golem_GIF.zip
"""
from __future__ import annotations
import sys, zipfile, tempfile
from pathlib import Path
from PIL import Image, ImageSequence
import numpy as np

OUT = Path('assets/sprites/characters/mecha_stone_golem')

def punch(im: Image.Image) -> Image.Image:
    a = np.asarray(im.convert('RGBA')).copy()
    mask = (a[:,:,0] < 12) & (a[:,:,1] < 12) & (a[:,:,2] < 12)
    a[mask, 3] = 0
    return Image.fromarray(a)

def strip(frames, path: Path) -> None:
    w, h = frames[0].size
    sheet = Image.new('RGBA', (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sheet.paste(f, (i * w, 0), f)
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)
    print('wrote', path, sheet.size, 'frames', len(frames))

def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__); return 2
    zpath = Path(sys.argv[1])
    with tempfile.TemporaryDirectory() as td:
        with zipfile.ZipFile(zpath) as zf:
            zf.extractall(td)
        root = next(Path(td).rglob('flatten_character.gif')).parent
        flat = [punch(f) for f in ImageSequence.Iterator(Image.open(root / 'flatten_character.gif'))]
        strip(flat[0:7], OUT / 'idle.png')
        strip(flat[7:12] + flat[37:44], OUT / 'special.png')
        strip(flat[12:21], OUT / 'attack.png')
        strip(flat[44:60], OUT / 'walk.png')
        strip(flat[44:60], OUT / 'run.png')
        strip(flat[60:67], OUT / 'death.png')
        laser = [punch(f) for f in ImageSequence.Iterator(Image.open(root / 'laser.gif'))]
        lw, lh = laser[0].size
        sheet = Image.new('RGBA', (lw, lh * len(laser)), (0, 0, 0, 0))
        for i, f in enumerate(laser):
            sheet.paste(f, (0, i * lh), f)
        sheet.save(OUT / 'laser_sheet.png')
        arm = [punch(f) for f in ImageSequence.Iterator(Image.open(root / 'arm_projectile_glowing.gif'))]
        strip(arm, OUT / 'arm_projectile_glowing.png')
        max(arm, key=lambda im: np.asarray(im)[:,:,3].sum()).save(OUT / 'arm_projectile.png')
    print('done')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
