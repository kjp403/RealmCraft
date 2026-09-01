"""Write the Traveling Peddler's paired content: one bag Item and one stock row
per good, from ONE table.

The pairing is the point. A PeddlerItemData's `id` must equal its Item's slug or
the shop hands out nothing, and the price, name and blurb have to read the same
in the cart and in the tooltip. Authoring twelve pairs by hand is twenty-four
files and twelve chances to typo half of one, so the table below is the source
and both .tres sets are written from it.

BROKERED rows sell an item the game ALREADY has (the PvM chests). No item .tres
is written for those -- the chest is authored under items/chests/ with a real
loot table under combat/chests/, and the Peddler is only another shop that
stocks it. Its stock id IS its existing slug, so nothing downstream has to know
the difference.

Written as TEXT, never through ResourceSaver: a headless `-s` save strips uid=
from the resource and every ext_resource it names, which quietly breaks scene
references elsewhere in the project.

Ids are NOT invented on a re-run. An existing .tres keeps the metadata/id it
already has, because that id is what the committed items index maps to this path
-- reassigning it here would leave the .tres and the index disagreeing, and
load_by_id would hand back the wrong item. Only a brand new good is given the
next free id from ITEM_ID_BASE, and running tools/update_items_index.gd afterwards
is what makes it resolvable.

  python tools/build_peddler_content.py
  godot --headless --path . --import
  godot --headless --path . -s tools/update_items_index.gd
"""
import io
import os

ITEM_DIR = os.path.join("source", "common", "gameplay", "items", "peddler")
STOCK_DIR = os.path.join("source", "common", "gameplay", "peddler", "stock")
ICON_DIR = "res://assets/sprites/items/icons/peddler"
ACTION_DIR = "res://source/common/gameplay/peddler/actions"

ITEM_SCRIPT = "res://source/common/gameplay/items/peddler_good_item.gd"
PLAIN_ITEM_SCRIPT = "res://source/common/gameplay/items/item.gd"
STOCK_SCRIPT = "res://source/common/gameplay/peddler/peddler_item_data.gd"

# First id handed to a good that has never been written before. The items index
# sat at next_id 630 when this was written; update_items_index.gd renumbered the
# first batch from there in ITS order, and existing_id() below is what keeps this
# script from arguing with it.
ITEM_ID_BASE = 630

# (slug, display name, tier, price, action script or None, usable, vendor_value,
#  stack_limit, description)
#
# vendor_value is 0 across the board: these are peddler goods, not junk, and a
# 500,000-gold key that an NPC would buy back for anything at all is a gold
# faucet pointed at the wrong end of the economy.
GOODS = [
    # --- S tier ---------------------------------------------------------------
    ("peddler_vault_key", "Peddler's Vault Key", "S", 500000, None, False, 1,
     "A key the Peddler will sell you and will not use for you. It opens the "
     "strongbox beside their cart, once, and the lock keeps the key."),
    ("chronos_clock", "Chronos Clock", "S", 250000, "chronos_clock_action", True, 1,
     "A cased clock that runs a little ahead of the world. The Peddler will not "
     "say by how much, and will not be drawn on what that is worth."),
    ("hunter_charm", "Hunter's Charm", "S", 350000, "hunter_charm_action", True, 0,
     "A tooth on a wire, worn smooth. For two hours the rarest thing a great "
     "beast is carrying leans very slightly toward the person wearing it."),
    # --- A tier ---------------------------------------------------------------
    ("anvil_stabilizer", "Anvil Stabilizer", "A", 75000, "anvil_stabilizer_action", True, 0,
     "A weighted collar that stops a furnace drifting off heat. Fifty charges: "
     "each one holds a smelt steady, and a stabilised run can go fifty bars deep "
     "instead of ten."),
    ("portable_deposit_box", "Portable Deposit Box", "A", 100000, "portable_deposit_box_action", True, 1,
     "A strapped case with a bank's mark burned into the lid. Heavier empty than "
     "it has any right to be."),
    ("mystery_seed", "Mystery Seed", "A", 50000, "mystery_seed_action", True, 0,
     "Unlabelled, and the Peddler does not know either. Plant it and it is grown "
     "and harvested inside a breath — logs or herbs, never the same twice."),
    ("botanist_skilling_crate", "Botanist's Skilling Crate", "A", 60000, "botanists_crate_action", True, 1,
     "A slatted crate that smells of cut stems. Sealed with a botanist's wax and "
     "sold on the Peddler's word about what is under it."),
    # --- B tier ---------------------------------------------------------------
    # No action_script: the scroll is specified to open the Wayfarer's teleport
    # board, which lives entirely on the unmerged quick-travel branch. Building it
    # here would mean duplicating that feature onto origin/main. Sold and owned;
    # wire it to the board once that PR lands.
    ("biome_recall_scroll", "Biome Recall Scroll", "B", 25000, None, False, 5,
     "A road-map folded to the size of a palm, marked in a hand that clearly "
     "walked every line of it. The folds have not been worn in yet."),
    ("prismatic_dye", "Prismatic Dye", "B", 20000, "prismatic_dye_action", True, 5,
     "A stoppered vial that shows a different colour depending on which eye you "
     "close. The Peddler keeps it wrapped."),
    ("wandering_tonic", "Wandering Tonic", "B", 8000, "wandering_tonic_action", True, 10,
     "Bitter, warm, and faintly of road dust. Drunk by people who have somewhere "
     "to be and a long way to go to be there."),
    ("hearth_stew", "Hearth Stew", "B", 10000, "hearth_stew_action", True, 10,
     "A sealed crock, still hot, from a fire that is nowhere near here. Nobody "
     "has got the Peddler to explain this one."),
]

