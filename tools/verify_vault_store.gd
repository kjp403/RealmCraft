extends Node
## Regression gate for the Vault store UI - what a buyer sees, and what they can
## click. Drives the REAL vault_menu.tscn inside a z_index 100 host (the way
## hud.gd hosts every menu) with the REAL catalog prices.
##
## Scene mode, not `-s`: the menus reach client autoloads, which `-s` does not
## register, and a `-s` run that cannot compile them exits 0 having checked nothing.
##   godot --headless --path . --mode=client res://tools/verify_vault_store.tscn
##
## NO SERVER. The responses a live server sends are handed to the same handlers
## the network would call. What the server itself refuses (equipping unowned,
## buying owned, double purchases) is guarded server-side and is not re-tested
## here - this is the client half: never offering the wrong thing.

const MENU_SCENE: String = "res://source/client/ui/menus/vault/vault_menu.tscn"
const STANDALONE_SCENES: Array[String] = [
	"res://source/client/ui/menus/titles/titles_menu.tscn",
	"res://source/client/ui/menus/skins/skins_menu.tscn",
	"res://source/client/ui/menus/cosmetics/cosmetics_menu.tscn",
]
const W: int = 960
const H: int = 540

var _pass: int = 0
var _fail: int = 0
var _host: Control
var _menu: Control
var _panels: Dictionary


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var wearer: LocalPlayer = LocalPlayer.new()
	wearer.skin_id = PlayerSkins.starter_skin_id()
	ClientState.local_player = wearer

	_host = Control.new()
	_host.z_index = 100
	_host.size = Vector2(W, H)
	add_child(_host)
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	_host.add_child(_menu)
	_menu.position = Vector2.ZERO
	_menu.size = Vector2(W, H)
	await _frames(2)
	_panels = _menu.get(&"_panels")

	var rows: Array = []
	for entry: Dictionary in PremiumCatalog.roster():
		var row: Dictionary = entry.duplicate()
		row["owned"] = false
		rows.append(row)
	_menu.call(&"_on_catalog", {"ok": true, "purchasable": true, "items": rows})
	_menu.call(&"_on_balance", {"ok": true, "balance": 5000})

	await _check_hidden_tabs_cannot_steal_selection()
	await _check_cosmetic_shelf()
	await _check_purchase_unlocks_equip()
	await _check_take_off_needs_something_worn()
	await _check_try_on()
	await _check_pet_renders_inside_viewport()
	await _check_titles()
	await _check_skins_dyes()
	await _check_buy_follows_tab()
	await _check_processing_lock()
	await _check_standalone_menus()

	ClientState.local_player = null
	print("%d passed, %d failed" % [_pass, _fail])
	print("VERIFY_PASS" if _fail == 0 else "VERIFY_FAIL")
	get_tree().quit(0 if _fail == 0 else 1)


# --- Checks ------------------------------------------------------------------

## State for every tab arrives on open, visible or not. Only the tab on screen may
## decide what Buy is pricing - otherwise a buyer looking at an aura can be
## charged for a title on a tab they are not even looking at.
func _check_hidden_tabs_cannot_steal_selection() -> void:
	print("a hidden tab cannot change what Buy is pricing")
	var auras: Array[int] = _sellable(&"aura")
	_menu.call(&"_select_tab", &"cosmetics")
	var cos: Control = _panels[&"cosmetics"]
	cos.call(&"_on_state", _cosmetic_state([auras[0], auras[1]], {"aura": auras[0]}))
	await _frames(1)
	var want: String = VaultGrants.cosmetic_token(int(cos.call(&"_current_id")))
	_ck(_selected() == want, "Buy targets the visible tab's item")
	(_panels[&"titles"] as Control).call(&"_on_state", _title_state([], ""))
	(_panels[&"skins"] as Control).call(&"_on_state", {"ok": true, "allowed": false, "owned": [], "equipped": 0})
	(_panels[&"pets"] as Control).call(&"_on_state", _cosmetic_state([], {}))
	await _frames(1)
	_ck(_selected() == want, "hidden tabs' state leaves it alone (now '%s')" % _selected())


