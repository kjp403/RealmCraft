class_name PeddlerCatalog
## Every good the Traveling Peddler can ever stock, loaded from
## [code]peddler/stock/[/code] and bucketed by tier.
##
## Scanned from disk rather than listed in code so the stock list has ONE home
## (the .tres files), and sorted by [member PeddlerItemData.id] so the bucket
## order is identical on every machine. That ordering is not cosmetic: the daily
## roll indexes into these arrays, so a catalog that enumerated in directory
## order would hand two servers different stock from the same date hash.

const STOCK_DIR: String = "res://source/common/gameplay/peddler/stock/"

## tier -> Array[PeddlerItemData], each sorted by id. Empty until _scan().
static var _by_tier: Dictionary[String, Array] = {}
## id -> PeddlerItemData, for resolving a purchase back to its row.
static var _by_id: Dictionary[String, PeddlerItemData] = {}
static var _scanned: bool = false


## The sellable rows in [param tier], id-sorted. Never null.
static func tier_pool(tier: String) -> Array:
	_scan()
	return _by_tier.get(tier, [])


## One row by its id, or null. This is the only sanctioned way to turn a
## client-supplied id into a priced good — never trust a price off the wire.
static func find(id: String) -> PeddlerItemData:
	_scan()
	return _by_id.get(id, null)


## Every sellable row, id-sorted across all tiers. For tooling and verification.
static func all() -> Array:
	_scan()
	var out: Array = []
	for tier: String in PeddlerItemData.TIERS:
		out.append_array(tier_pool(tier))
	return out


## Force a re-scan. Only for tools that write stock .tres files and then want to
## read them back in the same process.
static func reload() -> void:
	_scanned = false
	_by_tier.clear()
	_by_id.clear()
	_scan()


static func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	for tier: String in PeddlerItemData.TIERS:
		_by_tier[tier] = []
	for file_name: String in ResourceLoader.list_directory(STOCK_DIR):
		if not file_name.ends_with(".tres"):
			continue
		# Load UNTYPED and check, for the reason ContentRegistryHub does: a typed
		# assignment throws on any stray file here, and the throw would abort the
		# scan — leaving the Peddler with a partial catalog and no error a player
		# could act on.
		var loaded: Resource = ResourceLoader.load(STOCK_DIR + file_name)
		var row: PeddlerItemData = loaded as PeddlerItemData
		if row == null:
			push_error("PeddlerCatalog: %s is not a PeddlerItemData — skipping." % file_name)
			continue
		if not row.is_sellable():
			push_error("PeddlerCatalog: %s is missing id/name/price — skipping." % file_name)
			continue
		if not _by_tier.has(row.tier):
			push_error("PeddlerCatalog: %s has unknown tier '%s' — skipping." % [
				file_name, row.tier
			])
			continue
		if _by_id.has(row.id):
			push_error("PeddlerCatalog: duplicate stock id '%s' — skipping %s." % [
				row.id, file_name
			])
			continue
		_by_id[row.id] = row
		(_by_tier[row.tier] as Array).append(row)
	for tier: String in _by_tier:
		(_by_tier[tier] as Array).sort_custom(
			func(a: PeddlerItemData, b: PeddlerItemData) -> bool: return a.id < b.id
		)
