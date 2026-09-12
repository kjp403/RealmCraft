class_name TitleThemeFx
## The emitter stack for each of the eight colour-matched shop titles, built from
## [CosmeticThemes] rather than authored as a .tres.
##
## WHY NOT A .tres, when the donation ladder's four profiles are exactly that: a
## .tres holds literal colours. These eight take theirs from the DYE TABLE, which
## is the entire point of the set - the title, the aura and the body dye are the
## same hex, and a file holding its own copy of that hex is a copy that drifts.
## So the shape of each look is written here as code and the colour is looked up.
##
## What that costs is inspector tuning: a designer cannot drag a slider on
## "Crimson Warlord" the way they can on "Diamond Donator". That is the deliberate
## trade - the ladder is four looks tuned against each other by hand and retuned
## as a set, these eight are one recipe applied in eight colours, and the second
## kind is better served by a function than by eight files to keep in sync.
##
## Everything else is shared with the ladder: the emitter data is a
## [VipParticleLayer], the runtime is [VipTitleEffect], and the budget, span clamp
## and LOD are that class's. See its header for why bought titles need an LOD at
## all when the earned ones do not.
##
## EVERY ONE OF THE EIGHT HAS A TRAIL, and no two trails are the same effect in a
## different colour. That is a product rule, not a preference: the trail is what
## the rest of the server sees, because a title is read from BEHIND a running
## player far more often than it is read head-on in a bank. A set whose eight
## trails were one shape in eight tints would look like one purchase with a colour
## picker.
##
## So each trail differs in SHAPE, in BLEND and in which way it goes, and
## tools/verify_cosmetic_themes.gd fails the build if two of them collapse onto
## the same combination:
##
##   Crimson    cinders raining down and cooling to ash            DOT      matte
##   Arcane     sigil sparks hanging in the air where you walked   DIAMOND  light
##   Glacial    frost settling and shrinking away                  SHARD    light
##   Verdant    leaves kicked up and tumbling backwards            LEAF     matte
##   Storm      sparks skittering off in bursts                    PIP      light
##   Lotus      blossom drifting down and across                   LEAF     matte
##   Solar      gold dust hanging and fading                       SPARKLE  light
##   Prism      a ribbon of every dye in the vault                 PIP      light
##
## WORLD SPACE IS WHAT MAKES IT A TRAIL. [VipTitleEffect] leaves particles where
## they were born, so a layer emitting from a walking nameplate is left behind by
## it. A trail layer that ever sets [member VipParticleLayer.local_space] would be
## bolted to the label and would follow the wearer around as a cloud instead.

## Profile per theme, built on first ask. Static so thirty players wearing the
## same title in a bank share one build rather than one each - the same argument
## [VipTierProfile]'s cache makes.
static var _cache: Dictionary = {}


## The profile for [param theme], or null when it is not one of the eight.
static func profile(theme: StringName) -> VipTierProfile:
	if not CosmeticThemes.has(theme):
		return null
	if _cache.has(theme):
		return _cache[theme]
	var built: VipTierProfile = _build(theme)
	_cache[theme] = built
	return built


static func _build(theme: StringName) -> VipTierProfile:
	var p: VipTierProfile = VipTierProfile.new()
	p.tier = theme
	p.display_name = CosmeticThemes.label(theme)
	p.accent = CosmeticThemes.core(theme)
	# The metal group is untouched on purpose: these titles are painted by
	# theme_title.gdshader, which is not the ladder's cast-metal shader and reads
	# none of those uniforms. Only `layers` and `ray_color` are live here.
	match theme:
		CosmeticThemes.CRIMSON:
			p.layers = _crimson(theme)
		CosmeticThemes.ARCANE:
			p.layers = _arcane(theme)
		CosmeticThemes.GLACIAL:
			p.layers = _glacial(theme)
		CosmeticThemes.VERDANT:
			p.layers = _verdant(theme)
		CosmeticThemes.STORM:
			p.layers = _storm(theme)
		CosmeticThemes.LOTUS:
			p.layers = _lotus(theme)
		CosmeticThemes.SOLAR:
			p.layers = _solar(theme)
			# The sunburst. A fan of drawn triangles rather than particles,
			# because a ray is a long shape anchored at one point and a row of
			# sprites reads as streaks - see VipTitleEffect._paint_rays. Alpha
			# here is the fan's peak opacity, and it is the one thing in the set
			# that draws BEHIND the letters.
			p.ray_color = Color(CosmeticThemes.pale(theme), 0.30)
		CosmeticThemes.PRISM:
			p.layers = _prism(theme)
	return p


