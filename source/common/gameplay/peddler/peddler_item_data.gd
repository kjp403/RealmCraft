class_name PeddlerItemData
extends Resource
## ONE row in the Traveling Peddler's stock: what it is, what tier it rolls in,
## and what it costs. Authored as a .tres under [code]peddler/stock/[/code], the
## same way a shop authors its catalog, so adding a thirteenth good is a data
## edit and not a code change.
##
## [member id] is load-bearing twice over. It is the daily-roll key the client
## and server both index on, AND it is the ITEM REGISTRY SLUG of the real bag
## item the purchase grants — [code]peddler_vault_key[/code] here is
## [code]peddler_vault_key.tres[/code] in the items registry. Keeping them the
## same string is what lets [PeddlerCatalog] resolve a stock row to a grantable
## item without a second mapping table to fall out of sync (the shop-key
## collision class of bug, see [method NPCResource.giver_key]).
##
## That holds for [member brokered] rows too — the id of the row that sells the
## Grand Steel Chest is [code]gold_steel_grand[/code], the chest's own slug — so
## nothing about resolving or capping a purchase has to know the difference.
##
## Prices are quoted from here for DISPLAY only. Every gold check and deduction
## happens server-side in [code]peddler.buy[/code] against this same resource, so
## a client that edits its copy just gets refused.

## Tier names. Strings, not an enum ordinal, so a reordered enum can never
## silently repaint the whole catalog (same reasoning as [LootRarity.NAMES]).
const TIER_S: String = "S"
const TIER_A: String = "A"
const TIER_B: String = "B"
## Roll order — one item is drawn from each, in this order, every day.
const TIERS: PackedStringArray = [TIER_S, TIER_A, TIER_B]

## Fallback swatch colours, by tier. Only used when [member icon] is null.
const TIER_COLORS: Dictionary[String, Color] = {
	TIER_S: Color(1.0, 0.84, 0.25),  # gold
	TIER_A: Color(0.66, 0.42, 0.95), # purple
	TIER_B: Color(0.35, 0.62, 1.0),  # blue
}

## Edge of the generated fallback icon: a near-black outer ring under a
## near-white inner ring. Two rings rather than one because the swatch has to
## read against BOTH the dark bag grid and the parchment shop card — a single
## border colour disappears into one or the other.
const FALLBACK_SIZE: int = 16
const FALLBACK_OUTER: Color = Color(0.05, 0.04, 0.03, 1.0)
const FALLBACK_INNER: Color = Color(0.97, 0.96, 0.92, 1.0)

## Generated swatches, keyed by tier. Built at most once per tier per process —
## every bag slot and stock row asks for one, so this must not allocate an Image
## per draw.
static var _fallback_cache: Dictionary[String, Texture2D] = {}

## Stock key AND the registry slug of the item this grants. See the class note.
@export var id: String = ""
## Shop-row title.
@export var item_name: String = ""
## Shop-row body copy.
@export_multiline var description: String = ""
## Price in gold. Charged server-side; this copy is for display.
@export var price_gold: int = 0
## Which daily bucket this rolls in: [constant TIER_S] / [constant TIER_A] /
## [constant TIER_B].
@export var tier: String = TIER_B
## Shop-row art. Null is FINE — [method resolved_icon] generates a tier swatch,
## so an unfinished good never blanks a slot or crashes the row builder.
@export var icon: Texture2D
## True when this row sells something that ALREADY EXISTS in the game — a boss
## chest, say — rather than a Peddler-exclusive [PeddlerGoodItem].
##
## The Peddler is a broker for these, not their author. It changes three things:
##   - no PeddlerGoodItem is written for it (the item is already authored),
##   - it keeps whatever use pipeline its own class has (a LootChestItem opens
##     through UniversalChestManager / chest.open_item, NOT through peddler.use),
##   - it stays as tradeable as it already was. Making a boss drop untradeable
##     because the Peddler also sells it would retroactively freeze every copy
##     already in players' hands.
##
## The daily one-per-account cap still applies: it is keyed on the STOCK id, so
## it limits how many you can buy, which is the only thing the Peddler controls.
@export var brokered: bool = false
## Optional [PeddlerAction] subclass run server-side when the good is used.
## Null = this good has no use action yet (it is stock the player owns, not a
## consumable), and [code]peddler.use[/code] refuses it by name.
@export var action_script: Script


## Icon for this row: the authored art, or a generated tier swatch when there
## is none. NEVER returns null — the UI is built to assume that.
func resolved_icon() -> Texture2D:
	if icon != null:
		return icon
	return fallback_icon(tier)


## The accent colour for [param tier_name], falling back to the B-tier blue for
## an unknown tier rather than to black (which would read as "no tier" and is
## invisible on the bag grid).
static func tier_color(tier_name: String) -> Color:
	return TIER_COLORS.get(tier_name, TIER_COLORS[TIER_B])


## A [constant FALLBACK_SIZE]-square swatch in [param tier_name]'s colour with a
## two-tone border. Cached per tier.
static func fallback_icon(tier_name: String) -> Texture2D:
	var key: String = tier_name if TIER_COLORS.has(tier_name) else TIER_B
	if _fallback_cache.has(key):
		return _fallback_cache[key]
	var image: Image = Image.create_empty(
		FALLBACK_SIZE, FALLBACK_SIZE, false, Image.FORMAT_RGBA8
	)
	image.fill(tier_color(key))
	var last: int = FALLBACK_SIZE - 1
	for i: int in FALLBACK_SIZE:
		# Outer ring (row/column 0 and last).
		image.set_pixel(i, 0, FALLBACK_OUTER)
		image.set_pixel(i, last, FALLBACK_OUTER)
		image.set_pixel(0, i, FALLBACK_OUTER)
		image.set_pixel(last, i, FALLBACK_OUTER)
	for i: int in range(1, last):
		# Inner ring, inset one pixel.
		image.set_pixel(i, 1, FALLBACK_INNER)
		image.set_pixel(i, last - 1, FALLBACK_INNER)
		image.set_pixel(1, i, FALLBACK_INNER)
		image.set_pixel(last - 1, i, FALLBACK_INNER)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_fallback_cache[key] = texture
	return texture


## True when this row is authored well enough to sell. A row missing its id or
## priced at zero is a half-finished edit, and the roll skips it rather than
## offering the player a free nameless item.
func is_sellable() -> bool:
	return not id.is_empty() and not item_name.is_empty() and price_gold > 0
