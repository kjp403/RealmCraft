"""Import Mana Seed character sheets into the project and regenerate PaperDollData.

The packs ship as `char_a_<page>_<layer>_<item>_v<NN>.png`, 512x512, laid out as an
8x8 grid of 64x64 cells (see the pack's own "using this base.txt"):

    rows 0-3   standing (col 0), push (1-2), pull (3-4), jump (5-7)
    rows 4-7   walk (cols 0-5) plus the two extra run frames (cols 6-7)
    row order  DOWN, UP, RIGHT, LEFT   (verified against the art, not assumed)

Layer z-order is the pack's own numeric prefix:

    0bot < 1out < 2clo < 3fac < 4har < 5hat < 6tla < 7tlb

This copies the sheets we use into assets/sprites/characters/manaseed/<layer>/ and
writes source/common/gameplay/characters/player/paperdoll_data.gd from what
actually landed on disk, so the rosters can never claim art that is not there.

Usage:
    python tools/paperdoll/import_manaseed.py --src "<extracted packs dir>"
"""

from __future__ import annotations

import argparse
import collections
import glob
import os
import re
import shutil
from typing import Dict, List, Set

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEST = os.path.join(REPO, "assets", "sprites", "characters", "manaseed")
DATA_GD = os.path.join(
    REPO, "source", "common", "gameplay", "characters", "player", "paperdoll_data.gd"
)

FRAME = 64
SHEET = 512
COLS = SHEET // FRAME
ROWS = SHEET // FRAME

# Page 1 is walk/run/stand - the only page the world rig needs today. The combat
# pages (pONE/pBOW/pPOL) and skilling pages (p2/p3/p4) are imported too so the
# skilling professions and weapon animations can be wired without re-importing.
PAGES = ("p1", "p2", "p3", "p4", "pONE1", "pBOW1", "pPOL1")

# Layers we mount, in draw order. `3fac` and `0bot` exist in the packs but nothing
# in the game drives them yet; they are imported so they are ready.
LAYERS = ("0bot", "1out", "2clo", "3fac", "4har", "5hat", "6tla", "7tlb")

FILE_RE = re.compile(
    r"char_a_(?P<page>p[\w]+?)_(?P<layer>\d(?:bas|bot|out|clo|fac|har|hat|tla|tlb))"
    r"_(?P<item>\w{4})_v(?P<var>\d+)\.png$"
)

# Human-readable names for the four-letter item codes, used by the creator UI.
ITEM_NAMES: Dict[str, str] = {
    # bodies
    "humn": "Human", "demn": "Demon", "gbln": "Goblin",
    # outfits
    "boxr": "Boxers", "undi": "Undershirt", "pfpn": "Farmhand", "pfdr": "Farm Dress",
    "angl": "Angler", "bksm": "Blacksmith", "alch": "Alchemist", "fstr": "Forester",
    # cloaks
    "lnpl": "Long Cloak", "mnpl": "Mantle",
    # hair
    "bob1": "Bob", "bob2": "Long Bob", "dap1": "Dapper", "flat": "Flat",
    "fro1": "Afro", "pon1": "Ponytail", "spk2": "Spiked",
    # hats
    "band": "Bandana", "hddn": "Hood", "hdpl": "Hood (Up)", "pfbn": "Bonnet",
    "pfht": "Straw Hat", "pnty": "Pointed Hat", "rnht": "Rain Hat",
    # face
    "gogl": "Goggles",
}


def scan(src: str) -> Dict[str, Dict[str, Dict[str, Set[str]]]]:
    """layer -> item -> page -> {variants}"""
    found: Dict[str, Dict[str, Dict[str, Set[str]]]] = collections.defaultdict(
        lambda: collections.defaultdict(lambda: collections.defaultdict(set))
    )
    for path in glob.glob(os.path.join(src, "**", "*.png"), recursive=True):
        match = FILE_RE.search(os.path.basename(path))
        if not match:
            continue
        g = match.groupdict()
        found[g["layer"]][g["item"]][g["page"]].add(g["var"])
    return found


def copy_sheets(src: str, pages: Set[str]) -> Dict[str, int]:
    """Copy every sheet for the wanted pages into DEST/<layer>/, flat."""
    counts: Dict[str, int] = collections.Counter()
    for path in glob.glob(os.path.join(src, "**", "*.png"), recursive=True):
        name = os.path.basename(path)
        match = FILE_RE.search(name)
        if not match:
            continue
        g = match.groupdict()
        if g["page"] not in pages:
            continue
        layer_dir = os.path.join(DEST, g["layer"])
        os.makedirs(layer_dir, exist_ok=True)
        target = os.path.join(layer_dir, name)
        # Some packs ship the same sheet twice (a "comp. v01" and a combat-animation
        # rebuild). Prefer the LARGER file: the combat rebuilds add frames.
        if os.path.exists(target) and os.path.getsize(target) >= os.path.getsize(path):
            continue
        shutil.copy2(path, target)
        counts[g["layer"]] += 1
    return counts


def variants_of(found, layer: str, item: str, page: str = "p1") -> List[str]:
    return sorted(found.get(layer, {}).get(item, {}).get(page, set()))


def gd_str_array(items) -> str:
    return "[%s]" % ", ".join(f'&"{s}"' for s in items)