## CRIMSON WARLORD - embers up off the letters, cinders down behind the heels.
static func _crimson(theme: StringName) -> Array[VipParticleLayer]:
	var embers: VipParticleLayer = _layer(&"embers", VipParticleLayer.Shape.DOT, 5)
	embers.span = VipParticleLayer.Span.BOTTOM
	embers.span_scale = 1.15
	embers.amount = 14
	embers.lifetime = 1.1
	embers.direction = Vector2(0.0, -1.0)
	embers.spread = 24.0
	embers.gravity = Vector2(0.0, -14.0)
	embers.velocity_min = 8.0
	embers.velocity_max = 22.0
	embers.damping = 6.0
	embers.scale_min = 0.25
	embers.scale_max = 0.7
	embers.scale_start = 1.0
	embers.scale_end = 0.2
	_ramp(embers, CosmeticThemes.pale(theme), CosmeticThemes.accent(theme),
		CosmeticThemes.core(theme), 0.85)

	# THE TRAIL: cinders raining off the name and cooling to ash on the way down.
	#
	# NOT ADDITIVE, and that is the one thing in this layer that is not taste.
	# Half its ramp is ash - a dark colour - and additive blending of a dark colour
	# adds nothing at all, so the layer would tick, cost frame time and draw
	# literally no pixels for the second half of every particle's life.
	# Six pixels rather than five, and bigger on screen than any other trail in the
	# set: a cinder is the only one of the eight that is warm paint on a dark floor
	# rather than light ADDED to it, so it has to win its contrast with area.
	var cinders: VipParticleLayer = _layer(&"cinders", VipParticleLayer.Shape.DOT, 6)
	cinders.span = VipParticleLayer.Span.BOTTOM
	cinders.span_scale = 1.2
	cinders.amount = 20
	cinders.lifetime = 1.3
	cinders.direction = Vector2(0.0, 1.0)
	cinders.spread = 35.0
	cinders.gravity = Vector2(0.0, 22.0)
	cinders.velocity_min = 3.0
	cinders.velocity_max = 12.0
	cinders.scale_min = 0.5
	cinders.scale_max = 1.15
	cinders.scale_start = 1.0
	cinders.scale_end = 0.5
	cinders.additive = false
	cinders.on_move = true
	# FOUR STOPS, so the cinder stays LIT for most of its fall and only goes to
	# ash at the very end. The three-stop version spent the whole second half of
	# every particle's life walking toward `deep`, which is dark paint on a dark
	# floor - the trail was there, ticking and costing frame time, and could not
	# be seen. Ash is the last beat of the effect, not the bulk of it.
	cinders.color_in = CosmeticThemes.pale(theme)
	cinders.color_mid = CosmeticThemes.accent(theme)
	cinders.late_stop = 0.72
	cinders.color_late = CosmeticThemes.core(theme)
	cinders.color_out = CosmeticThemes.deep(theme)
	cinders.peak_alpha = 1.0
	return [embers, cinders] as Array[VipParticleLayer]


