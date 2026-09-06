extends Node
## Global HUD edit mode + the store of player-chosen HUD sizes (client only).
##
##   HudLayout.toggle()                     — what the L key calls
##   HudLayout.locked                       — true = playing, false = editing
##   HudLayout.lock_changed                 — every HudResizer listens
##   HudLayout.size_for(key)                — persisted size, or Vector2.ZERO
##   HudLayout.store_size(key, size)        — called once, on drag RELEASE
##
## WHY AN AUTOLOAD AND NOT A STATIC CLASS
## The state is global (one lock for the whole HUD) but the listeners are not:
## resizers come and go with the panels they belong to, and several of those
## panels are built at runtime rather than authored in hud.tscn. A signal on a
## node they can all reach is the cheapest way for a panel created halfway
## through a session to pick up the current mode.
##
## THIS NODE DOES NOT READ INPUT. The L key is caught in Hud._unhandled_input
## next to M and I, because that is where every other HUD keybind already lives
## and it inherits the behaviour those depend on: a focused LineEdit consumes
## printable keys before unhandled input ever runs, so typing "look out" in chat
## cannot toggle edit mode. An _input handler here would sit AHEAD of the chat
## box and would have to re-derive that guard itself.
##
## Unlike Toaster and LootFeed this node does NOT queue_free itself off the
## client. It holds no per-frame cost and never touches the tree, and keeping it
## alive means HudResizer.attach() stays safe to call from the render tools in
## tools/, which run with a client GameMode but are not the game.

signal lock_changed(locked: bool)
## Every HudResizer reverts its host to the size the SCENE authored. Clearing the
## stored sizes is not enough on its own: by the time a reset happens those sizes
## have already been written onto the panels (as custom_minimum_size or as anchor
## offsets), so without this the settings button would wipe the save file and
## leave the HUD looking exactly as the player left it.
signal layout_reset

const SETTING_SECTION: StringName = &"hud_layout"
## Persisted lock state lives under the same section as the sizes, so a "reset
## HUD layout" is one section wipe.
const SETTING_LOCKED: StringName = &"locked"

## Locked is the DEFAULT and the safe state: handles hidden, every resizer
## mouse-transparent, nothing between the player and the world.
var locked: bool = true


func _ready() -> void:
	# Settings are loaded by ClientState._ready; this autoload is registered
	# after it, so the value is already on disk-backed data by the time we read.
	var saved: Variant = ClientState.settings.get_value(SETTING_SECTION, SETTING_LOCKED)
	locked = bool(saved) if saved != null else true


func toggle() -> void:
	set_locked(not locked)


func set_locked(value: bool) -> void:
	if locked == value:
		return
	locked = value
	ClientState.settings.set_value(SETTING_SECTION, SETTING_LOCKED, locked)
	lock_changed.emit(locked)


## The player's stored size for [param key], or ZERO when they have never
## resized that panel — callers must treat ZERO as "keep your authored size"
## rather than as a size, or every panel collapses on a fresh install.
func size_for(key: StringName) -> Vector2:
	var saved: Variant = ClientState.settings.get_value(SETTING_SECTION, key)
	return saved if saved is Vector2 else Vector2.ZERO


## Persist one panel's size.
##
## CALL THIS ON DRAG RELEASE, NEVER DURING THE DRAG. ClientState.Settings.set_value
## calls save() on every single call, which rewrites user://client_settings.cfg —
## doing that per mouse-motion event would put a file write in the drag loop.
func store_size(key: StringName, size: Vector2) -> void:
	ClientState.settings.set_value(SETTING_SECTION, key, size)


## Drop every stored size, put the panels back to their authored geometry, and
## re-lock. The Settings dictionary is the live store, so clearing the section and
## saving persists it; [signal layout_reset] is what the panels on screen react to.
func reset() -> void:
	var data: Dictionary = ClientState.settings.data
	if data.has(SETTING_SECTION):
		data[SETTING_SECTION] = {}
	ClientState.settings.save()
	layout_reset.emit()
	locked = true
	lock_changed.emit(locked)
