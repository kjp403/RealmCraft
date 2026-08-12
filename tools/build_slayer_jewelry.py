#!/usr/bin/env python3
"""Build Slayer Shop gems, currency, shop stock, anvil ring recipes, and index entries.

Run from repo root:
  python tools/build_slayer_jewelry.py
"""
from __future__ import annotations

import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ITEMS = ROOT / "source/common/gameplay/items"
GEM_DIR = ITEMS / "materials/gems"
CUR_DIR = ITEMS / "currencies"
SHOP_PATH = ROOT / "source/common/gameplay/shops/resources/slayer_shop.tres"
ANVIL = ROOT / "source/common/gameplay/crafting/resources/anvil.tres"
INDEX = ROOT / "source/common/registry/indexes/items_index.tres"
NPC = ROOT / "source/common/gameplay/characters/npc/npcs/ascension_broker_vael.tres"

MATERIAL_SCRIPT = "res://source/common/gameplay/items/material_item.gd"
ITEM_SCRIPT = "res://source/common/gameplay/items/item.gd"
SHOP_SCRIPT = "res://source/common/gameplay/shops/shop_resource.gd"
ENTRY_SCRIPT = "res://source/common/gameplay/shops/shop_entry.gd"
TRADE_SCRIPT = "res://source/common/gameplay/shops/shop_trade.gd"

# family -> (display stem, icon basename per quality low/med/high/pristine)
FAMILIES = {
	"guard": (
		"Guard",
		["gem_wyrmguard", "gem_basilisk", "gem_colossus", "gem_behemoth"],
	),
	"agile": (
		"Agile",
		["gem_tempest", "gem_skyrender", "gem_nightglass", "gem_eclipse"],
	),
	"focus": (
		"Focus",
		["gem_runewoven", "gem_astral", "gem_voidsilk", "gem_aetherborn"],
	),
	"vital": (
		"Vital",
		["gem_enchanted", "gem_godsteel", "gem_empyrean", "gem_primordial"],
	),
}

QUALITIES = [
	("low", "Low Quality", "copper", 30, 1, 125),
	("medium", "Medium Quality", "iron", 60, 5, 275),
	("high", "High Quality", "silver", 100, 10, 550),
	("pristine", "Pristine", "gold", 200, 15, 1000),
]

RING_SLUG = {
	"guard": "ring_guard_{metal}",
	"agile": "ring_agile_{metal}",
	"focus": "ring_focus_{metal}",
	"vital": "ring_vital_{metal}",
}

BAR_SLUG = {
	"copper": "copper_bar",
	"iron": "iron_bar",
	"silver": "silver_bar",
	"gold": "gold_bar",
}


def sha256_file(path: Path) -> str:
	return hashlib.sha256(path.read_bytes()).hexdigest()


def write_text(path: Path, text: str) -> None:
	path.parent.mkdir(parents=True, exist_ok=True)
	path.write_text(text.replace("\r\n", "\n"), encoding="utf-8", newline="\n")
	print("wrote", path.relative_to(ROOT))


def gem_slug(family: str, quality: str) -> str:
	return f"gem_{family}_{quality}"


def build_currency() -> Path:
	path = CUR_DIR / "slayer_points.tres"
	text = f'''[gd_resource type="Resource" script_class="Item" format=3]

[ext_resource type="Texture2D" path="res://assets/sprites/ui/menu_icons_shadow/32px/realmcraft_menu_icons/Slayer.png" id="1_icon"]
[ext_resource type="Script" path="{ITEM_SCRIPT}" id="2_script"]

[resource]
script = ExtResource("2_script")
item_name = &"Slayer Points"
item_icon = ExtResource("1_icon")
description = "Earned by completing Slayer tasks. Spent at the Slayer Shop."
is_currency = true
can_trade = false
vendor_value = 0
metadata/slug = &"slayer_points"
'''
	write_text(path, text)
	return path