## ARCANE MAGUS - gold sigils turning around the name, over a violet haze.
static func _arcane(theme: StringName) -> Array[VipParticleLayer]:
	var sigils: VipParticleLayer = _layer(&"sigils", VipParticleLayer.Shape.DIAMOND, 7)
	sigils.span = VipParticleLayer.Span.BOX
	sigils.span_scale = 1.25
	sigils.amount = 9
	sigils.lifetime = 1.4
	sigils.velocity_min = 0.0
	sigils.velocity_max = 2.0
	# The whole look. Local space so the ring travels WITH the wearer instead of
	# being left behind as a circle drawn where they were standing.
	sigils.orbit = 0.14
	sigils.local_space = true
	sigils.angular_velocity = 40.0
	sigils.scale_min = 0.5
	sigils.scale_max = 1.0
	_ramp(sigils, CosmeticThemes.accent(theme), CosmeticThemes.accent(theme),
		CosmeticThemes.pale(theme), 0.9)

	var haze: VipParticleLayer = _layer(&"haze", VipParticleLayer.Shape.DOT, 9)
	haze.span = VipParticleLayer.Span.BOX
	haze.amount = 10
	haze.lifetime = 1.3
	haze.direction = Vector2(0.0, -1.0)
	haze.spread = 60.0
	haze.velocity_min = 3.0
	haze.velocity_max = 12.0
	haze.scale_min = 0.3
	haze.scale_max = 0.8
	haze.detail = true
	_ramp(haze, CosmeticThemes.core(theme), CosmeticThemes.core(theme),
		CosmeticThemes.pale(theme), 0.55)

	# THE TRAIL: sigil sparks shed off the ring and left HANGING where they were
	# shed. Almost no velocity and no gravity, so in world space each one simply
	# stays put while the wearer walks out from under it - a line of slowly
	# turning marks down the path behind them, which is the one trail in the set
	# that writes on the world instead of falling out of the air.
	var runewake: VipParticleLayer = _layer(&"runewake", VipParticleLayer.Shape.DIAMOND, 6)
	runewake.span = VipParticleLayer.Span.BOTTOM
	runewake.span_scale = 1.1
	runewake.amount = 16
	runewake.lifetime = 1.4
	runewake.direction = Vector2(0.0, -1.0)
	runewake.spread = 20.0
	runewake.velocity_min = 0.0
	runewake.velocity_max = 3.0
	runewake.damping = 8.0
	runewake.angular_velocity = 90.0
	runewake.scale_min = 0.35
	runewake.scale_max = 0.8
	runewake.scale_start = 1.0
	runewake.scale_end = 0.3
	runewake.on_move = true
	_ramp(runewake, CosmeticThemes.accent(theme), CosmeticThemes.accent(theme),
		CosmeticThemes.core(theme), 0.85)
	return [sigils, haze, runewake] as Array[VipParticleLayer]


## GLACIAL SOVEREIGN - snow falling through the title, frost lifting off it.
static func _glacial(theme: StringName) -> Array[VipParticleLayer]:
	var snow: VipParticleLayer = _layer(&"snow", VipParticleLayer.Shape.PIP, 4)
	snow.span = VipParticleLayer.Span.TOP
	snow.span_scale = 1.3
	snow.amount = 18
	snow.lifetime = 1.4
	snow.direction = Vector2(0.0, 1.0)
	snow.spread = 18.0
	snow.gravity = Vector2(2.0, 16.0)
	snow.velocity_min = 4.0
	snow.velocity_max = 11.0
	snow.scale_min = 0.3
	snow.scale_max = 0.7
	_ramp(snow, CosmeticThemes.pale(theme), CosmeticThemes.pale(theme),
		CosmeticThemes.accent(theme), 0.8)

	var crystals: VipParticleLayer = _layer(&"crystals", VipParticleLayer.Shape.SHARD, 9)
	crystals.span = VipParticleLayer.Span.ENDS
	crystals.amount = 8
	crystals.lifetime = 1.2
	crystals.direction = Vector2(0.0, -1.0)
	crystals.spread = 30.0
	crystals.velocity_min = 4.0
	crystals.velocity_max = 14.0
	crystals.damping = 8.0
	crystals.angular_velocity = 60.0
	crystals.scale_min = 0.35
	crystals.scale_max = 0.8
	crystals.detail = true
	_ramp(crystals, CosmeticThemes.accent(theme), CosmeticThemes.accent(theme),
		CosmeticThemes.pale(theme), 0.75)

	# THE TRAIL: frost thrown off the name as it goes, settling and shrinking away
	# to nothing. The scale curve is what separates it from the snow above - snow
	# falls at a constant size, frost sublimates - so the two never read as one
	# layer at two speeds even though both are cold and both go downward.
	var frostwake: VipParticleLayer = _layer(&"frostwake", VipParticleLayer.Shape.SHARD, 5)
	frostwake.span = VipParticleLayer.Span.BOTTOM
	frostwake.span_scale = 1.25
	frostwake.amount = 16
	frostwake.lifetime = 1.2
	frostwake.direction = Vector2(0.0, 1.0)
	frostwake.spread = 55.0
	frostwake.gravity = Vector2(0.0, 10.0)
	frostwake.velocity_min = 2.0
	frostwake.velocity_max = 10.0
	frostwake.damping = 6.0
	frostwake.angular_velocity = 70.0
	frostwake.scale_min = 0.3
	frostwake.scale_max = 0.75
	frostwake.scale_start = 1.0
	frostwake.scale_end = 0.15
	frostwake.on_move = true
	_ramp(frostwake, CosmeticThemes.pale(theme), CosmeticThemes.accent(theme),
		CosmeticThemes.pale(theme), 0.8)
	return [snow, crystals, frostwake] as Array[VipParticleLayer]


