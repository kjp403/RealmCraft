class_name VfxDrawLayer
extends Node2D
## A child canvas item with its own blend mode that calls back to paint.
##
## Exists because a CanvasItem gets exactly ONE blend mode. Any effect that needs
## both solid geometry and additive light out of its drawing — carved stone under
## glowing runes, black char under molten rock, a bright title over a dark
## backing — physically cannot do it in one node. The alternatives are worse:
## making the whole node additive turns the solid half into a lamp, and leaving
## it mixed makes the light half look painted on.
##
## Owns no state beyond the callback. It is a second canvas item and nothing else.
##
## Lives here rather than inside [CosmeticPreset], where it started, because the
## title VFX need it too. As an inner class it dragged the entire cosmetics preset
## tree — and through it ClientState — into anything that touched it, which broke
## the titles in tool runs that have no autoloads and coupled two systems that
## have nothing to do with each other.
##
## Redrawing is the OWNER'S job: call queue_redraw() on this node from whatever
## already ticks. That keeps a layer from paying for its own _process, which
## matters when the owner is something like a nameplate that exists once per
## player on screen.

## Called with this node as its only argument; use the layer's own draw_* methods.
var painter: Callable


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)
