class_name PrayerBook
## Single source of truth for which prayers exist, in book order. Adding a
## prayer is a content change: drop a `<slug>.tres` under `prayer/prayers/` and
## add one line here.
##
## `static var` (not `const`) for the same reason [JobRegistry] uses one:
## preload() expressions cannot initialise a typed `const` with class-shaped
## values in GDScript 4.
##
## Prayers are addressed by SLUG everywhere — over the wire, in the active set,
## in the UI — never by index, so reordering this list is safe and inserting a
## prayer in the middle cannot silently re-point a player's active prayers.

const PRAYER_DIR: String = "res://source/common/gameplay/prayer/prayers/"

static var PRAYERS: Array[PrayerResource] = [
	# --- Defence --------------------------------------------------------------
	preload("res://source/common/gameplay/prayer/prayers/earthen_ward.tres"),
	preload("res://source/common/gameplay/prayer/prayers/ironheart.tres"),
	preload("res://source/common/gameplay/prayer/prayers/bulwark_mountain.tres"),

	# --- Offence --------------------------------------------------------------
	preload("res://source/common/gameplay/prayer/prayers/hawk_talon.tres"),
	preload("res://source/common/gameplay/prayer/prayers/wolf_rage.tres"),
	preload("res://source/common/gameplay/prayer/prayers/bear_might.tres"),
	preload("res://source/common/gameplay/prayer/prayers/blood_tithe.tres"),
	preload("res://source/common/gameplay/prayer/prayers/mind_seer.tres"),
	preload("res://source/common/gameplay/prayer/prayers/oath_slayer.tres"),

	# --- Protection -----------------------------------------------------------
	preload("res://source/common/gameplay/prayer/prayers/ward_blades.tres"),
	preload("res://source/common/gameplay/prayer/prayers/ward_arcane.tres"),

	# --- Gathering ------------------------------------------------------------
	preload("res://source/common/gameplay/prayer/prayers/gatherer_haste.tres"),
	preload("res://source/common/gameplay/prayer/prayers/prosperity.tres"),
	preload("res://source/common/gameplay/prayer/prayers/wisdom_light.tres"),
]

static var _by_slug: Dictionary[StringName, PrayerResource] = {}


## The prayer with [param slug], or null when unknown. An unknown slug is the
## normal case for a client sending stale data, so callers must handle null
## rather than trusting it.
static func by_slug(slug: StringName) -> PrayerResource:
	if _by_slug.is_empty():
		for prayer: PrayerResource in PRAYERS:
			if prayer != null and not prayer.slug.is_empty():
				_by_slug[prayer.slug] = prayer
	return _by_slug.get(slug, null)


## Every prayer unlocked at [param level], in book order.
static func unlocked_at(level: int) -> Array[PrayerResource]:
	var out: Array[PrayerResource] = []
	for prayer: PrayerResource in PRAYERS:
		if prayer != null and prayer.required_level <= level:
			out.append(prayer)
	return out