## VERDANT WARDEN - leaves while you walk, a quiet shine while you do not.
static func _verdant(theme: StringName) -> Array[VipParticleLayer]:
	# THE SIGNATURE LAYER, and it is the shine rather than the leaves. A title
	# whose only layer is movement-gated renders nothing at all while its owner
	# stands still, which is most of the time anyone is being looked at.
	var shine: VipParticleLayer = _layer(&"shine", VipParticleLayer.Shape.SPARKLE, 7)
	shine.span = VipParticleLayer.Span.BOX
	shine.amount = 8
	shine.lifetime = 1.2
	shine.explosiveness = 0.3
	shine.velocity_min = 0.0
	shine.velocity_max = 6.0
	shine.scale_min = 0.25
	shine.scale_max = 0.6
	_ramp(shine, CosmeticThemes.accent(theme), CosmeticThemes.accent(theme),
		CosmeticThemes.pale(theme), 0.7)

	var leaves: VipParticleLayer = _layer(&"leaves", VipParticleLayer.Shape.LEAF, 9)
	leaves.span = VipParticleLayer.Span.BOTTOM
	leaves.span_scale = 1.2
	leaves.amount = 18
	leaves.lifetime = 1.4
	leaves.direction = Vector2(-1.0, -0.4)
	leaves.spread = 45.0
	leaves.gravity = Vector2(-6.0, 10.0)
	leaves.velocity_min = 6.0
	leaves.velocity_max = 18.0
	leaves.angular_velocity = 140.0
	leaves.scale_min = 0.4
	leaves.scale_max = 0.9
	# Leaves are matte. Additive would make them glow like sparks, which is the
	# one thing a leaf must not do.
	leaves.additive = false
	leaves.on_move = true
	_ramp(leaves, CosmeticThemes.core(theme), CosmeticThemes.core(theme),
		CosmeticThemes.deep(theme), 0.9)
	return [shine, leaves] as Array[VipParticleLayer]


