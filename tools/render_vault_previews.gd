extends Node
## Screenshot the REAL Vault store — all three tabs, with the Ark Coin balance and
## live prices — at the shipping 960x540 client size.
##
## Runs as a SCENE, not a `-s` tool, and windowed (headless has no rasteriser):
##   godot --path . --mode=client res://tools/render_vault_previews.tscn
##
## The scene route is not a style choice: `-s` starts a bare SceneTree with no
## autoloads, and vault_menu.gd references Client and InstanceClient — under `-s`
## they fail to COMPILE, so there is nothing to screenshot. `--mode=client` keeps
## the Client autoload alive instead of self-freeing.
##
## NO SERVER, SO THE DATA IS INJECTED. Every panel fetches its own state on show
## and gives up when InstanceClient.current is null, which is exactly what happens
## here — so the responses a live server would have sent are handed straight to
## the same handlers. The prices are the REAL catalog, not mock numbers: this is
## a picture of what the store actually charges.

const MENU_SCENE: String = "res://source/client/ui/menus/vault/vault_menu.tscn"
const OUT_DIR: String = "res://previews"

## The project's base viewport. Captured here and upscaled after, so what you see
## is the layout the client produces rather than a roomier canvas that hides
## clipping.
const W: int = 960
const H: int = 540
const UPSCALE: int = 2

## A balance that can afford some things and not others, so the Buy button shows
## both of its enabled states across the three tabs.
const DEMO_BALANCE: int = 1750

var _sv: SubViewport
var _menu: Control
var _out_abs: String


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	_out_abs = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(_out_abs)

	_sv = SubViewport.new()
	_sv.size = Vector2i(W, H)
	_sv.transparent_bg = false
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sv)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0.04, 0.05, 0.07)
	backdrop.size = Vector2(W, H)
	_sv.add_child(backdrop)

	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sv.add_child(_menu)
	await get_tree().process_frame
	await get_tree().process_frame

	_fake_wearer()
	_feed_panels()
	_feed_shell()

	for tab: Array in [
		[&"titles", "vault_titles"],
		[&"skins", "vault_skins"],
		[&"cosmetics", "vault_cosmetics"],
	]:
		_menu.call(&"_select_tab", tab[0])
		# The tab re-announces its selection on show, which is what re-prices the
		# Buy button. Two frames: one for the panel to lay out, one for the shell
		# to react to the selection it emitted.
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_shoot(str(tab[1]))

	# One more, on the FLOURISH tab. The two event slots are the ones a buyer
	# cannot judge from the art - a flourish and a departure look identical in a
	# wardrobe, and differ entirely in when they fire - so the line that says
	# when it plays is the thing worth having a picture of.
	var cosmetics_panel: Control = (_menu.get(&"_panels") as Dictionary).get(&"cosmetics")
	if cosmetics_panel != null:
		_menu.call(&"_select_tab", &"cosmetics")
		cosmetics_panel.call(&"_select_slot", &"flourish")
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_shoot("vault_flourish")

	# And the try-on stack: an aura and a halo already worn, a trail being
	# browsed over the top.
	if cosmetics_panel != null:
		cosmetics_panel.call(&"_select_slot", &"trail")
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_shoot("vault_combo")

	print("done -> ", _out_abs)
	get_tree().quit()


## A stand-in local player, so the Cosmetics tab draws a body under the effect
## and a title over it.
##
## The wardrobe reads the wearer off [member ClientState.local_player] - that is
## the whole point of the preview, an aura shown on the skin and dye the buyer is
## actually wearing - and there is no world here to spawn one. Without this the
## panel falls back to the starter body with no title, which is a true picture of
## the fallback and a poor one of the feature.
##
## DELIBERATELY LEFT OUT OF THE TREE, and it logs one error for it: skin_id's
## setter refreshes the body visual, which asks `multiplayer` whether this is the
## server, and that is null outside a tree - so the run prints "Cannot call
## method 'is_server' on a null value" and carries on. The assignment itself
## lands before the refresh, which is all the wardrobe reads.
##
## PARENTING IT IS WORSE, not better: a LocalPlayer in a tree starts running its
## real _process against a camera, a state machine and a stat block that do not
## exist here, and the run fills with a dozen null errors instead of one.
func _fake_wearer() -> void:
	var wearer: LocalPlayer = LocalPlayer.new()
	wearer.skin_id = PlayerSkins.starter_skin_id()
	wearer.vault_skin_id = 0
	wearer.display_title = "Emberwake"
	ClientState.local_player = wearer


## Hand each panel the state a live server would have sent. Called directly
## rather than faked through Client, so the panels run their real handlers.
func _feed_panels() -> void:
	var panels: Dictionary = _menu.get(&"_panels")

	var titles: Control = panels.get(&"titles")
	if titles != null:
		titles.call(&"_on_state", {
			"ok": true,
			"allowed": true,
			"titles": TitleCatalog.vault_roster(),
			"equipped": "",
		})

	var skins: Control = panels.get(&"skins")
	if skins != null:
		skins.call(&"_on_state", {"ok": true, "allowed": true, "equipped": 0})

	var cosmetics: Control = panels.get(&"cosmetics")
	if cosmetics != null:
		# Dressed in an aura and a halo already, so the Trails tab shows what the
		# wardrobe is actually for now: a COMBINATION, with the browsed trail on
		# top of what is already worn.
		cosmetics.call(&"_on_state", {
			"ok": true,
			"allowed": true,
			"cosmetics": Cosmetics.ids(),
			"equipped": 0,
			"equipped_weapon": 0,
			"slots": {
				"aura": _first_in_slot(&"aura"),
				"halo": _first_in_slot(&"halo"),
			},
		})


## The shell's own two fetches: the catalog (prices + ownership) and the balance.
## The roster is the REAL one, so every price in the screenshot is the shipping
## price.
func _feed_shell() -> void:
	var rows: Array = []
	for entry: Dictionary in PremiumCatalog.roster():
		var row: Dictionary = entry.duplicate()
		row["owned"] = false
		rows.append(row)
	_menu.call(&"_on_catalog", {"ok": true, "purchasable": true, "items": rows})
	_menu.call(&"_on_balance", {"ok": true, "balance": DEMO_BALANCE})


func _shoot(name: String) -> void:
	var img: Image = _sv.get_texture().get_image()
	# NEAREST, because everything in frame is pixel art and a smooth upscale
	# would misrepresent how the UI actually looks.
	img.resize(W * UPSCALE, H * UPSCALE, Image.INTERPOLATE_NEAREST)
	var path: String = "%s/%s.png" % [_out_abs, name]
	img.save_png(path)
	print("  wrote ", path)


## The lowest id in [param slot], for dressing the stand-in. Lowest rather than
## random so two runs of this tool produce comparable pictures.
func _first_in_slot(slot: StringName) -> int:
	for id: int in Cosmetics.ids():
		if Cosmetics.slot_of(id) == slot:
			return id
	return 0
