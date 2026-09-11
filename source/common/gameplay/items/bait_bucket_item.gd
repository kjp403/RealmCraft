class_name BaitBucketItem
extends AnglerToolItem
## The Bottomless Bait Bucket. Right-click Fill sweeps every loose Fish Bait stack
## out of the bags and into the bucket in one server call — no panel, because there
## is nothing to choose.
##
## THE BUCKET HOLDS NO STATE OF ITS OWN. The charge lives on
## [member PlayerResource.stored_bait] and is only ever touched through
## [BaitBucket]. An @export here would be shared by every player on the server,
## because item resources are loaded once and handed out by reference — see the
## note on BaitBucket for the full reasoning and for the second, independent way
## per-slot storage loses it.


func action_label() -> String:
	return "Fill"


func server_request() -> StringName:
	return &"bait.fill"


## Hover / detail lines: what is actually IN the bucket, and what that buys.
##
## The bucket is the one bag item whose whole value is a number you cannot see —
## it never stacks, its icon never changes, and the bait it swallowed left the
## bags. Without these lines the only way to learn the count was to right-click
## Fill and read the toast, which is a destructive way to ask a question.
##
## Read off [ClientState], never `player_resource`: the charge lives on
## PlayerResource, which is assigned on the world server only and is null on
## every client, so reading it here would print 0 for everyone. [GameMode] gates
## the whole block because this script is common/ — the server parses it too, and
## ClientState frees itself outside the client.
func stat_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	# "charges" is the muted ink ItemTooltip already uses for a count that is
	# neither a stat nor a gate, which is exactly what this is.
	lines.append({
		"kind": &"charges",
		"text": "Baited casts: +%d%% Fishing XP per catch, up to +%d%%" % [
			roundi(FishingComboManager.STEP * 100.0),
			roundi((FishingComboManager.MAX_MULTIPLIER - 1.0) * 100.0),
		],
	})
	if not GameMode.is_client() or not ClientState.has_bait_bucket:
		return lines
	var capacity: int = ClientState.bait_capacity
	if capacity <= 0:
		capacity = BaitBucket.MAX_STORED
	lines.insert(0, {
		"kind": &"charges",
		"text": "Bait stored: %s / %s" % [
			NumberFormat.with_commas(ClientState.stored_bait),
			NumberFormat.with_commas(capacity),
		],
	})
	return lines