func _check_cosmetic_shelf() -> void:
	print("the cosmetics shelf lists, tags and prices correctly")
	var auras: Array[int] = _sellable(&"aura")
	var cos: Control = _panels[&"cosmetics"]
	_menu.call(&"_select_tab", &"cosmetics")
	cos.call(&"_on_state", _cosmetic_state([auras[0], auras[1]], {"aura": auras[0]}))
	await _frames(1)
	var shelf: Control = cos.get(&"_shelf")
	var ids: Array = cos.call(&"_current_ids")
	_ck(int(shelf.call(&"row_count")) == ids.size(), "every aura on the shelf has a row (%d)" % ids.size())
	var i_worn: int = ids.find(auras[0])
	var i_owned: int = ids.find(auras[1])
	var i_buy: int = ids.find(auras[2])
	var cost: int = _cost(VaultGrants.cosmetic_token(auras[2]))
	_ck(_tag(shelf, i_worn) == "Equipped", "the worn aura says Equipped")
	_ck(_tag(shelf, i_owned) == "Owned", "an owned aura says Owned")
	_ck(_tag(shelf, i_buy) == str(cost) and _coin(shelf, i_buy), "an unowned aura shows its price (%d)" % cost)

	var buy: Button = _menu.get(&"_buy_button")
	var action: Button = cos.get(&"_action_button")
	shelf.emit_signal(&"picked", i_buy)
	await _frames(1)
	_ck(_selected() == VaultGrants.cosmetic_token(auras[2]), "clicking a row points Buy at it")
	_ck((cos.get(&"_name_label") as Label).text == Cosmetics.display_name(auras[2]), "the preview names the clicked aura")
	_ck(_only_pressed(shelf, i_buy), "only the clicked row is highlighted")
	_ck(buy.visible and not buy.disabled and buy.text.contains(str(cost)), "Buy is offered at the catalog price")
	_ck(action.disabled, "Equip is locked on an aura not owned")

	shelf.emit_signal(&"picked", i_owned)
	await _frames(1)
	_ck(not buy.visible, "no Buy on an aura already owned")
	_ck(not action.disabled and action.text == "Equip", "Equip is live on an owned aura")

	shelf.emit_signal(&"picked", i_worn)
	await _frames(1)
	_ck(not buy.visible, "no Buy on the worn aura")
	_ck(action.disabled and action.text == "Equipped", "the worn aura reads Equipped")


## After paying, the buyer's next click is Equip. It must work without reopening
## the Vault, on the item they just bought.
func _check_purchase_unlocks_equip() -> void:
	print("buying unlocks Equip in place")
	var auras: Array[int] = _sellable(&"aura")
	var cos: Control = _panels[&"cosmetics"]
	_menu.call(&"_select_tab", &"cosmetics")
	var shelf: Control = cos.get(&"_shelf")
	var ids: Array = cos.call(&"_current_ids")
	var i_buy: int = ids.find(auras[2])
	shelf.emit_signal(&"picked", i_buy)
	await _frames(1)
	var token: String = VaultGrants.cosmetic_token(auras[2])
	_menu.call(&"_on_purchased", {"ok": true, "item_id": token, "label": "x", "balance": 4000})
	# refresh_after_purchase starts a state fetch; there is no server here, so the
	# answer it would get is handed over by hand - including the hidden tabs'.
	cos.call(&"_on_state", _cosmetic_state([auras[0], auras[1], auras[2]], {"aura": auras[0]}))
	(_panels[&"pets"] as Control).call(&"_on_state", _cosmetic_state([auras[2]], {}))
	(_panels[&"titles"] as Control).call(&"_on_state", _title_state([], ""))
	await _frames(1)
	var action: Button = cos.get(&"_action_button")
	var buy: Button = _menu.get(&"_buy_button")
	_ck(cos.get(&"_slot") == &"aura" and int(cos.call(&"_current_id")) == auras[2], "the bought aura stays selected")
	_ck(_selected() == token, "Buy still targets it, not a hidden tab's item")
	_ck(not action.disabled and action.text == "Equip", "Equip unlocks straight away")
	_ck(not buy.visible, "Buy disappears once owned")
	_ck(_tag(shelf, i_buy) == "Owned", "its row now says Owned")