def build_gems() -> list[Path]:
	paths: list[Path] = []
	for family, (stem, icons) in FAMILIES.items():
		for i, (qslug, qlabel, _metal, _price, _lvl, _xp) in enumerate(QUALITIES):
			slug = gem_slug(family, qslug)
			icon = icons[i]
			name = f"{qlabel} {stem} Gem"
			desc = (
				f"A {qlabel.lower()} gem for forging {stem} rings. "
				f"Bought with Slayer Points; set into {QUALITIES[i][2].title()} metal at the anvil."
			)
			path = GEM_DIR / f"{slug}.tres"
			text = f'''[gd_resource type="Resource" script_class="MaterialItem" format=3]

[ext_resource type="Texture2D" path="res://assets/sprites/items/icons/{icon}.png" id="1_icon"]
[ext_resource type="Script" path="{MATERIAL_SCRIPT}" id="2_script"]

[resource]
script = ExtResource("2_script")
item_name = &"{name}"
item_icon = ExtResource("1_icon")
description = "{desc}"
holdable = false
can_trade = true
vendor_value = 0
stack_limit = 20
tags = PackedStringArray("slayer_gem", "{family}", "{qslug}")
metadata/slug = &"{slug}"
'''
			write_text(path, text)
			paths.append(path)
	return paths


def build_shop() -> Path:
	lines: list[str] = [
		'[gd_resource type="Resource" script_class="ShopResource" format=3]',
		"",
		f'[ext_resource type="Script" path="{ENTRY_SCRIPT}" id="1_entry"]',
		f'[ext_resource type="Script" path="{SHOP_SCRIPT}" id="2_shop"]',
		f'[ext_resource type="Script" path="{TRADE_SCRIPT}" id="3_trade"]',
		'[ext_resource type="Resource" path="res://source/common/gameplay/items/currencies/slayer_points.tres" id="4_pts"]',
	]
	ext_id = 5
	gem_ext: dict[str, str] = {}
	for family in FAMILIES:
		for qslug, _qlabel, _metal, _price, _lvl, _xp in QUALITIES:
			slug = gem_slug(family, qslug)
			eid = f"{ext_id}_{slug}"
			gem_ext[slug] = eid
			lines.append(
				f'[ext_resource type="Resource" path="res://source/common/gameplay/items/materials/gems/{slug}.tres" id="{eid}"]'
			)
			ext_id += 1

	lines.append("")
	entry_ids: list[str] = []
	for family in FAMILIES:
		for qslug, _qlabel, _metal, price, _lvl, _xp in QUALITIES:
			slug = gem_slug(family, qslug)
			sid = f"Entry_{slug}"
			entry_ids.append(sid)
			lines.extend(
				[
					f'[sub_resource type="Resource" id="{sid}"]',
					'script = ExtResource("1_entry")',
					f'item = ExtResource("{gem_ext[slug]}")',
					f"price = {price}",
					"",
				]
			)

	entries = ", ".join(f'SubResource("{sid}")' for sid in entry_ids)
	lines.extend(
		[
			"[resource]",
			'script = ExtResource("2_shop")',
			'shop_name = "Slayer Shop"',
			'currency_item = ExtResource("4_pts")',
			f"entries = Array[ExtResource(\"1_entry\")]([{entries}])",
			"buys_vendor_priced = false",
			'metadata/slug = &"slayer_shop"',
			"",
		]
	)
	write_text(SHOP_PATH, "\n".join(lines))
	return SHOP_PATH