def write_data(found) -> None:
    """Write paperdoll_data.gd from what is actually on disk."""
    bodies = sorted(variants_of(found, "0bas", "humn"))
    hair_styles = sorted(found.get("4har", {}).keys())
    hair_colors = sorted(variants_of(found, "4har", hair_styles[0])) if hair_styles else []
    outfits = sorted(found.get("1out", {}).keys())
    hats = sorted(found.get("5hat", {}).keys())
    cloaks = sorted(found.get("2clo", {}).keys())

    def name_map(codes) -> str:
        pairs = ",\n".join(
            f'\t&"{c}": "{ITEM_NAMES.get(c, c.capitalize())}"' for c in codes
        )
        return "{\n%s,\n}" % pairs if pairs else "{}"

    lines = [
        "class_name PaperDollData",
        "## GENERATED by tools/paperdoll/import_manaseed.py - do not edit by hand.",
        "##",
        "## Describes the Mana Seed sheet layout and the rosters actually present in",
        "## assets/sprites/characters/manaseed/. Re-run the importer after adding a pack.",
        "",
        f"const FRAME_SIZE: int = {FRAME}",
        f"const SHEET_SIZE: int = {SHEET}",
        f"const GRID_COLS: int = {COLS}",
        f"const GRID_ROWS: int = {ROWS}",
        "",
        "## Row order on every page, verified against the art rather than assumed.",
        "enum Facing { DOWN = 0, UP = 1, RIGHT = 2, LEFT = 3 }",
        "",
        "## Rows 0-3 hold the standing/push/pull/jump poses; rows 4-7 hold walk+run.",
        "const STAND_ROW_BASE: int = 0",
        "const WALK_ROW_BASE: int = 4",
        "",
        "## Standing is a single cell; walk is the first six columns.",
        "const STAND_COL: int = 0",
        "const WALK_COLS: Array[int] = [0, 1, 2, 3, 4, 5]",
        "## Run reuses walk frames but swaps in the two dedicated run frames (cols 6,7)",
        "## for the 3rd and 6th - straight from the pack's own guide.",
        "const RUN_COLS: Array[int] = [0, 1, 6, 3, 4, 7]",
        "",
        "## Per-frame hold in seconds, from the pack's timing guide. Run is deliberately",
        "## uneven (80/55/125) - even timing makes the borrowed frames read wrong.",
        "const WALK_FRAME_TIME: float = 0.135",
        "const RUN_FRAME_TIMES: Array[float] = [0.08, 0.055, 0.125, 0.08, 0.055, 0.125]",
        "",
        "## Paper-doll draw order, straight from the pack's naming convention.",
        "const LAYER_ORDER: Array[StringName] = "
        + gd_str_array(["0bot", "1out", "2clo", "3fac", "4har", "5hat", "6tla", "7tlb"]),
        "",
        "## Creator rosters - only entries with art on disk.",
        f"const BODY_VARIANTS: Array[StringName] = {gd_str_array(bodies)}",
        f"const HAIR_STYLES: Array[StringName] = {gd_str_array(hair_styles)}",
        f"const HAIR_COLORS: Array[StringName] = {gd_str_array(hair_colors)}",
        f"const OUTFITS: Array[StringName] = {gd_str_array(outfits)}",
        f"const HATS: Array[StringName] = {gd_str_array(hats)}",
        f"const CLOAKS: Array[StringName] = {gd_str_array(cloaks)}",
        "",
        "## Display names for the four-letter pack codes.",
        f"const ITEM_NAMES: Dictionary = {name_map(sorted(set(hair_styles) | set(outfits) | set(hats) | set(cloaks)))}",
        "",
        "## Per-item variant counts, so the creator never offers a colour that is",
        "## missing for one style (hair variants differ: pon1 ships 13, the rest 14).",
        "const VARIANTS: Dictionary = {",
    ]
    # Every mountable layer, not just clothing: weapons (6tla) and offhands (7tlb)
    # are resolved through the same variant table, and omitting them made every
    # weapon fall back to a "v00" that does not exist (variants start at v01).
    for layer in ("0bot", "1out", "2clo", "3fac", "4har", "5hat", "6tla", "7tlb"):
        for item in sorted(found.get(layer, {})):
            vs = variants_of(found, layer, item)
            if vs:
                lines.append(f'\t&"{layer}/{item}": {gd_str_array(vs)},')
    lines += ["}", ""]

    os.makedirs(os.path.dirname(DATA_GD), exist_ok=True)
    with open(DATA_GD, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="directory of extracted Mana Seed packs")
    ap.add_argument("--pages", default=",".join(PAGES))
    args = ap.parse_args()

    if not os.path.isdir(args.src):
        print("source directory not found:", args.src)
        return 1

    found = scan(args.src)
    if not found:
        print("no Mana Seed sheets found under", args.src)
        return 1

    pages = set(args.pages.split(","))
    counts = copy_sheets(args.src, pages)
    write_data(found)

    print("copied sheets by layer:")
    for layer in sorted(counts):
        print(f"  {layer}: {counts[layer]}")
    print("\nrosters written to", os.path.relpath(DATA_GD, REPO))
    for layer in ("0bas", "1out", "2clo", "3fac", "4har", "5hat", "6tla", "7tlb"):
        items = found.get(layer, {})
        if items:
            print(f"  {layer}: {len(items)} items -> {', '.join(sorted(items))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
