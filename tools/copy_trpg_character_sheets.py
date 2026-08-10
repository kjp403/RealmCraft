#!/usr/bin/env python3
"""Copy Tiny RPG Character Pack sheets into assets/sprites/characters/trpg_*/.

Uses the no-shadow 100x100 horizontal strips (Idle/Walk/Death/Attack…).
Does not create SpriteFrames — run tools/build_trpg_sprite_frames.gd after Godot imports.
"""
from __future__ import annotations

import os
import re
import shutil
import struct
from pathlib import Path

ROOT = Path("/workspace")
OUT_ROOT = ROOT / "assets/sprites/characters"

PACK01 = Path(
    "/tmp/asset_packs/tiny/Tiny RPG Character Asset Pack 01 v2.0 -Full 22 Characters/"
    "Characters(100x100 split)"
)
PACK02 = Path(
    "/tmp/asset_packs/blood/Blood Monsters/"
    "Tiny RPG Character Asset Pack 02 -Free Demon_A&Blood Monster_A/"
    "Characters(100x100 split)"
)

# Prefer no-effects attack sheets for cleaner in-game sprites.
SKIP_SUBSTRINGS = (
    "with magic effects",
    "_effect",
    "effect.png",
    "sumon_effect",  # typo in pack
)


def slugify(name: str) -> str:
    s = name.strip().lower()
    s = s.replace("&", " and ")
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as f:
        f.read(8)
        length = struct.unpack(">I", f.read(4))[0]
        ctype = f.read(4)
        assert ctype == b"IHDR"
        data = f.read(length)
        return struct.unpack(">II", data[:8])


def pick_noshadow_dir(char_dir: Path, display_name: str) -> Path | None:
    candidates: list[Path] = []
    for sub in char_dir.iterdir():
        if not sub.is_dir():
            continue
        low = sub.name.lower()
        if "shadow" in low or "projectile" in low or "arrow" in low:
            continue
        candidates.append(sub)
    if not candidates:
        return None
    # Prefer folder whose name matches the character
    for c in candidates:
        if c.name == display_name:
            return c
    return candidates[0]


def anim_key(filename: str, display_name: str) -> str | None:
    stem = Path(filename).stem
    prefix = display_name + "_"
    if stem == display_name:
        return None  # full sheet atlas — skip, we use split strips
    if not stem.startswith(prefix) and not stem.lower().startswith(display_name.lower() + "_"):
        # Necromancer_DEATH etc.
        if stem.upper().startswith(display_name.upper() + "_"):
            rest = stem[len(display_name) + 1 :]
        else:
            return None
    else:
        rest = stem[len(display_name) + 1 :]

    rest_l = rest.lower()
    for bad in SKIP_SUBSTRINGS:
        if bad in rest_l:
            return None

    # Normalize
    if rest_l.startswith("idle"):
        return "idle"
    if rest_l.startswith("walk"):
        # Walk01 preferred over Walk02; first wins in caller if we sort
        return "walk" if rest_l in ("walk", "walk01", "flying") or rest_l.startswith("walk0") else "walk"
    if rest_l.startswith("flying"):
        return "walk"  # Bat
    if rest_l.startswith("death"):
        return "death"
    if rest_l.startswith("hurt"):
        return "hurt"
    if rest_l.startswith("block"):
        return "block"
    if rest_l.startswith("summon") or rest_l.startswith("sumon"):
        return "special"
    if rest_l.startswith("heal"):
        return "special"
    if rest_l.startswith("attack"):
        # Attack01 -> attack, Attack02 -> special (or attack_2)
        m = re.match(r"attack0*(\d+)", rest_l)
        if m:
            n = int(m.group(1))
            if n <= 1:
                return "attack"
            if n == 2:
                return "special"
            return f"attack_{n}"
        if rest_l == "attack" or rest_l.startswith("attack("):
            return "attack"
        return "attack"
    return None


def copy_character(display_name: str, src_root: Path, slug_prefix: str) -> dict | None:
    char_dir = src_root / display_name
    if not char_dir.is_dir():
        print("MISSING", display_name)
        return None
    noshadow = pick_noshadow_dir(char_dir, display_name)
    if noshadow is None:
        print("NO DIR", display_name)
        return None

    slug = f"{slug_prefix}_{slugify(display_name)}"
    out = OUT_ROOT / slug
    out.mkdir(parents=True, exist_ok=True)

    # Clear previous pngs in out (keep .import if re-run — Godot will refresh)
    for old in out.glob("*.png"):
        old.unlink()

    chosen: dict[str, Path] = {}
    for png in sorted(noshadow.glob("*.png")):
        key = anim_key(png.name, display_name)
        if key is None:
            continue
        # Prefer Walk01 / Attack without effects — sorted order + first wins except walk01
        if key == "walk" and "walk02" in png.stem.lower():
            continue
        if key not in chosen:
            chosen[key] = png
        elif key == "walk" and "walk01" in png.stem.lower():
            chosen[key] = png

    # Bat has Flying not Idle — synthesize idle from flying/walk if needed
    if "idle" not in chosen and "walk" in chosen:
        chosen["idle"] = chosen["walk"]

    meta = {"slug": slug, "display_name": display_name, "anims": {}}
    for key, src in chosen.items():
        dest_name = f"{slug}_{key}.png"
        dest = out / dest_name
        shutil.copy2(src, dest)
        w, h = png_size(dest)
        frames = w // 100
        meta["anims"][key] = {
            "file": dest_name,
            "frames": frames,
            "frame_w": 100,
            "frame_h": h,
        }
        print(f"  {slug}/{dest_name} frames={frames}")

    # Also copy GIF preview if present beside the character folder
    for gif in char_dir.glob("*.gif"):
        shutil.copy2(gif, out / f"{slug}_preview.gif")

    return meta


def main() -> int:
    if not PACK01.is_dir():
        print("Pack 01 not extracted at", PACK01)
        return 1
    if not PACK02.is_dir():
        print("Pack 02 not extracted at", PACK02)
        return 1

    catalog: list[dict] = []
    print("=== Pack 01 ===")
    for name in sorted(os.listdir(PACK01)):
        if not (PACK01 / name).is_dir():
            continue
        print(name)
        meta = copy_character(name, PACK01, "trpg")
        if meta:
            catalog.append(meta)

    print("=== Pack 02 (Blood) ===")
    for name in sorted(os.listdir(PACK02)):
        if not (PACK02 / name).is_dir():
            continue
        print(name)
        meta = copy_character(name, PACK02, "trpg")
        if meta:
            catalog.append(meta)

    # Write catalog for the Godot builder
    import json

    cat_path = ROOT / "tools/trpg_import_catalog.json"
    cat_path.write_text(json.dumps(catalog, indent=2) + "\n")
    print("wrote", cat_path, "characters=", len(catalog))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