# High-end PvM chests the Peddler brokers. (existing item slug, display name,
# tier, price).
#
# THE SLUGS ARE THE MAPPING, and several do not read like their display name --
# "Ornate Gold Chest" is gold_pink_large, the same filename-vs-name trap as
# ossuran/cleetus and deep_shoals/pirates_cove. The name here is asserted against
# the item's real item_name by verify_peddler, so a wrong slug fails the gate
# instead of quietly selling the wrong chest.
#
# No entry writes an item, a loot table or an action script: all three already
# exist. A bought chest opens through UniversalChestManager / chest.open_item
# exactly like one that dropped off a boss.
BROKERED = [
    # --- S tier ---
    ("gold_steel_grand", "Grand Steel Chest", "S", 450000),
    ("gold_pink_large", "Ornate Gold Chest", "S", 400000),
    ("gold_steel_large", "Ornate Steel Chest", "S", 300000),
    # --- A tier ---
    ("gold_red_large", "Ornate Red Chest", "A", 150000),
    ("wood_gold_large", "Wood Chest (Gold, Large)", "A", 120000),
    ("wood_gold_medium", "Wood Chest (Gold, Medium)", "A", 75000),
]

# Shop copy for the brokered chests. Deliberately about WHERE the chest comes
# from rather than what is in it: the tables are authored elsewhere and a blurb
# listing contents here would be a second source of truth that rots the first
# time a table is retuned.
BROKERED_BLURB = (
    "Bought off a hunting party that needed the coin more than the contents. "
    "The Peddler has not opened it and will not be drawn on what is inside."
)

# Not stock -- what the Vault Chest pays out. Written here so it is authored
# beside the key that opens the box, and given an id from the same block.
EXTRA_ITEMS = [
    ("boss_contract_key", "Boss Contract Key", 0, 5,
     "A sealed writ of engagement, pre-paid. The contract board takes one in "
     "place of a contract's fee and asks nothing else."),
]


def tres(lines):
    return "\n".join(lines) + "\n"


def write(path, body):
    with io.open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(body)
    print("wrote", path)


def escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


