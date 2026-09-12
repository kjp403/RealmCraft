class_name TitleVfxSettings
## The one client switch that title particle layers obey, and nothing else.
##
## A CLASS OF ITS OWN because both ends need it and neither may name the other.
## [TitleVfx] preloads [VipTitleEffect], so the effect naming TitleVfx back closes
## a load-time cycle between them - the same trap [VipTierProfile] documents, and
## the one that passes CI and then kills the world on a cold load. A leaf class
## that references nothing can be named from both sides safely.
##
## WHAT THE SWITCH IS FOR. Title text shaders are one material each and cost
## nothing worth measuring. The EMITTERS are the crowd problem: three layers per
## bought title, times however many people are standing in a hub. So this turns
## off the emitters and leaves every shader running - a player who turns it off
## still sees who is wearing what, in the right colours, just without the motes.

## Matches [WeatherLayer]'s pair, which is the precedent for "a whole VFX family a
## player may switch off for frame rate". Shipped default lives in
## data/config/client_default_settings.cfg and is ON.
const SECTION: StringName = &"general"
const PROPERTY: StringName = &"title_particles"

## The settings autoload, once found. Static: this is asked on every title mount
## and on every wearer's LOD tick.
static var _host: Node = null


## True when title particle layers may run.
##
## Fails OPEN wherever there is nothing to ask - the headless server, a tools/
## render, the first frames of a boot - because rendering nothing there would be
## the bug, and because every one of those cases is either measuring the effect or
## not drawing at all.
##
## LOOKED UP BY PATH rather than by naming the ClientState autoload. This file is
## reachable from headless `-s` verifiers, which start no autoloads, and an
## autoload identifier that cannot resolve in one is a parse error that takes the
## whole class down with it - silently, while the game itself keeps working.
static func enabled() -> bool:
	if not is_instance_valid(_host):
		var loop: SceneTree = Engine.get_main_loop() as SceneTree
		if loop == null or loop.root == null:
			return true
		_host = loop.root.get_node_or_null(^"ClientState")
		if _host == null:
			return true
	var settings: Variant = _host.get(&"settings")
	if settings == null:
		return true
	var saved: Variant = settings.get_value(SECTION, PROPERTY)
	return true if saved == null else bool(saved)