## AETHER STORM - blue static, cut by cyan arcs that fire in batches.
static func _storm(theme: StringName) -> Array[VipParticleLayer]:
	# explosiveness 1.0 on a looping emitter is a repeating BURST with no timer
	# and no node churn: the whole batch spawns together, dies together, and the
	# next strike is one lifetime later. The [CosmeticPreset] trick, same reason.
	var arcs: VipParticleLayer = _layer(&"arcs", VipParticleLayer.Shape.SHARD, 11)
	arcs.span = VipParticleLayer.Span.ENDS
	arcs.span_scale = 1.1
	arcs.amount = 6
	arcs.lifetime = 0.55
	arcs.explosiveness = 1.0
	arcs.direction = Vector2(0.0, -1.0)
	arcs.spread = 80.0
	arcs.velocity_min = 20.0
	arcs.velocity_max = 46.0
	arcs.damping = 30.0
	arcs.angular_velocity = 220.0
	arcs.scale_min = 0.4
	arcs.scale_max = 1.0
	arcs.scale_start = 1.0
	arcs.scale_end = 0.3
	_ramp(arcs, CosmeticThemes.pale(theme), CosmeticThemes.accent(theme),
		CosmeticThemes.accent(theme), 0.95)

	var charge: VipParticleLayer = _layer(&"charge", VipParticleLayer.Shape.PIP, 4)
	charge.span = VipParticleLayer.Span.BOX
	charge.amount = 12
	charge.lifetime = 0.5
	charge.spread = 180.0
	charge.velocity_min = 2.0
	charge.velocity_max = 14.0
	charge.scale_min = 0.25
	charge.scale_max = 0.55
	charge.detail = true
	_ramp(charge, CosmeticThemes.core(theme), CosmeticThemes.accent(theme),
		CosmeticThemes.pale(theme), 0.7)

	# THE TRAIL: sparks skittering off in BURSTS rather than streaming. A steady
	# stream of sparks is a sparkler; a batch thrown every two thirds of a second
	# is something earthing itself as it moves, which is the only read that
	# belongs on a storm title. explosiveness does that with no timer and no node
	# churn - the same trick the arcs above use.
	var sparkwake: VipParticleLayer = _layer(&"sparkwake", VipParticleLayer.Shape.PIP, 4)
	sparkwake.span = VipParticleLayer.Span.BOTTOM
	sparkwake.span_scale = 1.15
	sparkwake.amount = 18
	sparkwake.lifetime = 0.7
	sparkwake.explosiveness = 0.85
	sparkwake.direction = Vector2(0.0, 1.0)
	sparkwake.spread = 70.0
	sparkwake.velocity_min = 14.0
	sparkwake.velocity_max = 38.0
	sparkwake.damping = 34.0
	sparkwake.scale_min = 0.25
	sparkwake.scale_max = 0.6
	sparkwake.scale_start = 1.0
	sparkwake.scale_end = 0.25
	sparkwake.on_move = true
	_ramp(sparkwake, CosmeticThemes.pale(theme), CosmeticThemes.accent(theme),
		CosmeticThemes.core(theme), 0.95)
	return [arcs, charge, sparkwake] as Array[VipParticleLayer]


## LOTUS WEAVER - blossom falling past the name.
static func _lotus(theme: StringName) -> Array[VipParticleLayer]:
	var petals: VipParticleLayer = _layer(&"petals", VipParticleLayer.Shape.LEAF, 8)
	petals.span = VipParticleLayer.Span.TOP
	petals.span_scale = 1.35
	petals.amount = 13
	petals.lifetime = 1.4
	petals.direction = Vector2(0.3, 1.0)
	petals.spread = 25.0
	petals.gravity = Vector2(4.0, 12.0)
	petals.velocity_min = 3.0
	petals.velocity_max = 10.0
	petals.damping = 3.0
	petals.angular_velocity = 110.0
	petals.scale_min = 0.4
	petals.scale_max = 0.85
	# Petals are matte, for the same reason leaves are.
	petals.additive = false
	_ramp(petals, CosmeticThemes.core(theme), CosmeticThemes.core(theme),
		CosmeticThemes.accent(theme), 0.95)

	var bloom: VipParticleLayer = _layer(&"bloom", VipParticleLayer.Shape.DOT, 9)
	bloom.span = VipParticleLayer.Span.BOX
	bloom.amount = 9
	bloom.lifetime = 1.3
	bloom.direction = Vector2(0.0, -1.0)
	bloom.spread = 50.0
	bloom.velocity_min = 2.0
	bloom.velocity_max = 9.0
	bloom.scale_min = 0.3
	bloom.scale_max = 0.75
	bloom.detail = true
	_ramp(bloom, CosmeticThemes.pale(theme), CosmeticThemes.pale(theme),
		CosmeticThemes.core(theme), 0.5)

	# THE TRAIL: blossom pushed off the name as it passes and drifting down and
	# ACROSS. The sideways gravity is what tells it apart from the Warden's
	# leaves, which are the same shape and the same matte blend but are kicked
	# UPWARD and backward - petals settle, leaves are thrown.
	var petalwake: VipParticleLayer = _layer(&"petalwake", VipParticleLayer.Shape.LEAF, 8)
	petalwake.span = VipParticleLayer.Span.BOTTOM
	petalwake.span_scale = 1.2
	petalwake.amount = 16
	petalwake.lifetime = 1.4
	petalwake.direction = Vector2(0.35, 1.0)
	petalwake.spread = 30.0
	petalwake.gravity = Vector2(7.0, 9.0)
	petalwake.velocity_min = 2.0
	petalwake.velocity_max = 9.0
	petalwake.damping = 2.0
	petalwake.angular_velocity = 130.0
	petalwake.scale_min = 0.4
	petalwake.scale_max = 0.9
	petalwake.additive = false
	petalwake.on_move = true
	_ramp(petalwake, CosmeticThemes.core(theme), CosmeticThemes.accent(theme),
		CosmeticThemes.core(theme), 0.95)
	return [petals, bloom, petalwake] as Array[VipParticleLayer]


