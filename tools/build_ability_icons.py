"""Cut the Raven Fantasy Icons pack into RealmCraft's ability-icon set.

One SOURCE cell per ability family (row, col into the pack's 32x32 spritesheet),
then one generated file per RANK: the rank-1 art untouched, higher ranks given a
progressively stronger RIM light in the art's own dominant hue plus a small
brightness lift. That keeps a chain readable as ONE move at a glance while still
giving every .tres its own icon file.

Writes assets/sprites/ui/ability_icons/<family>_<rank>.png plus an icon_map.json
next to this script, which tools/wire_ability_icons.py then points every .tres at.

The (row, col) numbers ARE the design decision — they record which pack cell each
ability wears, and they are why this script is committed rather than run once and
deleted: re-deriving them means eyeballing 2192 unlabeled cells again.

  python tools/build_ability_icons.py && python tools/wire_ability_icons.py
  godot --headless --path . --import
  godot --headless --path . tools/verify_ability_icons.tscn
"""
import os
from PIL import Image, ImageChops, ImageEnhance, ImageFilter

# The Raven Fantasy Icons pack (Clockwork Raven Studios), 32x32 sheet. NOT in the
# repo — it is a licensed art pack that lives outside it, so this points at the
# artist's copy on disk. Override with RAVEN_ICON_SHEET on another machine.
SHEET = os.environ.get(
    "RAVEN_ICON_SHEET",
    os.path.expanduser(os.path.join(
        "~", "OneDrive", "Desktop", "Aerkenelle assets", "RealmCraft Raven Assets",
        "Free - Raven Fantasy Icons", "Full Spritesheet", "32x32.png")))
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "assets", "sprites", "ui", "ability_icons")
CELL = 32
COLS = 16

