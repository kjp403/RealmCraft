class_name VaultSkinVfx
## Client-only prestige recolor on a character (or preview) sprite. Lookup is
## [VaultSkins]; 0 clears the shader so Horizon skins stay untouched.

const SHADER: Shader = preload("res://source/common/gameplay/characters/player/vault_skin.gdshader")


static func apply_to_sprite(sprite: CanvasItem, vault_skin_id: int) -> void:
	if sprite == null:
		return
	if vault_skin_id <= 0 or not VaultSkins.is_valid(vault_skin_id):
		sprite.material = null
		return
	var hex: String = VaultSkins.tint_hex(vault_skin_id)
	var tint: Color = Color(hex) if not hex.is_empty() else Color(0.91, 0.75, 0.31)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter(&"tint", tint)
	mat.set_shader_parameter(&"style", float(VaultSkins.style_of(vault_skin_id)))
	mat.set_shader_parameter(&"strength", 1.0)
	mat.set_shader_parameter(&"keep_flesh", 1.0 if VaultSkins.keeps_flesh(vault_skin_id) else 0.0)
	sprite.material = mat


## Client-only Prismatic Dye recolor, through the SAME shader a vault skin uses.
## 0 clears it. Kept here rather than in its own Vfx class because the two are
## mutually exclusive on one material slot — putting both entry points in one
## file is what makes that constraint visible to whoever changes either.
##
## style 0 and keep_flesh 1: a cloth dye recolours the garment and leaves the
## face alone. A dye that repainted skin would read as a costume, not a dye.
static func apply_dye_to_sprite(sprite: CanvasItem, dye_id: int) -> void:
	if sprite == null:
		return
	if dye_id <= 0 or not PrismaticDye.is_valid(dye_id):
		sprite.material = null
		return
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter(&"tint", PrismaticDye.tint_of(dye_id))
	mat.set_shader_parameter(&"style", 0.0)
	mat.set_shader_parameter(&"strength", 1.0)
	mat.set_shader_parameter(&"keep_flesh", 1.0)
	sprite.material = mat