## ALCHEMICAL EXARCH - flares off the letters over a standing sunburst.
static func _solar(theme: StringName) -> Array[VipParticleLayer]:
	var flares: VipParticleLayer = _layer(&"flares", VipParticleLayer.Shape.SPARKLE, 9)
	flares.span = VipParticleLayer.Span.ENDS
	flares.amount = 10
	flares.lifetime = 0.9
	flares.explosiveness = 0.8
	flares.direction = Vector2(0.0, -1.0)
	flares.spread = 70.0
	flares.velocity_min = 6.0
	flares.velocity_max = 24.0
	flares.damping = 12.0
	flares.scale_min = 0.35
	flares.scale_max = 0.95
	flares.scale_start = 1.0
	flares.scale_end = 0.25
	_ramp(flares, CosmeticThemes.pale(theme), CosmeticThemes.pale(theme),
		CosmeticThemes.accent(theme), 1.0)

	var motes: VipParticleLayer = _layer(&"motes", VipParticleLayer.Shape.DOT, 5)
	motes.span = VipParticleLayer.Span.BOTTOM
	motes.span_scale = 1.15
	motes.amount = 11
	motes.lifetime = 1.3
	motes.direction = Vector2(0.0, -1.0)
	motes.spread = 30.0
	motes.gravity = Vector2(0.0, -10.0)
	motes.velocity_min = 5.0
	motes.velocity_max = 16.0
	motes.scale_min = 0.25
	motes.scale_max = 0.6
	motes.detail = true
	_ramp(motes, CosmeticThemes.core(theme), CosmeticThemes.accent(theme),
		CosmeticThemes.pale(theme), 0.65)

	# THE TRAIL: gold dust hanging in the air behind the wearer and burning out.
	# The same hanging idea as the Magus's runewake and deliberately a different
	# object: sparkles rather than marks, shrinking to nothing rather than
	# turning, warm rather than violet. Two titles may both leave something in the
	# air as long as nobody could mistake one for the other.
	var golddust: VipParticleLayer = _layer(&"golddust", VipParticleLayer.Shape.SPARKLE, 5)
	golddust.span = VipParticleLayer.Span.BOTTOM
	golddust.span_scale = 1.2
	golddust.amount = 18
	golddust.lifetime = 1.4
	golddust.direction = Vector2(0.0, -1.0)
	golddust.spread = 40.0
	golddust.velocity_min = 0.0
	golddust.velocity_max = 5.0
	golddust.damping = 10.0
	golddust.scale_min = 0.25
	golddust.scale_max = 0.7
	golddust.scale_start = 1.0
	golddust.scale_end = 0.1
	golddust.on_move = true
	_ramp(golddust, CosmeticThemes.pale(theme), CosmeticThemes.core(theme),
		CosmeticThemes.accent(theme), 0.85)
	return [flares, motes, golddust] as Array[VipParticleLayer]


