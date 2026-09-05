class_name NumberFormat
## The one place large numbers become display text. Every stack badge and every
## gold readout routes through [method format_stack_size] so a 7,402,340 purse
## reads the same in the bag, the bank, the market and the vendor.
##
## PRESENTATION ONLY. Nothing here rounds a number the game then acts on — the
## caller keeps the raw int and only ever assigns the returned strings to a
## Label. Abbreviating a value on its way INTO inventory, a price or a save
## would quietly destroy player wealth, so the utility deliberately returns a
## Dictionary of text and never a number.
##
## The abbreviation only kicks in at 100k. Below that the exact figure still
## fits a slot badge, and players read small counts as counts, not magnitudes.


## Below this, the exact comma-separated figure is shown.
const ABBREVIATE_FROM: int = 100_000
const THOUSAND: int = 1_000
const MILLION: int = 1_000_000

## Under 100k — the plain readout, so it sits quiet against the badge art.
const COLOR_DEFAULT: Color = Color.WHITE
## 100k .. 999,999.
const COLOR_THOUSANDS: Color = Color("#00FFFF")
## 1M and up.
const COLOR_MILLIONS: Color = Color("#FFD700")


## Display form of [param amount] for a stack badge or a currency readout.
##
## Returns [code]{"text", "color", "exact_text"}[/code]:
## [code]text[/code] is what the Label shows ("99,999", "150K", "7.4M"),
## [code]color[/code] the font_color override that grades it at a glance, and
## [code]exact_text[/code] the full comma-separated figure for the tooltip —
## a player pricing a trade needs the last coin, not the magnitude.
##
## Abbreviations TRUNCATE rather than round, so the shown figure never claims
## more than the player has: 999,999 reads "999K", never "1000K".
##
## A decimal is only carried where it earns its place, since the tooltip gives
## the exact figure away for free and a 36px badge charges a character to say
## it. Thousands never carry one - a ".9" on a K figure is worth about a
## thousand coins. Millions carry one only below 100M, because dropping it
## there would let "7M" stand for anything up to 7,999,999; past 100M the
## decimal is back under a percent, so "123M" it is. Every tier therefore lands
## at roughly the same relative precision, in at most five characters.
static func format_stack_size(amount: int) -> Dictionary:
	var exact: String = with_commas(amount)
	var magnitude: int = absi(amount)

	if magnitude < ABBREVIATE_FROM:
		return {"text": exact, "color": COLOR_DEFAULT, "exact_text": exact}

	var sign_prefix: String = "-" if amount < 0 else ""
	if magnitude < MILLION:
		@warning_ignore("integer_division")
		var thousands: int = magnitude / THOUSAND
		return {
			"text": "%s%dK" % [sign_prefix, thousands],
			"color": COLOR_THOUSANDS,
			"exact_text": exact,
		}

	return {
		"text": "%s%sM" % [sign_prefix, _tenths(magnitude, MILLION)],
		"color": COLOR_MILLIONS,
		"exact_text": exact,
	}


## 7402340 -> "7,402,340". Kept public: plain-text lines (toasts, chat, mail)
## want the exact figure without the colour and the abbreviation.
static func with_commas(amount: int) -> String:
	var digits: String = str(absi(amount))
	var out: String = ""
	var i: int = digits.length()
	while i > 0:
		var start: int = maxi(0, i - 3)
		if not out.is_empty():
			out = "," + out
		out = digits.substr(start, i - start) + out
		i = start
	return ("-" + out) if amount < 0 else out


## [param magnitude] over [param unit], truncated to one decimal. The zero is
## kept ("2.0M", not "2M") so every millions figure is the same width and the
## column of badges does not jitter as a stack grows.
##
## Once the whole part reaches three digits the decimal is dropped: it is worth
## under a percent by then, and "123.4M" is the one string that overflows the
## 36px inventory badge.
static func _tenths(magnitude: int, unit: int) -> String:
	@warning_ignore("integer_division")
	var whole: int = magnitude / unit
	if whole >= 100:
		return str(whole)
	@warning_ignore("integer_division")
	var tenths: int = (magnitude % unit) / (unit / 10)
	return "%d.%d" % [whole, tenths]