func _check_take_off_needs_something_worn() -> void:
	print("Take off is only live when something is worn")
	var cos: Control = _panels[&"cosmetics"]
	var clear: Button = cos.get(&"_clear_button")
	cos.call(&"_select_slot", &"aura")
	await _frames(1)
	_ck(not clear.disabled, "Take off is live on a tab with something worn")
	var empty_slot: StringName = &""
	for slot: StringName in cos.get(&"_slots"):
		if int(cos.call(&"_equipped_for", slot)) == 0:
			empty_slot = slot
			break
	if empty_slot != &"":
		cos.call(&"_select_slot", empty_slot)
		await _frames(1)
		_ck(clear.disabled, "Take off is locked on %s, where nothing is worn" % empty_slot)
		cos.call(&"_select_slot", &"aura")


func _check_try_on() -> void:
	print("the mannequin only draws what belongs on this tab, and Reset takes the rest off")
	var cos: Control = _panels[&"cosmetics"]
	_menu.call(&"_select_tab", &"cosmetics")
	cos.call(&"_select_slot", &"aura")
	await _frames(1)
	var bar: Control = cos.get(&"_try_on_bar")
	var reset: Button = cos.get(&"_try_on_reset")
	_ck(bar != null and reset != null, "the try-on bar exists")
	if bar == null or reset == null:
		return

	# Start clean: earlier checks browsed other tabs, and browsing tries things on.
	cos.call(&"_reset_other_try_ons")
	await _frames(1)
	_ck(not bar.visible, "Reset clears try-ons left over from other tabs")

	# Browse an unowned aura: that alone must not raise the bar - it is on screen.
	var auras: Array[int] = _sellable(&"aura")
	var ids: Array = cos.call(&"_current_ids")
	var shelf: Control = cos.get(&"_shelf")
	var unowned: int = auras[auras.size() - 1]
	shelf.emit_signal(&"picked", ids.find(unowned))
	await _frames(1)
	_ck(not bar.visible, "browsing an unowned aura does not flag a try-on")

	var try_on: Dictionary = cos.get(&"_try_on")
	var weapons: Array[int] = Cosmetics.ids_in_slot(&"weapon")
	var flourishes: Array[int] = Cosmetics.ids_in_slot(&"flourish")
	if not weapons.is_empty():
		try_on[&"weapon"] = weapons[0]
	if not flourishes.is_empty():
		try_on[&"flourish"] = flourishes[0]
	cos.call(&"_render_outfit")
	var vfx: Dictionary = cos.get(&"_preview_vfx")
	_ck((vfx[&"aura"] as CosmeticVfx).visible, "the aura being browsed draws")
	_ck(not (vfx[&"weapon"] as CosmeticVfx).visible, "a weapon skin never draws on the Auras tab")
	_ck(not (vfx[&"flourish"] as CosmeticVfx).visible, "a flourish never loops on the Auras tab")
	_ck(not bar.visible, "try-ons that do not draw here are not flagged")

	# The weapon skin is previewed on a real Ascended weapon, never as a strip.
	var weapon_preview: Sprite2D = cos.get(&"_weapon_preview")
	_ck(weapon_preview != null and not weapon_preview.visible, "no showcase weapon on the Auras tab")
	if not weapons.is_empty() and (cos.get(&"_slots") as Array).has(&"weapon"):
		cos.call(&"_select_slot", &"weapon")
		await _frames(1)
		var glow: WeaponVfx = cos.get(&"_weapon_glow")
		_ck(not (vfx[&"weapon"] as CosmeticVfx).visible, "the raw weapon strip never draws, even on its own tab")
		_ck(weapon_preview.visible, "the Weapon Skins tab shows the showcase Ascended weapon")
		_ck(glow.visible and glow.sprite_frames != null, "with the glow the world would mount on it")
		cos.call(&"_select_slot", &"aura")
		cos.call(&"_reset_other_try_ons")
		await _frames(1)
		_ck(not weapon_preview.visible, "and it goes away on the Auras tab")
		shelf.emit_signal(&"picked", ids.find(unowned))
		await _frames(1)

	var trails: Array[int] = _sellable(&"trail")
	if trails.is_empty():
		return
	try_on[&"trail"] = trails[0]
	cos.call(&"_render_outfit")
	_ck(bar.is_visible_in_tree(), "a trail tried on another tab is flagged")
	_ck(
		(cos.get(&"_try_on_label") as Label).text.contains("%s trail" % Cosmetics.display_name(trails[0])),
		"the bar names it, with its slot"
	)
	reset.emit_signal(&"pressed")
	await _frames(1)
	_ck(
		int(try_on.get(&"trail", 0)) == int(cos.call(&"_equipped_for", &"trail")) and not bar.visible,
		"Reset takes it back off"
	)
	_ck(int(try_on.get(&"aura", 0)) == unowned, "Reset keeps the aura being browsed on")
	_ck(_selected() == VaultGrants.cosmetic_token(unowned), "Reset leaves Buy on the selected row")


