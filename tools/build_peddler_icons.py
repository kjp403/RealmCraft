"""Generate the Traveling Peddler's item icons.

These are PLACEHOLDER art, generated rather than drawn, for the same reason the
ability icons are generated: twelve one-off 16x16 sprites hand-cut into the repo
would be twelve files nobody can regenerate, and the peddler's art direction is
not settled. Each icon is a tier-coloured chip (gold / purple / blue, matching
PeddlerItemData.TIER_COLORS) carrying a hand-authored 16x16 glyph mask.

The MASKS are the design decision here, which is why this script is committed:
they record what each good looks like, and re-deriving them means drawing twelve
sprites again. Replace an entry with real art by dropping the PNG in and removing
its mask.

Writes assets/sprites/items/icons/peddler/<slug>.png.

  python tools/build_peddler_icons.py
  godot --headless --path . --import
"""
import os

from PIL import Image

OUT_DIR = os.path.join("assets", "sprites", "items", "icons", "peddler")
SIZE = 16

# Tier chip colours — kept in sync BY HAND with PeddlerItemData.TIER_COLORS.
# Duplicated rather than parsed out of the .gd because this is a build-time
# placeholder generator, and a parser for one dictionary is more to go wrong than
# three tuples are.
TIER_FILL = {
    "S": (255, 214, 64),
    "A": (168, 107, 242),
    "B": (89, 158, 255),
}
BORDER_OUTER = (13, 10, 8, 255)
BORDER_INNER = (247, 245, 235, 255)
INK = (34, 26, 20, 255)
LIT = (252, 250, 242, 255)

# Glyph masks, 16 rows x 16 columns.
#   ' ' tier fill      '#' ink (dark)      '.' highlight (light)
# The outer two rings are overwritten by the border, so glyphs live in the
# 12x12 middle -- rows/cols 2..13.
MASKS = {
    # --- S tier -------------------------------------------------------------
    "peddler_vault_key": [
        "                ",
        "                ",
        "      ####      ",
        "     #....#     ",
        "     #.##.#     ",
        "     #....#     ",
        "      #..#      ",
        "       ##       ",
        "       ##       ",
        "       ##       ",
        "       ###      ",
        "       ##       ",
        "       ###      ",
        "       ##       ",
        "                ",
        "                ",
    ],
    "chronos_clock": [
        "                ",
        "                ",
        "      ####      ",
        "    ##....##    ",
        "   #........#   ",
        "   #...##...#   ",
        "  #....##....#  ",
        "  #....####..#  ",
        "  #.........+#  ",
        "  #.........#   ",
        "   #.......#    ",
        "   ##.....##    ",
        "     #####      ",
        "                ",
        "                ",
        "                ",
    ],
    "hunter_charm": [
        "                ",
        "                ",
        "    #      #    ",
        "    ##    ##    ",
        "     #.##.#     ",
        "     #....#     ",
        "    #......#    ",
        "    #.####.#    ",
        "   #........#   ",
        "   #.#....#.#   ",
        "    #......#    ",
        "     #....#     ",
        "      #..#      ",
        "       ##       ",
        "                ",
        "                ",
    ],
    # --- A tier -------------------------------------------------------------
    "anvil_stabilizer": [
        "                ",
        "                ",
        "                ",
        "    ########    ",
        "   #........##  ",
        "   #.........#  ",
        "    ##......#   ",
        "     #.....#    ",
        "      #...#     ",
        "      #...#     ",
        "     #.....#    ",
        "    ##.....##   ",
        "   ###########  ",
        "                ",
        "                ",
        "                ",
    ],
    "portable_deposit_box": [
        "                ",
        "                ",
        "    ########    ",
        "   #........#   ",
        "   #.######.#   ",
        "   ##########   ",
        "   #........#   ",
        "   #...##...#   ",
        "   #...##...#   ",
        "   #........#   ",
        "   #........#   ",
        "   ##########   ",
        "                ",
        "                ",
        "                ",
        "                ",
    ],
    "mystery_seed": [
        "                ",
        "                ",
        "        #       ",
        "       #.#      ",
        "      #...#     ",
        "     #.....#    ",
        "     #.....#    ",
        "      #...#     ",
        "       #.#      ",
        "        #       ",
        "      ##.##     ",
        "     #.....#    ",
        "      #####     ",
        "                ",
        "                ",
        "                ",
    ],
    "botanist_skilling_crate": [
        "                ",
        "                ",
        "   ##########   ",
        "   #..#....#.#  ",
        "   #.#.#..#.##  ",
        "   #.##..##..#  ",
        "   #.#.##.#..#  ",
        "   #.##..##..#  ",
        "   #.#.#..#.##  ",
        "   #..#....#.#  ",
        "   ##########   ",
        "                ",
        "                ",
        "                ",
        "                ",
        "                ",
    ],
    # --- B tier -------------------------------------------------------------
    "biome_recall_scroll": [
        "                ",
        "                ",
        "    ########    ",
        "   #.#......#   ",
        "   #.#......#   ",
        "   #.#.####.#   ",
        "   #.#......#   ",
        "   #.#.####.#   ",
        "   #.#......#   ",
        "   #.#.###..#   ",
        "   #.#......#   ",
        "    ########    ",
        "                ",
        "                ",
        "                ",
        "                ",
    ],
    "prismatic_dye": [
        "                ",
        "                ",
        "       ##       ",
        "       ##       ",
        "      #..#      ",
        "      #..#      ",
        "     #....#     ",
        "     #....#     ",
        "    #......#    ",
        "    #.####.#    ",
        "   #........#   ",
        "   #........#   ",
        "    ########    ",
        "                ",
        "                ",
        "                ",
    ],
    "wandering_tonic": [
        "                ",
        "                ",
        "      ####      ",
        "      #..#      ",
        "      #..#      ",
        "     #....#     ",
        "     #....#     ",
        "    #......#    ",
        "    #.####.#    ",
        "    #.####.#    ",
        "    #.####.#    ",
        "     ######     ",
        "                ",
        "                ",
        "                ",
        "                ",
    ],
    "hearth_stew": [
        "                ",
        "                ",
        "      #  #      ",
        "     #    #     ",
        "      #  #      ",
        "                ",
        "   ##########   ",
        "   #........#   ",
        "   ##########   ",
        "    #......#    ",
        "     #....#     ",
        "      ####      ",
        "                ",
        "                ",
        "                ",
        "                ",
    ],
    # Not peddler stock -- the Vault Chest's payout. Given a chip so it does not
    # sit in the bag wearing the default leaf.
    "boss_contract_key": [
        "                ",
        "                ",
        "     ######     ",
        "    #......#    ",
        "    #.####.#    ",
        "    #.#..#.#    ",
        "    #.####.#    ",
        "    #......#    ",
        "     ##..##     ",
        "      #..#      ",
        "      #..##     ",
        "      #..#      ",
        "      #..##     ",
        "      ####      ",
        "                ",
        "                ",
    ],
}