# family -> (row, col, [ability slugs in RANK ORDER])
# Rank order is the display order (I, II, III...), which is NOT always the file
# suffix order: several families ship the base rank under an unsuffixed name and
# the top rank under the bare family name (meteor, mana_font, rain_of_arrows...).
FAMILIES = {
    # --- swordsmanship ---------------------------------------------------
    "sword_swing":       (90, 6,  ["sword_swing"]),
    "sword_spin":        (45, 4,  ["sword_spin"]),
    "whirlwind":         (49, 8,  ["sword_whirlwind", "sword_whirlwind_2", "sword_whirlwind_3",
                                   "sword_whirlwind_4", "sword_whirlwind_5"]),
    "bladestorm":        (45, 8,  ["bladestorm"]),
    "crippling_strike":  (55, 4,  ["crippling_strike"]),
    "deflect":           (41, 8,  ["sword_deflect", "sword_deflect_2"]),
    "berserk":           (67, 7,  ["sword_berserk", "sword_berserk_2", "sword_berserk_3"]),
    "rally":             (68, 2,  ["sword_rally", "sword_rally_2"]),
    "last_stand":        (53, 10, ["last_stand", "last_stand_2", "last_stand_3"]),
    # --- heavy weapons ---------------------------------------------------
    "punch":             (41, 6,  ["punch"]),
    "ground_slam":       (65, 3,  ["hammer_slam"]),
    "crushing_blow":     (52, 4,  ["crushing_blow"]),
    "shockwave":         (61, 11, ["shockwave"]),
    "earthshatter":      (61, 13, ["earthshatter"]),
    "cataclysm":         (62, 5,  ["cataclysm"]),
    "aftershock":        (61, 9,  ["hammer_aftershock", "hammer_aftershock_2", "hammer_aftershock_3"]),
    "mighty_roar":       (42, 9,  ["mighty_roar", "mighty_roar_2", "mighty_roar_3"]),
    "spectral_ward":     (53, 7,  ["spectral_ward", "spectral_ward_2", "spectral_ward_3"]),
    "paladins_might":    (41, 13, ["paladins_might", "paladins_might_2", "paladins_might_3"]),
    "rampage":           (54, 4,  ["hammer_rampage", "hammer_rampage_2", "hammer_rampage_3",
                                   "hammer_rampage_4"]),
    "healing_aura":      (67, 0,  ["hammer_aura", "hammer_aura_2", "hammer_aura_3", "hammer_aura_4"]),
    # --- ranger (bow) ----------------------------------------------------
    "charged_shot":      (94, 9,  ["bow_shot"]),
    "venom_shot":        (60, 4,  ["venom_shot"]),
    "multishot":         (61, 4,  ["bow_multishot", "bow_multishot_2", "bow_multishot_3",
                                   "bow_multishot_4"]),
    "arrow_storm":       (61, 5,  ["arrow_storm", "arrow_storm_2", "arrow_storm_3", "arrow_storm_4"]),
    # Three real arrows falling — see composed(). The recoloured ice-rain cone
    # this replaced read as a range of mountains.
    "rain_of_arrows":    (134, 9, ["rain_of_arrows_1", "rain_of_arrows_2", "rain_of_arrows_3",
                                   "rain_of_arrows"],
                          {"tint": (222, 186, 132),
                           "compose": [(0, 12, 0.58, True), (8, 6, 0.58, True),
                                       (16, 0, 0.58, True)]}),
    # One heavy broadhead, kept cold: the shaft colour is the tell that this is
    # the arrow that roots what it hits.
    "pinning_arrow":     (134, 9, ["pinning_arrow_1", "pinning_arrow_2", "pinning_arrow_3",
                                   "pinning_arrow"]),
    "deadeye":           (61, 10, ["deadeye", "deadeye_2", "deadeye_3", "deadeye_4"]),
    # Three arrows abreast, mid-flight.
    "rapid_fire":        (134, 9, ["rapid_fire_1", "rapid_fire_2", "rapid_fire_3", "rapid_fire_4"],
                          {"tint": (222, 186, 132),
                           "compose": [(1, 1, 0.54, False), (8, 8, 0.54, False),
                                       (15, 15, 0.54, False)]}),
    # --- arcanist (wand) -------------------------------------------------
    "magic_bolt":        (93, 6,  ["wand_bolt"]),
    "arc_strike":        (64, 0,  ["arc_strike"]),
    "ember_bolt":        (62, 1,  ["ember_bolt"]),
    "fireball":          (62, 0,  ["fireball_1", "fireball", "fireball_2", "fireball_3"]),
    "overload":          (64, 15, ["overload"]),
    "mending_bolt":      (68, 4,  ["wand_heal", "wand_heal_2", "wand_heal_3", "wand_heal_4"]),
    "blink":             (68, 0,  ["blink", "blink_2", "blink_3", "blink_4"]),
    "meteor":            (62, 8,  ["meteor_1", "meteor_2", "meteor_3", "meteor"]),
    "arcane_wall":       (63, 5,  ["arcane_wall_1", "arcane_wall", "arcane_wall_2"]),
    "mana_font":         (59, 6,  ["mana_font_1", "mana_font_2", "mana_font", "mana_font_4"]),
    # --- battlemage (book) -----------------------------------------------
    "lightning_lash":    (64, 3,  ["lightning_lash", "lightning_lash_2", "lightning_lash_3"]),
    "static_field":      (64, 14, ["static_field", "static_field_2", "static_field_3"]),
    "blood_feast":       (66, 7,  ["blood_feast", "blood_feast_2", "blood_feast_3", "blood_feast_4"]),
    "frost_nova":        (49, 2,  ["frost_nova", "frost_nova_2", "frost_nova_3", "frost_nova_4"]),
    "battle_form":       (68, 7,  ["battle_form_1", "battle_form", "battle_form_2", "battle_form_3"]),
    "life_siphon":       (46, 7,  ["life_siphon"]),
    "recall":            (43, 7,  ["recall"]),
    # --- gathering tool basic attacks (HUD left-click tile, not tree nodes)
    "axe_swing":         (91, 0,  ["wooden_axe_swing"]),
    "pickaxe_swing":     (56, 6,  ["wooden_pickaxe_swing"]),
    "sickle_swing":      (58, 10, ["wooden_sickle_swing"]),
    "fishing_cast":      (59, 4,  ["wooden_fishing_rod_swing"]),
}