def patch_npc() -> None:
	text = f'''[gd_resource type="Resource" script_class="NPCResource" format=3 uid="uid://cascensionbroker1"]

[ext_resource type="Script" uid="uid://ddps5vwhnf048" path="res://source/common/gameplay/characters/npc/npc_resource.gd" id="1_npc"]
[ext_resource type="Script" uid="uid://bg3vv3lo3vxog" path="res://source/common/gameplay/characters/npc/interactions/npc_interaction.gd" id="2_inter"]
[ext_resource type="Script" uid="uid://bpo804060rk5t" path="res://source/common/gameplay/characters/npc/interactions/shop_interaction.gd" id="3_shop"]
[ext_resource type="Script" uid="uid://cb4eeew5u1da1" path="res://source/common/gameplay/characters/npc/interactions/dialogue_interaction.gd" id="4_diag"]
[ext_resource type="Resource" path="res://source/common/gameplay/shops/resources/slayer_shop.tres" id="5_shop"]
[ext_resource type="SpriteFrames" uid="uid://dlopdt61exewy" path="res://source/common/gameplay/characters/sprite_frames/scholar_researcher.tres" id="6_skin"]

[sub_resource type="Resource" id="Shop_slayer"]
script = ExtResource("3_shop")
shop = ExtResource("5_shop")
label_override = "Browse Slayer Shop"

[sub_resource type="Resource" id="Talk_slayer"]
script = ExtResource("4_diag")
lines = Array[String](["I take Slayer points, not gold. Finish tasks for Durael — or Turael, if you're just starting — and bring the points here.", "These gems set the Guard, Agile, Focus, and Vital rings. Buy the quality that matches the metal you plan to forge: low for copper, medium for iron, high for silver, pristine for gold.", "Ten bars and one gem at the anvil. No shortcuts, no gold price tags."])
label_override = "How does this shop work?"

[resource]
script = ExtResource("1_npc")
npc_name = "Slayer Quartermaster Vael"
skin = ExtResource("6_skin")
greeting = "Points for gems. Gems for rings. The hunt pays — if you spend wisely."
interactions = Array[ExtResource("2_inter")]([SubResource("Shop_slayer"), SubResource("Talk_slayer")])
'''
	write_text(NPC, text)


