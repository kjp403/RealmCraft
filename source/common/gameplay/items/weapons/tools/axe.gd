class_name Axe
extends Pickaxe
## A woodcutting axe. Mechanically a tool-swing like the pickaxe — it reuses
## the same swing animation (extends Pickaxe so PickSwingAbility's `is Pickaxe`
## animation hook still fires) and the same PickArc hitbox. Only its item's
## tool_type (&"axe") and sprite differ, which is what lets it chop trees a
## pickaxe can't work.