# Mastery PASSIVE nodes, same shape: family -> (row, col, [node ids in rank order]).
# Separate table because these are addressed by NODE id inside a tree .tres, not
# by an ability slug.
PASSIVES = {
    "p_toughness":   (42, 8,  ["book_toughness", "book_toughness_2", "book_toughness_3"]),
    "p_focus":       (63, 15, ["book_focus", "book_focus_2", "book_focus_3", "book_focus_4",
                               "book_focus_5"]),
    "p_mana_siphon": (68, 5,  ["bow_venom_shot"]),
    "p_hardened":    (68, 12, ["bow_survival", "bow_survival_2", "bow_survival_3"]),
    "p_lightstep":   (54, 9,  ["bow_lightstep", "bow_lightstep_2"]),
    "p_hawkeye":     (44, 14, ["bow_hawkeye", "bow_hawkeye_2"]),
    "p_steady_aim":  (68, 11, ["bow_steady_aim", "bow_steady_aim_2"]),
    "p_executioner": (42, 0,  ["hammer_executioner", "hammer_executioner_2", "hammer_executioner_3"]),
    "p_juggernaut":  (41, 2,  ["hammer_juggernaut"]),
    "p_ironhide":    (68, 10, ["hammer_ironhide"]),
    "p_momentum":    (54, 0,  ["hammer_momentum"]),
    "p_iron_guard":  (53, 5,  ["sword_parry"]),
    "p_fortitude":   (41, 4,  ["sword_fortitude", "sword_fortitude_2"]),
    "p_tempo":       (64, 10, ["sword_tempo", "sword_tempo_2"]),
    "p_bloodrush":   (41, 10, ["sword_bloodrush"]),
    "p_attunement":  (61, 7,  ["wand_attunement", "wand_attunement_2", "wand_attunement_3"]),
    "p_warding":     (53, 9,  ["wand_warding", "wand_warding_2", "wand_warding_3"]),
    "p_clarity":     (41, 3,  ["wand_clarity", "wand_clarity_2"]),
}


def dominant_hue(img):
    """Average colour of the opaque pixels, pushed to full saturation.

    The glow has to belong to the art, not to a palette I picked: a frost icon
    glowing orange reads as a different ability, not a higher rank.
    """
    px = img.load()
    r = g = b = n = 0
    for y in range(img.height):
        for x in range(img.width):
            cr, cg, cb, ca = px[x, y]
            if ca > 128:
                r += cr; g += cg; b += cb; n += 1
    if n == 0:
        return (255, 255, 255)
    r, g, b = r / n, g / n, b / n
    mx = max(r, g, b, 1.0)
    boost = 255.0 / mx
    return (int(min(255, r * boost)), int(min(255, g * boost)), int(min(255, b * boost)))


def tiered(base, rank, total):
    """Rank art: the base cell plus a rim light that grows with the rank.

    Rank 1 is the untouched pack art on purpose — the escalation has to read as
    "this one is MORE", which needs a plain baseline to be more than.
    """
    if rank == 0 or total == 1:
        return base.copy()
    strength = rank / float(max(1, total - 1))  # 0..1 across the chain

    # RIM only: the dilated silhouette MINUS the silhouette, so the glow is a
    # band hugging the outline and can never paint the gaps inside the art.
    #
    # The first attempt blurred the whole dilated silhouette instead, which was
    # fine for a compact glyph and terrible for a sparse one: on a starburst the
    # blur bled through every gap between the rays and the "glow" rendered as an
    # opaque square box behind the icon. A rim is coverage-independent — art that
    # fills its cell simply shows less of it, rather than turning into a tile.
    pad = 2
    big = Image.new("RGBA", (base.width + pad * 2, base.height + pad * 2), (0, 0, 0, 0))
    big.paste(base, (pad, pad))
    alpha = big.split()[3]
    rim = ImageChops.subtract(alpha.filter(ImageFilter.MaxFilter(3)), alpha)
    rim = rim.filter(ImageFilter.GaussianBlur(0.7))
    rim = ImageChops.multiply(rim, Image.new("L", rim.size, int(255 * (0.55 + 0.45 * strength))))
    hue = dominant_hue(base)
    glow = Image.new("RGBA", big.size, hue + (0,))
    glow.putalpha(rim)
    out = Image.alpha_composite(glow, big)
    out = out.crop((pad, pad, pad + base.width, pad + base.height))

    # A touch more light in the art itself, so a higher rank still reads brighter
    # on art whose rim is clipped by the cell edge. Brightness alone washes the
    # pack's shading out, so it goes up WITH saturation, not instead of it.
    art = ImageEnhance.Brightness(base).enhance(1.0 + 0.16 * strength)
    art = ImageEnhance.Color(art).enhance(1.0 + 0.30 * strength)
    return Image.alpha_composite(out, art)


