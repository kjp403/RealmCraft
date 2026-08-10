#!/usr/bin/env python3
"""Import Supporter Asset Pack monsters into assets/sprites/characters/trpg_*/.

Each pack entry is a 4-frame 16x16 loop (GIF + 64x16 PNG strip). We nearest-neighbor
upscale 4x → 64x64 frames so they match existing goblin/orc scale, then emit
idle/walk/run/attack/death strips and append catalog rows for build_trpg_sprite_frames.gd.

Usage:
  unzip Supporter_Asset_Pack.zip -d /tmp/asset_packs/supporter_fresh
  python3 tools/copy_supporter_monster_sheets.py
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from PIL import Image, ImageSequence

ROOT = Path("/workspace")
OUT_ROOT = ROOT / "assets/sprites/characters"
CATALOG_PATH = ROOT / "tools/trpg_import_catalog.json"
ANIM_ROOT_CANDIDATES = [
    Path(
        "/tmp/asset_packs/supporter_fresh/Supporter Asset Pack/"
        "Supporter Asset Pack/Supporter Monster Animations"
    ),
    Path(
        "/tmp/asset_packs/supporter/Supporter Asset Pack/"
        "Supporter Asset Pack/Supporter Monster Animations"
    ),
    Path("/tmp/asset_packs/supporter/Supporter Monster Animations"),
]

SCALE = 4  # 16 → 64
FRAME = 16 * SCALE


def slugify(name: str) -> str:
    s = name.strip().lower()
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def find_anim_root() -> Path:
    for p in ANIM_ROOT_CANDIDATES:
        if p.is_dir():
            return p
    raise SystemExit(
        "Supporter Monster Animations not found. Extract the zip under "
        "/tmp/asset_packs/supporter_fresh first."
    )


def load_frames(monster_dir: Path) -> list[Image.Image]:
    pngs = sorted(monster_dir.glob("*.png"))
    gifs = sorted(monster_dir.glob("*.gif"))
    frames: list[Image.Image] = []
    if pngs:
        sheet = Image.open(pngs[0]).convert("RGBA")
        w, h = sheet.size
        if w % h == 0 and h == 16:
            n = w // h
            for i in range(n):
                frames.append(sheet.crop((i * h, 0, (i + 1) * h, h)))
        elif w == 16 and h == 16:
            frames.append(sheet)
    if not frames and gifs:
        gif = Image.open(gifs[0])
        for fr in ImageSequence.Iterator(gif):
            frames.append(fr.convert("RGBA"))
    if not frames:
        raise RuntimeError(f"No frames in {monster_dir}")
    # Upscale nearest-neighbor
    out: list[Image.Image] = []
    for fr in frames:
        out.append(fr.resize((FRAME, FRAME), Image.Resampling.NEAREST))
    return out


def write_strip(frames: list[Image.Image], path: Path) -> None:
    sheet = Image.new("RGBA", (FRAME * len(frames), FRAME), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        sheet.paste(fr, (i * FRAME, 0), fr)
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)


def import_monster(display_name: str, monster_dir: Path) -> dict:
    slug = f"trpg_{slugify(display_name)}"
    out = OUT_ROOT / slug
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.png"):
        old.unlink()

    frames = load_frames(monster_dir)
    # Locomotion + attack reuse the loop; death holds the last pose.
    death_frames = frames[-1:] * max(2, len(frames))

    anim_files = {
        "idle": frames,
        "walk": frames,
        "run": frames,
        "attack": frames,
        "death": death_frames,
    }
    meta = {
        "slug": slug,
        "display_name": display_name,
        "pack": "supporter",
        "anims": {},
    }
    for key, frs in anim_files.items():
        dest_name = f"{slug}_{key}.png"
        write_strip(frs, out / dest_name)
        meta["anims"][key] = {
            "file": dest_name,
            "frames": len(frs),
            "frame_w": FRAME,
            "frame_h": FRAME,
        }
        print(f"  {slug}/{dest_name} frames={len(frs)} size={FRAME}x{FRAME}")
    return meta


def main() -> int:
    root = find_anim_root()
    print("source", root)

    new_entries: list[dict] = []
    for monster_dir in sorted(p for p in root.iterdir() if p.is_dir()):
        print(monster_dir.name)
        new_entries.append(import_monster(monster_dir.name, monster_dir))

    existing: list[dict] = []
    if CATALOG_PATH.is_file():
        existing = json.loads(CATALOG_PATH.read_text())
        if not isinstance(existing, list):
            existing = []

    new_slugs = {e["slug"] for e in new_entries}
    # Drop prior supporter rows (and any prior import of these slugs), keep Tiny RPG rows.
    kept = [
        e
        for e in existing
        if e.get("slug") not in new_slugs and e.get("pack") != "supporter"
    ]
    catalog = kept + new_entries
    CATALOG_PATH.write_text(json.dumps(catalog, indent=2) + "\n")
    print(
        "wrote",
        CATALOG_PATH,
        "total=",
        len(catalog),
        "supporter=",
        len(new_entries),
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