func _check_pet_renders_inside_viewport() -> void:
	print("a pet renders in the preview, not under the z-100 menu")
	var pets: Control = _panels[&"pets"]
	_menu.call(&"_select_tab", &"pets")
	pets.call(&"_on_state", _cosmetic_state([], {}))
	await _frames(3)
	var vfx: CosmeticVfx = (pets.get(&"_preview_vfx") as Dictionary)[&"pet"]
	var companion: CompanionPreset = vfx.companion()
	_ck(companion != null, "the browsed pet mounts a companion")
	if companion != null:
		_ck(
			companion.body.get_viewport() == pets.get(&"_preview_viewport"),
			"its top_level body lives inside the preview viewport"
		)


func _check_titles() -> void:
	print("titles shelf")
	var titles: Control = _panels[&"titles"]
	_menu.call(&"_select_tab", &"titles")
	var state: Dictionary = _title_state([], "")
	titles.call(&"_on_state", state)
	await _frames(1)
	var roster: Array = state["titles"]
	_ck(not roster.is_empty(), "there are titles for sale (%d)" % roster.size())
	var shelf: Control = titles.get(&"_shelf")
	_ck(int(shelf.call(&"row_count")) == roster.size(), "every title has a row")
	var name0: String = str((roster[0] as Dictionary).get("name", ""))
	var cost: int = _cost(VaultGrants.title_token(name0))
	_ck(_tag(shelf, 0) == str(cost), "the first title shows its price")
	_ck(_selected() == VaultGrants.title_token(name0), "Buy targets the selected title")
	_ck((titles.get(&"_action_button") as Button).disabled, "Wear is locked on a title not owned")
	_ck((titles.get(&"_clear_button") as Button).disabled, "Take off is locked with no title worn")
	titles.call(&"_on_state", _title_state([name0.to_lower()], name0))
	await _frames(1)
	_ck(not (_menu.get(&"_buy_button") as Button).visible, "no Buy on a title already owned")
	_ck(_tag(shelf, 0) == "Equipped", "the worn title says Equipped")
	_ck(not (titles.get(&"_clear_button") as Button).disabled, "Take off is live with a title worn")


func _check_skins_dyes() -> void:
	print("skins: bodies listed, dyes re-price the shelf")
	var skins: Control = _panels[&"skins"]
	_menu.call(&"_select_tab", &"skins")
	skins.call(&"_on_state", {"ok": true, "allowed": false, "owned": [], "equipped": 0})
	await _frames(1)
	var swatches: Array = skins.get(&"_swatches")
	_ck(swatches.size() == VaultSkins.dye_roster().size(), "every dye has a swatch (%d)" % swatches.size())
	skins.call(&"_on_dye_picked", 1)
	await _frames(1)
	var packed: int = int(skins.call(&"_packed"))
	_ck(_selected() == VaultGrants.skin_token(packed), "a dye click points Buy at that body in that dye")
	_ck((swatches[1] as Button).button_pressed and not (swatches[0] as Button).button_pressed, "only the picked swatch is highlighted")
	var shelf: Control = skins.get(&"_shelf")
	var expected: int = _cost(VaultGrants.skin_token(int(skins.call(&"_packed_for", 0))))
	_ck(_tag(shelf, 0) == str(expected), "the shelf is priced for the picked dye")
	skins.call(&"_on_state", {"ok": true, "allowed": false, "owned": [packed], "equipped": 0})
	await _frames(1)
	_ck(not (_menu.get(&"_buy_button") as Button).visible, "no Buy on a pairing already owned")
	_ck(not (skins.get(&"_action_button") as Button).disabled, "Wear is live on an owned pairing")
	_ck((skins.get(&"_clear_button") as Button).disabled, "Take off is locked with no skin worn")


