#!/usr/bin/env python3
"""Build SpriteFrames .tres + the cosmetics content index from the VFX strips.

Run after tools/gen_cosmetic_vfx.py:

    python tools/gen_cosmetic_vfx.py assets/sprites/vfx/cosmetics
    python tools/build_cosmetic_frames.py

Writes the .tres files as TEXT rather than going through Godot's ResourceSaver
on purpose -- a headless `-s` tool run strips `uid=` from a saved .tres and from
every ext_resource in it, which silently breaks references. Text output keeps
path-based ext_resources, which Godot resolves fine.

Ids are assigned alphabetically and are STABLE: an existing index is read back
and its slug->id mapping preserved, so regenerating never renumbers a cosmetic
someone already has equipped.
"""

from __future__ import annotations

import hashlib
import os
import re
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STRIP_DIR = os.path.join(REPO, "assets", "sprites", "vfx", "cosmetics")
FRAMES_DIR = os.path.join(REPO, "source", "common", "gameplay", "cosmetics", "frames")
INDEX_PATH = os.path.join(REPO, "source", "common", "registry", "indexes", "cosmetics_index.tres")

CELL = 128

# Slot is derived from the slug prefix. Looping slots play forever while equipped;
# one-shot slots fire on an event and stop.
LOOPING = {"aura", "trail", "halo"}
SPEED = {"aura": 12.0, "trail": 14.0, "halo": 14.0, "flourish": 16.0, "departure": 14.0}


def slot_of(slug: str) -> str:
    return slug.split("_", 1)[0]


def frame_count(png_path: str) -> int:
    """Width / 128 straight out of the PNG header -- avoids a Pillow dependency
    here so this stays runnable in a bare checkout."""
    with open(png_path, "rb") as fh:
        head = fh.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"not a PNG: {png_path}")
    width = int.from_bytes(head[16:20], "big")
    if width % CELL:
        raise ValueError(f"{png_path}: width {width} is not a multiple of {CELL}")
    return width // CELL


def existing_ids() -> tuple[dict[str, int], int]:
    """Preserve slug->id from a previous index so ids never shift."""
    if not os.path.exists(INDEX_PATH):
        return {}, 1
    text = open(INDEX_PATH, encoding="utf-8").read()
    ids = {
        m.group(2): int(m.group(1))
        for m in re.finditer(r'&"id":\s*(\d+),\s*\n&"path":[^\n]*\n&"slug":\s*&"([^"]+)"', text)
    }
    if not ids:
        ids = dict(zip(re.findall(r'&"slug":\s*&"([^"]+)"', text),
                       (int(x) for x in re.findall(r'&"id":\s*(\d+)', text))))
    nxt = int(re.search(r"next_id\s*=\s*(\d+)", text).group(1)) if "next_id" in text else 1
    return ids, nxt


def write_frames(slug: str, n: int, cid: int) -> str:
    slot = slot_of(slug)
    loop = "true" if slot in LOOPING else "false"
    speed = SPEED.get(slot, 12.0)
    png_res = f"res://assets/sprites/vfx/cosmetics/{slug}.png"

    lines = [
        f'[gd_resource type="SpriteFrames" load_steps={n + 2} format=3]',
        "",
        f'[ext_resource type="Texture2D" path="{png_res}" id="1_tex"]',
        "",
    ]
    for i in range(n):
        lines += [
            f'[sub_resource type="AtlasTexture" id="f{i}"]',
            'atlas = ExtResource("1_tex")',
            f"region = Rect2({i * CELL}, 0, {CELL}, {CELL})",
            "",
        ]
    frames = ", ".join(
        '{\n"duration": 1.0,\n"texture": SubResource("f%d")\n}' % i for i in range(n)
    )
    lines += [
        "[resource]",
        "animations = [{",
        f'"frames": [{frames}],',
        f'"loop": {loop},',
        '"name": &"loop",',
        f'"speed": {speed}',
        "}]",
        f'metadata/slug = &"{slug}"',
        f"metadata/id = {cid}",
        "",
    ]
    out = os.path.join(FRAMES_DIR, f"{slug}.tres")
    with open(out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))
    return out


def main() -> None:
    os.makedirs(FRAMES_DIR, exist_ok=True)
    slugs = sorted(
        f[:-4] for f in os.listdir(STRIP_DIR) if f.endswith(".png")
    )
    known, next_id = existing_ids()

    entries = []
    for slug in slugs:
        png = os.path.join(STRIP_DIR, f"{slug}.png")
        n = frame_count(png)
        cid = known.get(slug)
        if cid is None:
            cid = next_id
            next_id += 1
        tres = write_frames(slug, n, cid)
        digest = hashlib.sha256(open(tres, "rb").read()).hexdigest()
        entries.append((cid, slug, f"res://source/common/gameplay/cosmetics/frames/{slug}.tres", digest))
        print(f"  {slug:<22} id={cid:<3} {n:>2} frames  [{slot_of(slug)}]")

    entries.sort(key=lambda e: e[0])
    body = ", ".join(
        '{\n&"hash": "%s",\n&"id": %d,\n&"path": "%s",\n&"slug": &"%s"\n}' % (h, i, p, s)
        for i, s, p, h in entries
    )
    index = "\n".join([
        '[gd_resource type="Resource" script_class="ContentIndex" format=3]',
        "",
        '[ext_resource type="Script" path="res://source/common/registry/content_index.gd" id="1_ci"]',
        "",
        "[resource]",
        'script = ExtResource("1_ci")',
        'content_name = &"cosmetics"',
        f"version = {int(time.time())}",
        f"next_id = {next_id}",
        f"entries = Array[Dictionary]([{body}])",
        "",
    ])
    with open(INDEX_PATH, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(index)
    print(f"COSMETIC_FRAMES_PASS cosmetics={len(entries)} next_id={next_id}")


if __name__ == "__main__":
    main()