## IRIDESCENT ASPECT - sparks in every dye the vault sells.
static func _prism(theme: StringName) -> Array[VipParticleLayer]:
	var dyes: Array[Color] = CosmeticThemes.prism_colors()

	# The FOUR-stop ramp earns its keep here. A particle walks three dyes on its
	# way out, so a field of sparks at mixed ages shows mixed colour - which is
	# dispersion spread over the particles instead of over one particle's life,
	# and is the only way a handful of sprites reads as a spectrum at all.
	var sparks: VipParticleLayer = _layer(&"sparks", VipParticleLayer.Shape.SPARKLE, 7)
	sparks.span = VipParticleLayer.Span.BOX
	sparks.span_scale = 1.2
	sparks.amount = 16
	sparks.lifetime = 1.2
	sparks.direction = Vector2(0.0, -1.0)
	sparks.spread = 55.0
	sparks.velocity_min = 4.0
	sparks.velocity_max = 18.0
	sparks.scale_min = 0.25
	sparks.scale_max = 0.7
	sparks.color_in = _dye(dyes, 0)
	sparks.color_mid = _dye(dyes, 2)
	sparks.late_stop = 0.62
	sparks.color_late = _dye(dyes, 4)
	sparks.color_out = _dye(dyes, 6)
	sparks.peak_alpha = 0.9

	# THE TRAIL, and the one the brief named: a ribbon of every dye in the vault,
	# left behind as the wearer runs. Near-zero velocity and no gravity, so in
	# world space the motes hang exactly where they were dropped and the path
	# itself is what carries the colour - a spray would mix the eight dyes into
	# one pale smear within a stride.
	#
	# The FOUR-stop ramp is what makes it a spectrum rather than a colour: each
	# mote walks three dyes over its life, so a ribbon of motes at mixed ages
	# shows mixed colour. That is dispersion spread over the particles instead of
	# over one particle, and the stops are offset from the sparks above so the two
	# layers are never showing the same colour at the same time.
	var ribbon: VipParticleLayer = _layer(&"ribbon", VipParticleLayer.Shape.PIP, 5)
	ribbon.span = VipParticleLayer.Span.BOTTOM
	ribbon.span_scale = 1.25
	ribbon.amount = 20
	ribbon.lifetime = 1.4
	ribbon.direction = Vector2(0.0, -1.0)
	ribbon.spread = 45.0
	ribbon.velocity_min = 0.0
	ribbon.velocity_max = 4.0
	ribbon.damping = 6.0
	ribbon.scale_min = 0.25
	ribbon.scale_max = 0.6
	ribbon.scale_start = 1.0
	ribbon.scale_end = 0.2
	ribbon.on_move = true
	ribbon.color_in = _dye(dyes, 1)
	ribbon.color_mid = _dye(dyes, 3)
	ribbon.late_stop = 0.66
	ribbon.color_late = _dye(dyes, 5)
	ribbon.color_out = _dye(dyes, 7)
	ribbon.peak_alpha = 0.85
	return [sparks, ribbon] as Array[VipParticleLayer]


## A layer with the defaults every one of these wants. Shape and pixel size are
## the two things none of them share.
static func _layer(id: StringName, shape: VipParticleLayer.Shape, px: int) -> VipParticleLayer:
	var layer: VipParticleLayer = VipParticleLayer.new()
	layer.id = id
	layer.shape = shape
	layer.shape_px = px
	return layer


## Three-stop colour ramp. In and out are the ENDS of the particle's life and are
## always transparent (see [member VipParticleLayer.peak_alpha]), so these three
## are hues and the alpha is one number.
static func _ramp(
	layer: VipParticleLayer, c_in: Color, c_mid: Color, c_out: Color, peak: float
) -> void:
	layer.color_in = c_in
	layer.color_mid = c_mid
	layer.color_out = c_out
	layer.peak_alpha = peak


## One dye out of the prism cycle, wrapping. Indexed rather than iterated so each
## layer can start on a different colour and the two are never in phase.
static func _dye(dyes: Array[Color], index: int) -> Color:
	if dyes.is_empty():
		return Color.WHITE
	return dyes[index % dyes.size()]