def tinted(img, rgb):
    """Recolour the art to [param rgb] while keeping its shading.

    For the handful of abilities the pack has the right SHAPE for but the wrong
    element — a cone of projectiles raining down is exactly Rain of Arrows, it is
    just drawn as ice. Luminance is preserved and used as the multiplier, so the
    pack's highlights and dark edges survive the recolour instead of flattening
    into a silhouette.
    """
    out = img.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            # Bias upward so mid-tones do not go muddy; clamp per channel.
            k = min(1.0, lum * 1.15)
            px[x, y] = (int(rgb[0] * k), int(rgb[1] * k), int(rgb[2] * k), a)
    return out


def composed(cell, placements):
    """Build an icon by stamping the trimmed source art several times.

    The pack's four "arrow" cells in the elemental rows are ENERGY BOLTS, not
    arrows — a glowing lightning dart reads as a spell no matter what ability it
    is bolted to, which is exactly why Rapid Fire and Pinning Arrow looked like
    magic. Row 134 carries real arrows (shaft + head + fletching), so the bow
    ability icons are stamped from those instead: three parallel arrows in flight
    for Rapid Fire, three falling for Rain of Arrows.

    Each placement is (x, y, scale, flip_vertical) on the 32x32 cell.
    """
    out = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    for x, y, scale, flip in placements:
        piece = cell.transpose(Image.FLIP_TOP_BOTTOM) if flip else cell
        box = piece.getbbox()
        if box is None:
            continue
        piece = piece.crop(box)
        piece = piece.resize(
            (max(1, int(piece.width * scale)), max(1, int(piece.height * scale))),
            Image.NEAREST)
        out.alpha_composite(piece, (x, y))
    return out


def main():
    sheet = Image.open(SHEET).convert("RGBA")
    os.makedirs(OUT, exist_ok=True)
    mapping = {}
    written = []
    for table in (FAMILIES, PASSIVES):
        for family, entry in table.items():
            row, col, slugs = entry[0], entry[1], entry[2]
            opts = entry[3] if len(entry) > 3 else {}
            cell = sheet.crop((col * CELL, row * CELL, (col + 1) * CELL, (row + 1) * CELL))
            if cell.getbbox() is None:
                raise SystemExit("EMPTY CELL for %s at r%dc%d" % (family, row, col))
            if "tint" in opts:
                cell = tinted(cell, opts["tint"])
            if "compose" in opts:
                cell = composed(cell, opts["compose"])
            for i, slug in enumerate(slugs):
                name = family if len(slugs) == 1 else "%s_%d" % (family, i + 1)
                path = os.path.join(OUT, name + ".png")
                tiered(cell, i, len(slugs)).save(path)
                mapping[slug] = name + ".png"
                written.append(name + ".png")
    print("ICONS_WRITTEN", len(written))
    import json
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "icon_map.json"), "w") as fh:
        json.dump(mapping, fh, indent=1, sort_keys=True)
    print("MAPPED_SLUGS", len(mapping))


if __name__ == "__main__":
    main()
