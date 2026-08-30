"""Build the SpriteFrames for the Secret Lab set pieces in the sewer biomes.

The Epic RPG World Sewers pack ships its lab props as standalone PNGs, not as
cells of `atlas-props.png`, and none of them is a multiple of 32: the capsule
bank is 185x181 and the steam engine 149x151. They cannot become TileSet tiles
without either rescaling the art or cropping it, so they are mounted as
`AnimatedDeco` instead -- which is also what makes the capsule liquid and the
engine flywheel animate.

The capsule bank is two layers on one canvas: `capsules and pipes` is the glass
and plumbing, and `active capsule liquid` is an eight-frame glow drawn on the
SAME 185x181 canvas, meant to sit on top of it. They are emitted as two frames
resources and stacked as two decos at one position rather than composited here,
so the glow can be tinted and lit without touching the base plate.

Written as text rather than through ResourceSaver: a headless `-s` save strips
`uid=` out of the resource and every ext_resource it points at.

    python tools/build_sewer_lab_frames.py
"""

import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "source", "common", "gameplay", "props", "sprite_frames")
PACK = "res://assets/sprites/environment/rpgw_sewers/EPIC RPG World - Sewers V1.5/Props/"

# name -> (source png, frame width, frame height, frame count, fps)
SHEETS = {
    "deco_lab_capsules": ("Secret Lab - capsules and pipes.png", 185, 181, 1, 1.0),
    "deco_lab_capsule_liquid": (
        "Secret Lab - active capsule liquid-with creature.png", 185, 181, 8, 8.0),
    "deco_lab_steam_engine": ("Secret Lab-steam engine ish.png", 149, 151, 4, 6.0),
    "deco_lab_wires": ("secret lab - wire ish.png", 98, 95, 1, 1.0),
    "deco_lab_capsule_small": ("Secret Lab - active capsule.png", 32, 64, 8, 8.0),
}


def build(name, png, fw, fh, frames, fps):
    ids = ["AtlasTexture_%s%d" % (name.replace("deco_lab_", "")[:5], i) for i in range(frames)]
    out = ['[gd_resource type="SpriteFrames" load_steps=%d format=3]' % (frames + 2), ""]
    out.append('[ext_resource type="Texture2D" path="%s%s" id="1_src"]' % (PACK, png))
    out.append("")
    for i, tid in enumerate(ids):
        out.append('[sub_resource type="AtlasTexture" id="%s"]' % tid)
        out.append('atlas = ExtResource("1_src")')
        out.append("region = Rect2(%d, 0, %d, %d)" % (i * fw, fw, fh))
        out.append("")
    out.append("[resource]")
    body = ", ".join(
        '{\n"duration": 1.0,\n"texture": SubResource("%s")\n}' % t for t in ids)
    out.append('animations = [{\n"frames": [%s],\n"loop": true,\n"name": &"default",\n"speed": %s\n}]'
               % (body, fps))
    path = os.path.join(OUT, name + ".tres")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")
    print("  %-26s %d frame(s) %dx%d" % (name + ".tres", frames, fw, fh))


if __name__ == "__main__":
    for name, spec in SHEETS.items():
        build(name, *spec)
    print("SEWER_LAB_FRAMES_BUILT")
