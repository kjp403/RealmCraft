extends Node
## Remove every cliff run in the east wing that fences nothing.
##
## A wall is worth keeping if it does a job: it bounds the map, or it encloses
## ground so the player has to go around. Anything else is a snake of cliff
## dropped across open field. Components are found with an 8-way flood fill,
## then tested: does removing this component change what is reachable from the
## outside? If not, it is decoration pretending to be terrain.
##   godot --path . --mode=client res://tools/strip_pointless_walls.tscn

const MAP: String = "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"
const EAST_FROM: int = 60
const LAYERS: Array[String] = ["Walls", "WallDecor"]


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var root: Node = (load(MAP) as PackedScene).instantiate()
	var walls: TileMapLayer = root.get_node("Walls") as TileMapLayer
	var decor: TileMapLayer = root.get_node_or_null("WallDecor") as TileMapLayer
	var rect: Rect2i = (root.get_node("Ground") as TileMapLayer).get_used_rect()

	var wall_cells: Dictionary = {}
	for cell: Vector2i in walls.get_used_cells():
		if cell.x >= EAST_FROM:
			wall_cells[cell] = true

	# Components, 8-way so diagonal cliff runs count as one piece.
	var seen: Dictionary = {}
	var components: Array = []
	for cell: Vector2i in wall_cells:
		if seen.has(cell):
			continue
		var stack: Array = [cell]
		var comp: Array = []
		seen[cell] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			comp.append(c)
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					var n: Vector2i = c + Vector2i(dx, dy)
					if wall_cells.has(n) and not seen.has(n):
						seen[n] = true
						stack.append(n)
		components.append(comp)
	print("wall components east of x%d: %d" % [EAST_FROM, components.size()])

	# Which ground is reachable from outside the map, walking around walls.
	var reachable: Dictionary = _flood(wall_cells, rect)
	var removed: int = 0
	var kept_boundary: int = 0
	var kept_enclosing: int = 0
	for comp: Array in components:
		var touches_edge: bool = false
		for c: Vector2i in comp:
			if c.x <= rect.position.x or c.x >= rect.end.x - 1 \
					or c.y <= rect.position.y or c.y >= rect.end.y - 1:
				touches_edge = true
				break
		var bb := Rect2i(comp[0], Vector2i.ONE)
		for c: Vector2i in comp:
			bb = bb.expand(c)
		if touches_edge:
			# These two run the length of the wing and only touch the border by
			# accident; keeping the whole component kept a field of ribbons. Keep
			# the part that IS the border, drop the rest.
			kept_boundary += 1
			var trimmed: int = 0
			for c: Vector2i in comp:
				var edge_dist: int = mini(
					mini(c.x - rect.position.x, rect.end.x - 1 - c.x),
					mini(c.y - rect.position.y, rect.end.y - 1 - c.y)
				)
				if edge_dist > 3:
					walls.erase_cell(c)
					if decor != null:
						decor.erase_cell(c)
					removed += 1
					trimmed += 1
			print("  TRIM edge   %4d cells, dropped %d away from the border"
				% [comp.size(), trimmed])
			continue
		# Does it shut anything off? Any neighbouring ground the outside flood
		# could not reach means this component is a real barrier.
		var encloses: bool = false
		for c: Vector2i in comp:
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					var n: Vector2i = c + Vector2i(dx, dy)
					if wall_cells.has(n) or not rect.has_point(n):
						continue
					if not reachable.has(n):
						encloses = true
						break
				if encloses:
					break
			if encloses:
				break
		# Even the "enclosing" runs are squiggles fencing a patch of empty grass
		# rather than gating anything, so they go as well. Only the map border
		# survives; say the word if any of these were meant to block a route.
		if encloses:
			kept_enclosing += 1
			print("  DROP encl   %4d cells  bbox %s" % [comp.size(), bb])
		for c: Vector2i in comp:
			walls.erase_cell(c)
			if decor != null:
				decor.erase_cell(c)
			removed += 1
	print("kept %d boundary runs, %d enclosing runs; removed %d cells"
		% [kept_boundary, kept_enclosing, removed])

	# Component-level keeps are too coarse: one snake that happens to reach the
	# map edge kept a whole field of dead-end cliff. Erode open ends instead —
	# a wall cell with one or no wall neighbour is the tip of a run that fences
	# nothing. Repeat until only closed loops and real barriers remain.
	var live: Dictionary = {}
	for cell: Vector2i in walls.get_used_cells():
		if cell.x >= EAST_FROM:
			live[cell] = true
	var pruned: int = 0
	var pass_count: int = 0
	while pass_count < 200:
		pass_count += 1
		var ends: Array = []
		for cell: Vector2i in live:
			# Map border cliffs stay: they are the edge of the world.
			if cell.x <= rect.position.x + 1 or cell.x >= rect.end.x - 2 					or cell.y <= rect.position.y + 1 or cell.y >= rect.end.y - 2:
				continue
			var n: int = 0
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					if live.has(cell + Vector2i(dx, dy)):
						n += 1
			if n <= 1:
				ends.append(cell)
		if ends.is_empty():
			break
		for cell: Vector2i in ends:
			live.erase(cell)
			walls.erase_cell(cell)
			if decor != null:
				decor.erase_cell(cell)
			pruned += 1
	print("eroded %d dead-end wall cells over %d passes" % [pruned, pass_count])

	var packed := PackedScene.new()
	packed.pack(root)
	print("saved: ", ResourceSaver.save(packed, MAP) == OK)
	get_tree().quit(0)


## Cells reachable from the map border without crossing a wall.
func _flood(wall_cells: Dictionary, rect: Rect2i) -> Dictionary:
	var out: Dictionary = {}
	var stack: Array = []
	for x: int in range(rect.position.x, rect.end.x):
		for y: Array in [[x, rect.position.y], [x, rect.end.y - 1]]:
			var c := Vector2i(y[0], y[1])
			if not wall_cells.has(c):
				stack.append(c)
	for y: int in range(rect.position.y, rect.end.y):
		for x: Array in [[rect.position.x, y], [rect.end.x - 1, y]]:
			var c := Vector2i(x[0], x[1])
			if not wall_cells.has(c):
				stack.append(c)
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		if out.has(c) or wall_cells.has(c) or not rect.has_point(c):
			continue
		out[c] = true
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			stack.append(c + d)
	return out
