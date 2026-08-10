class_name SlayerMasterRegistry
## Single source of truth for which Slayer masters exist — the Slayer-skill mirror
## of JobRegistry. Adding a master is a **content** change: drop a `<name>.tres`
## under slayer/masters/ and add one line here (plus an NPCResource + SlayerInteraction
## somewhere in the world that points at it).
##
## `static var` (not `const`) for the same reason JobRegistry uses it: preload()
## results can't initialize a typed const Dictionary with class-shaped values in
## GDScript 4.

static var MASTERS: Dictionary[StringName, SlayerMasterResource] = {
	&"turael": preload("res://source/common/gameplay/slayer/masters/turael.tres"),
	&"durael": preload("res://source/common/gameplay/slayer/masters/durael.tres"),
}


static func has_master(master_slug: StringName) -> bool:
	return MASTERS.has(master_slug)


static func master_for(master_slug: StringName) -> SlayerMasterResource:
	return MASTERS.get(master_slug, null)