def ensure_anvil_ring_recipes() -> None:
	"""Append copper/iron/silver/gold Guard/Agile/Focus/Vital recipes if missing."""
	text = ANVIL.read_text(encoding="utf-8")
	if "R_ring_guard_copper" in text:
		print("anvil already has entry ring recipes")
		return

	# Ext resources to add (after existing ones, before first sub_resource)
	needed_ext: list[tuple[str, str]] = []
	# bars
	for metal, slug in BAR_SLUG.items():
		path = f"res://source/common/gameplay/items/materials/metals/{slug}.tres"
		eid = f"bar_{metal}"
		if path not in text:
			needed_ext.append((eid, path))
	# gems + rings
	for family in FAMILIES:
		for qslug, _qlabel, metal, _price, _lvl, _xp in QUALITIES:
			gpath = f"res://source/common/gameplay/items/materials/gems/{gem_slug(family, qslug)}.tres"
			geid = f"g_{family}_{qslug}"
			needed_ext.append((geid, gpath))
			rslug = RING_SLUG[family].format(metal=metal)
			rpath = f"res://source/common/gameplay/items/gears/rings/{rslug}.tres"
			reid = f"r_{family}_{metal}"
			needed_ext.append((reid, rpath))

	ext_lines = []
	for eid, path in needed_ext:
		if f'id="{eid}"' in text or path in text and f'path="{path}"' in text:
			# may already exist under another id for bars
			continue
		ext_lines.append(f'[ext_resource type="Resource" path="{path}" id="{eid}"]')

	# Resolve actual ext ids for bars already on anvil
	def find_ext_id(path: str, preferred: str) -> str:
		m = re.search(rf'path="{re.escape(path)}" id="([^"]+)"', text)
		if m:
			return m.group(1)
		if preferred:
			return preferred
		raise RuntimeError(f"missing ext for {path}")

	# Insert new ext_resources before first [sub_resource]
	if ext_lines:
		# filter bars that already exist
		final_ext = []
		for eid, path in needed_ext:
			if re.search(rf'path="{re.escape(path)}"', text):
				continue
			final_ext.append(f'[ext_resource type="Resource" path="{path}" id="{eid}"]')
		if final_ext:
			idx = text.find("[sub_resource")
			text = text[:idx] + "\n".join(final_ext) + "\n\n" + text[idx:]

	# Re-resolve ids after insert
	def ext_id(path: str) -> str:
		m = re.search(rf'path="{re.escape(path)}" id="([^"]+)"', text)
		if not m:
			raise RuntimeError(f"no ext_resource for {path}")
		return m.group(1)

	sub_blocks: list[str] = []
	recipe_ids: list[str] = []
	for family in FAMILIES:
		for qslug, _qlabel, metal, _price, lvl, xp in QUALITIES:
			rslug = RING_SLUG[family].format(metal=metal)
			rid = f"R_ring_{family}_{metal}"
			recipe_ids.append(rid)
			ibar = f"I_{family}_{metal}_bar"
			igem = f"I_{family}_{metal}_gem"
			bar_path = f"res://source/common/gameplay/items/materials/metals/{BAR_SLUG[metal]}.tres"
			gem_path = f"res://source/common/gameplay/items/materials/gems/{gem_slug(family, qslug)}.tres"
			ring_path = f"res://source/common/gameplay/items/gears/rings/{rslug}.tres"
			sub_blocks.append(
				f'''[sub_resource type="Resource" id="{ibar}"]
script = ExtResource("3_ingred")
item = ExtResource("{ext_id(bar_path)}")
amount = 10

[sub_resource type="Resource" id="{igem}"]
script = ExtResource("3_ingred")
item = ExtResource("{ext_id(gem_path)}")

[sub_resource type="Resource" id="{rid}"]
script = ExtResource("1_recipe")
output_item = ExtResource("{ext_id(ring_path)}")
ingredients = Array[ExtResource("3_ingred")]([SubResource("{ibar}"), SubResource("{igem}")])
required_level = {lvl}
xp_reward = {xp}
'''
			)

	# Insert subresources before final [resource]
	res_idx = text.rfind("\n[resource]")
	if res_idx < 0:
		raise RuntimeError("anvil [resource] not found")
	text = text[:res_idx] + "\n" + "\n".join(sub_blocks) + text[res_idx:]

	# Append recipe ids to recipes array
	m = re.search(r"recipes = Array\[ExtResource\(\"1_recipe\"\)\]\(\[(.*)\]\)", text, re.S)
	if not m:
		raise RuntimeError("anvil recipes array not found")
	extra = ", ".join(f'SubResource("{rid}")' for rid in recipe_ids)
	old = m.group(0)
	# recipes line may be one long line
	inner = m.group(1).rstrip()
	if inner.endswith(","):
		new_inner = inner + " " + extra
	else:
		new_inner = inner + ", " + extra
	new = f'recipes = Array[ExtResource("1_recipe")]([{new_inner}])'
	text = text.replace(old, new, 1)

	write_text(ANVIL, text)