# Which tier chip each glyph sits on. boss_contract_key rides the S chip: it is
# what the 500,000-gold key buys.
TIERS = {
    "peddler_vault_key": "S",
    "chronos_clock": "S",
    "hunter_charm": "S",
    "anvil_stabilizer": "A",
    "portable_deposit_box": "A",
    "mystery_seed": "A",
    "botanist_skilling_crate": "A",
    "biome_recall_scroll": "B",
    "prismatic_dye": "B",
    "wandering_tonic": "B",
    "hearth_stew": "B",
    "boss_contract_key": "S",
}


def build(slug, mask, tier):
    fill = TIER_FILL[tier] + (255,)
    img = Image.new("RGBA", (SIZE, SIZE), fill)
    px = img.load()

    for y, row in enumerate(mask):
        if y >= SIZE:
            break
        for x, ch in enumerate(row[:SIZE]):
            if ch == "#":
                px[x, y] = INK
            elif ch == ".":
                px[x, y] = LIT

    # Border last so a glyph that overruns cannot eat the chip edge.
    last = SIZE - 1
    for i in range(SIZE):
        px[i, 0] = px[i, last] = px[0, i] = px[last, i] = BORDER_OUTER
    for i in range(1, last):
        px[i, 1] = px[i, last - 1] = px[1, i] = px[last - 1, i] = BORDER_INNER
    return img


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for slug, mask in MASKS.items():
        tier = TIERS[slug]
        out = os.path.join(OUT_DIR, slug + ".png")
        build(slug, mask, tier).save(out)
        print("wrote", out)
    print("%d peddler icons" % len(MASKS))


if __name__ == "__main__":
    main()
