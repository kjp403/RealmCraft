class_name StackMerge
## Client helper: ask the server to combine two stacks, then the caller refreshes.


static func try_merge(from_uid: int, to_uid: int, in_bank: bool = false) -> int:
	if (
		InstanceClient.current == null
		or from_uid < 0
		or to_uid < 0
		or from_uid == to_uid
	):
		return 0
	var result: Array = await Client.request_data_await(
		&"item.merge",
		{"from_uid": from_uid, "to_uid": to_uid, "in_bank": in_bank},
		InstanceClient.current.name
	)
	if result.size() < 2 or result[1] != OK or result[0] is not Dictionary:
		return 0
	var payload: Dictionary = result[0]
	if not bool(payload.get("ok", false)):
		return 0
	return int(payload.get("moved", 0))
