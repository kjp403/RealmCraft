@tool
extends SceneTree
## Every gem and every gem-set ring must load, and no two may share art.
##
## This is the guard on tools/build_gem_icons.py and
## tools/build_gem_jewelry_icons.py. Both folders started out with items
## sharing one image between many slugs (43 gems on 15 images, 16 Slayer rings
## on 4), which is invisible in a diff and obvious in a bag.
##
##   godot --headless --path . -s tools/verify_gem_icons.gd

const DIRS: Array[String] = [
	"res://source/common/gameplay/items/materials/gems",
	"res://source/common/gameplay/items/gears/rings",
	"res://source/common/gameplay/items/gears/jewelry",
]


func _init() -> void:
	var seen: Dictionary = {}
	var bad: int = 0
	var n: int = 0
	for d: String in DIRS:
		var dir := DirAccess.open(d)
		if dir == null:
			printerr("cannot open ", d)
			bad += 1
			continue
		for f: String in dir.get_files():
			if not f.ends_with(".tres"):
				continue
			n += 1
			var item: Item = ResourceLoader.load(d + "/" + f) as Item
			if item == null:
				printerr("LOAD FAILED  ", f)
				bad += 1
				continue
			var tex: Texture2D = item.item_icon
			if tex == null:
				printerr("NULL ICON    ", f)
				bad += 1
				continue
			var img: Image = tex.get_image()
			if img == null or img.get_width() <= 0:
				printerr("BAD IMAGE    ", f)
				bad += 1
				continue
			var key: String = Marshalls.raw_to_base64(img.get_data().compress())
			if seen.has(key):
				printerr("DUPLICATE    ", f, " == ", seen[key])
				bad += 1
			else:
				seen[key] = f
	print("items loaded: %d   unique icons: %d   problems: %d" % [n, seen.size(), bad])
	quit(1 if bad else 0)
