class_name RemoteBankInteraction
extends NPCInteraction
## NPC capability: open the personal bank for a gold fee (courier / bank runner).
## Selecting the option fires [code]bank.remote_open[/code]; on success the client
## opens the bank menu. Free bankers use [BankInteraction] instead.

## Gold fee to open the vault remotely. Single source of truth for UI + handler.
const COST: int = 5000


func menu_entry(_npc: Node) -> Dictionary:
	return {
		"label": _label_or("Bank for %sG" % _fmt_cost(COST)),
		"icon": _icon_or(""),
		"request": &"bank.remote_open",
		"args": {},
		"open_menu": &"bank",
	}


static func _fmt_cost(amount: int) -> String:
	var s: String = str(amount)
	var out: String = ""
	var i: int = s.length()
	while i > 0:
		var start: int = maxi(0, i - 3)
		if not out.is_empty():
			out = "," + out
		out = s.substr(start, i - start) + out
		i = start
	return out