def existing_id(slug):
    """metadata/id already committed for `slug`, or None.

    Ids belong to the items index once update_items_index.gd has stamped them.
    Re-deriving one here from table position would silently repoint a live id at
    a different item the first time this table is reordered.
    """
    path = os.path.join(ITEM_DIR, slug + ".tres")
    if not os.path.exists(path):
        return None
    with io.open(path, encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("metadata/id"):
                return int(line.split("=", 1)[1].strip())
    return None


def write_good_item(slug, name, item_id, usable, vendor_value, stack_limit, desc):
    body = tres([
        '[gd_resource type="Resource" script_class="PeddlerGoodItem" format=3]',
        "",
        '[ext_resource type="Script" path="%s" id="1_script"]' % ITEM_SCRIPT,
        '[ext_resource type="Texture2D" path="%s/%s.png" id="2_icon"]' % (ICON_DIR, slug),
        "",
        "[resource]",
        'script = ExtResource("1_script")',
        "usable = %s" % ("true" if usable else "false"),
        'item_name = &"%s"' % escape(name),
        'item_icon = ExtResource("2_icon")',
        'description = "%s"' % escape(desc),
        "holdable = false",
        "stack_limit = %d" % stack_limit,
        "vendor_value = %d" % vendor_value,
        'metadata/slug = &"%s"' % slug,
        "metadata/id = %d" % item_id,
    ])
    write(os.path.join(ITEM_DIR, slug + ".tres"), body)


def write_plain_item(slug, name, item_id, vendor_value, stack_limit, desc):
    body = tres([
        '[gd_resource type="Resource" script_class="Item" format=3]',
        "",
        '[ext_resource type="Script" path="%s" id="1_script"]' % PLAIN_ITEM_SCRIPT,
        '[ext_resource type="Texture2D" path="%s/%s.png" id="2_icon"]' % (ICON_DIR, slug),
        "",
        "[resource]",
        'script = ExtResource("1_script")',
        'item_name = &"%s"' % escape(name),
        'item_icon = ExtResource("2_icon")',
        'description = "%s"' % escape(desc),
        "holdable = false",
        "stack_limit = %d" % stack_limit,
        "vendor_value = %d" % vendor_value,
        'metadata/slug = &"%s"' % slug,
        "metadata/id = %d" % item_id,
    ])
    write(os.path.join(ITEM_DIR, slug + ".tres"), body)


def write_stock(slug, name, tier, price, action, desc, brokered=False, icon=None):
    # A brokered row has no peddler icon of its own -- the shop window falls back
    # to the item's real icon, which is the chest art players already recognise.
    icon_path = icon if icon else ("%s/%s.png" % (ICON_DIR, slug))
    ext = ['[ext_resource type="Script" path="%s" id="1_script"]' % STOCK_SCRIPT]
    res = [
        "[resource]",
        'script = ExtResource("1_script")',
        'id = "%s"' % slug,
        'item_name = "%s"' % escape(name),
        'description = "%s"' % escape(desc),
        "price_gold = %d" % price,
        'tier = "%s"' % tier,
    ]
    if brokered:
        res.append("brokered = true")
    else:
        ext.append('[ext_resource type="Texture2D" path="%s" id="2_icon"]' % icon_path)
        res.append('icon = ExtResource("2_icon")')
    if action:
        ext.append(
            '[ext_resource type="Script" path="%s/%s.gd" id="3_action"]' % (ACTION_DIR, action)
        )
        res.append('action_script = ExtResource("3_action")')
    body = tres(
        ['[gd_resource type="Resource" script_class="PeddlerItemData" format=3]', ""]
        + ext
        + [""]
        + res
    )
    write(os.path.join(STOCK_DIR, slug + ".tres"), body)


def main():
    os.makedirs(ITEM_DIR, exist_ok=True)
    os.makedirs(STOCK_DIR, exist_ok=True)
    known = [existing_id(g[0]) for g in GOODS] + [existing_id(e[0]) for e in EXTRA_ITEMS]
    next_id = max([ITEM_ID_BASE] + [i + 1 for i in known if i is not None])
    fresh = 0
    for slug, name, tier, price, action, usable, stack, desc in GOODS:
        item_id = existing_id(slug)
        if item_id is None:
            item_id, next_id, fresh = next_id, next_id + 1, fresh + 1
        write_good_item(slug, name, item_id, usable, 0, stack, desc)
        write_stock(slug, name, tier, price, action, desc)
    for slug, name, tier, price in BROKERED:
        write_stock(slug, name, tier, price, None, BROKERED_BLURB, brokered=True)
    for slug, name, vendor_value, stack, desc in EXTRA_ITEMS:
        item_id = existing_id(slug)
        if item_id is None:
            item_id, next_id, fresh = next_id, next_id + 1, fresh + 1
        write_plain_item(slug, name, item_id, vendor_value, stack, desc)
    print("%d goods (%d newly numbered), %d brokered stock rows" % (
        len(GOODS) + len(EXTRA_ITEMS), fresh, len(BROKERED)))


if __name__ == "__main__":
    main()
