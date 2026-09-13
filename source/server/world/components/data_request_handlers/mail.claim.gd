extends DataRequestHandler
## Claims one mail's reward attachments for the requesting character. Reuses the
## redeem grant pipeline: validate → apply → mark claimed. The claimed guard
## (SQL-level) stops double-claims, including one-claim-per-player on broadcasts.
## Returns {"ok": true, "rewards": [...]} or {"ok": false, "reason": ...}.
## See docs/mailbox.md.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var pr: PlayerResource = instance.world_server.connected_players.get(peer_id, null)
	if pr == null:
		return {"ok": false, "reason": "no_player"}
	var mail_id: int = int(args.get("mail_id", 0))
	if mail_id <= 0:
		return {"ok": false, "reason": "missing"}

	var store: MailStore = instance.world_server.database.mail_store
	var claimable: Dictionary = store.get_claimable(pr.player_id, mail_id)
	if not bool(claimable.get("ok", false)):
		return {"ok": false, "reason": str(claimable.get("reason", "missing"))}

	var attachments: Array = claimable.get("attachments", [])
	if not RedeemCodes.validate_grants(attachments):
		ServerLog.error("Mail #%d has invalid attachments; refusing to claim." % mail_id)
		return {"ok": false, "reason": "invalid"}

	# "to_bank": items fill the vault first and spill into the bag. The bag-only
	# path tops out at ~90 slots of 10-stacks, so a large market buy was
	# unclaimable no matter how empty the bag was.
	var to_bank: bool = bool(args.get("to_bank", false))

	# Space is checked BEFORE anything is consumed: apply_grants adds items
	# uncapped, and a market purchase claimed into a full bag has to stay in the
	# mailbox rather than quietly overflow it. Nothing is mutated on this path.
	if to_bank:
		if not RedeemCodes.grants_fit_bank(pr, attachments):
			return {"ok": false, "reason": "bank_full"}
	elif not RedeemCodes.grants_fit(pr, attachments):
		return {"ok": false, "reason": "inventory_full"}

	var result: Dictionary = {"ok": true}
	if to_bank:
		var placed: Dictionary = RedeemCodes.apply_grants_bank(pr, attachments)
		result["rewards"] = placed["rewards"]
		result["banked"] = placed["banked"]
		result["bagged"] = placed["bagged"]
	else:
		result["rewards"] = RedeemCodes.apply_grants(pr, attachments)
	store.mark_claimed(pr.player_id, mail_id)
	# Persist immediately. Waiting for the periodic save would leave a window where
	# the mail reads "claimed" in SQLite while the gold/items live only in memory —
	# a crash there would eat a market payout outright.
	instance.world_server.database.save_player(pr)
	ServerLog.info("Player #%d (%s) claimed mail #%d%s." % [
		pr.player_id, pr.display_name, mail_id, " to bank" if to_bank else ""
	])
	return result
