extends SceneTree
## Export a coarse opacity mask per prop so the layout tool can place things
## against what is actually DRAWN, not against a bounding box. Boxes carry the
## sprites' transparent margins, which is how a palm ended up inside a hull
## while the box test said the two were clear of each other.
##   godot --headless --path . -s tools/dump_prop_masks.gd

const DIR: String = "res://assets/sprites/environment/sea/props"
const OUT: String = "res://previews/prop_masks.json"
## 4px cells: fine enough to tell a trunk from a gap, coarse enough to stay fast.
const CELL: int = 4


func _init() -> void:
	var masks: Dictionary = {}
	var dir: DirAccess = DirAccess.open(DIR)
	for file: String in dir.get_files():
		if not file.ends_with(".png"):
			continue
		var tex: Texture2D = load(DIR.path_join(file))
		if tex == null:
			continue
		var img: Image = tex.get_image()
		var cols: int = int(ceil(float(img.get_width()) / CELL))
		var rows: int = int(ceil(float(img.get_height()) / CELL))
		var bits: PackedByteArray = PackedByteArray()
		for cy: int in rows:
			for cx: int in cols:
				var solid: bool = false
				for y: int in range(cy * CELL, mini((cy + 1) * CELL, img.get_height())):
					for x: int in range(cx * CELL, mini((cx + 1) * CELL, img.get_width())):
						if img.get_pixel(x, y).a > 0.35:
							solid = true
							break
					if solid:
						break
				bits.append(1 if solid else 0)
		masks[file.get_basename()] = {
			"w": img.get_width(), "h": img.get_height(),
			"cols": cols, "rows": rows, "bits": Array(bits),
		}
	var f: FileAccess = FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(masks))
	f.close()
	print("wrote %d masks to %s" % [masks.size(), OUT])
	quit(0)