func _check_buy_follows_tab() -> void:
	print("Buy sits above the buttons of whichever tab is open")
	var order: Array[StringName] = [&"titles", &"skins", &"cosmetics", &"pets"]
	var buy: Button = _menu.get(&"_buy_button")
	for round_i: int in 3:
		for tab: StringName in order:
			_menu.call(&"_select_tab", tab)
	await _frames(1)
	for tab: StringName in order:
		_menu.call(&"_select_tab", tab)
		await _frames(1)
		var panel: Control = _panels[tab]
		var detail: Control = panel.get(&"_detail")
		var row: Control = panel.get(&"_action_row")
		_ck(
			buy.get_parent() == detail and buy.get_index() == row.get_index() - 1,
			"%s: Buy is directly above its action row" % tab
		)


func _check_processing_lock() -> void:
	print("a purchase in flight cannot be started twice")
	var buy: Button = _menu.get(&"_buy_button")
	_menu.set(&"_processing", true)
	_menu.call(&"_update_buy")
	_ck(buy.visible and buy.disabled and buy.text == "Processing...", "Buy locks while a purchase settles")
	_menu.call(&"_on_purchased", {"ok": false, "reason": "insufficient_funds", "item_id": ""})
	_ck(not bool(_menu.get(&"_processing")), "a failed settle releases the lock")


func _check_standalone_menus() -> void:
	print("the Curator's standalone menus still build")
	for path: String in STANDALONE_SCENES:
		var menu: Control = (load(path) as PackedScene).instantiate()
		_host.add_child(menu)
		menu.size = Vector2(W, H)
		await _frames(2)
		_ck(menu.get(&"content") != null and menu.get(&"_detail") != null, "%s builds its shell and layout" % path.get_file())
		menu.queue_free()
	await _frames(1)


# --- Helpers -----------------------------------------------------------------

func _selected() -> String:
	return str(_menu.get(&"_selected"))


func _cost(token: String) -> int:
	return int((_menu.call(&"catalog_entry", token) as Dictionary).get("cost", 0))


## Ids in [param slot] the catalog sells, in shelf order.
func _sellable(slot: StringName) -> Array[int]:
	var out: Array[int] = []
	for id: int in Cosmetics.ids_in_slot(slot):
		if _cost(VaultGrants.cosmetic_token(id)) > 0:
			out.append(id)
	return out


## What cosmetics.state sends a non-staff player: for sale, plus owned.
func _cosmetic_state(owned: Array, slots: Dictionary) -> Dictionary:
	var visible: Array = []
	for id: int in Cosmetics.ids():
		if owned.has(id) or _cost(VaultGrants.cosmetic_token(id)) > 0:
			visible.append(id)
	return {"ok": true, "allowed": false, "owned": owned, "cosmetics": visible, "slots": slots}


## What titles.state sends a non-staff player: only what the till sells.
func _title_state(owned: Array, equipped: String) -> Dictionary:
	var rows: Array = []
	for row_v: Variant in TitleCatalog.vault_roster():
		var title: String = str((row_v as Dictionary).get("name", ""))
		if _cost(VaultGrants.title_token(title)) > 0:
			rows.append(row_v)
	return {"ok": true, "allowed": false, "owned": owned, "titles": rows, "equipped": equipped}


func _tag(shelf: Control, index: int) -> String:
	var tags: Array = shelf.get(&"_tags")
	if index < 0 or index >= tags.size():
		return "<no row %d>" % index
	var label: Label = tags[index]
	return label.text if label.visible else ""


func _coin(shelf: Control, index: int) -> bool:
	var coins: Array = shelf.get(&"_coins")
	return index >= 0 and index < coins.size() and (coins[index] as TextureRect).visible


func _only_pressed(shelf: Control, index: int) -> bool:
	var rows: Array = shelf.get(&"_rows")
	for i: int in rows.size():
		if (rows[i] as Button).button_pressed != (i == index):
			return false
	return true


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _ck(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
		print("  ok    %s" % label)
	else:
		_fail += 1
		printerr("  FAIL  %s" % label)