def update_items_index(new_paths: list[Path]) -> None:
	text = INDEX.read_text(encoding="utf-8")
	m = re.search(r"next_id = (\d+)", text)
	if not m:
		raise RuntimeError("next_id missing")
	next_id = int(m.group(1))

	# existing slugs
	existing = set(re.findall(r'&"slug": &"([^"]+)"', text))
	# also format with slug = 
	existing |= set(re.findall(r'"slug": &"([^"]+)"', text))
	existing |= set(re.findall(r"&\"slug\": &\"([^\"]+)\"", text))

	# Parse entries more reliably
	existing = set(re.findall(r'&"slug":\s*&"([^"]+)"', text))

	additions: list[str] = []
	for path in new_paths:
		slug = path.stem
		if slug in existing:
			# stamp id if missing on file
			item_text = path.read_text(encoding="utf-8")
			if "metadata/id" not in item_text:
				# find id from index
				em = re.search(
					rf'&"id":\s*(\d+),\s*\n&"path":\s*"{re.escape(str(path.as_posix()).replace(str(ROOT.as_posix()) + "/", "res://"))}"',
					text,
				)
			continue
		rel = "res://" + str(path.relative_to(ROOT)).replace("\\", "/")
		h = sha256_file(path)
		item_id = next_id
		next_id += 1
		additions.append(
			"{\n"
			f'&"hash": "{h}",\n'
			f'&"id": {item_id},\n'
			f'&"path": "{rel}",\n'
			f'&"slug": &"{slug}"\n'
			"}"
		)
		# stamp metadata on the item
		item_text = path.read_text(encoding="utf-8")
		if "metadata/id" not in item_text:
			if not item_text.endswith("\n"):
				item_text += "\n"
			item_text += f"metadata/id = {item_id}\n"
			# ensure slug line exists
			if "metadata/slug" not in item_text:
				item_text += f'metadata/slug = &"{slug}"\n'
			write_text(path, item_text)
		else:
			item_text = re.sub(r"metadata/id = \d+", f"metadata/id = {item_id}", item_text)
			write_text(path, item_text)
		print(f"index +{slug} id={item_id}")

	if not additions:
		print("index: nothing new")
		return

	# Recompute hashes after stamping ids
	final_adds: list[str] = []
	# rebuild from stamped files — parse ids we just assigned from files
	for path in new_paths:
		slug = path.stem
		if slug in existing:
			continue
		rel = "res://" + str(path.relative_to(ROOT)).replace("\\", "/")
		item_text = path.read_text(encoding="utf-8")
		id_m = re.search(r"metadata/id = (\d+)", item_text)
		if not id_m:
			continue
		h = sha256_file(path)
		final_adds.append(
			"{\n"
			f'&"hash": "{h}",\n'
			f'&"id": {int(id_m.group(1))},\n'
			f'&"path": "{rel}",\n'
			f'&"slug": &"{slug}"\n'
			"}"
		)

	# Insert before closing of entries array — find last `}]` pattern of entries
	text = re.sub(r"next_id = \d+", f"next_id = {next_id}", text, count=1)
	# entries = Array[Dictionary]([ ... ])
	insert_at = text.rfind("}])")
	if insert_at < 0:
		# maybe `}]` then newline then nothing — ContentIndex often ends with `}])`
		insert_at = text.rfind("}]")
		if insert_at < 0:
			raise RuntimeError("cannot find end of items_index entries")
		# insert before the last ]
		chunk = ", ".join(final_adds)
		text = text[:insert_at] + ", " + chunk + text[insert_at:]
	else:
		chunk = ", ".join(final_adds)
		text = text[:insert_at] + ", " + chunk + text[insert_at:]

	write_text(INDEX, text)
	print(f"items_index next_id={next_id} added={len(final_adds)}")


def place_npc_in_slayer_house() -> None:
	map_path = ROOT / "source/common/gameplay/maps/maps/slayer_house/inside_map.tscn"
	text = map_path.read_text(encoding="utf-8")
	if "ascension_broker_vael" in text or "SlayerQuartermaster" in text:
		print("slayer house already has quartermaster")
		return
	# add ext_resource + node near Turael
	ext = '[ext_resource type="Resource" uid="uid://cascensionbroker1" path="res://source/common/gameplay/characters/npc/npcs/ascension_broker_vael.tres" id="8_vael"]\n'
	if 'id="8_vael"' not in text:
		# after turael ext
		text = text.replace(
			'[ext_resource type="Resource" uid="uid://cjnx2h13qjtih" path="res://source/common/gameplay/characters/npc/npcs/turael.tres" id="6_turael"]\n',
			'[ext_resource type="Resource" uid="uid://cjnx2h13qjtih" path="res://source/common/gameplay/characters/npc/npcs/turael.tres" id="6_turael"]\n'
			+ ext,
		)
	node = '''
[node name="SlayerQuartermaster" parent="." instance=ExtResource("5_npc")]
position = Vector2(220, 220)
npc_resource = ExtResource("8_vael")
'''
	if "[node name=\"Turael\"" in text and "SlayerQuartermaster" not in text:
		# append after Turael node block
		text = text.rstrip() + "\n" + node
	write_text(map_path, text)


def main() -> None:
	paths: list[Path] = []
	paths.append(build_currency())
	paths.extend(build_gems())
	build_shop()
	patch_npc()
	ensure_anvil_ring_recipes()
	update_items_index(paths)
	place_npc_in_slayer_house()
	print("DONE")


if __name__ == "__main__":
	main()
