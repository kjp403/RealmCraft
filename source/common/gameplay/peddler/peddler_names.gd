class_name PeddlerNames
## The strings the Traveling Peddler's spawned nodes are addressed by.
##
## Split out of the manager because that script is an AUTOLOAD: an autoload has
## no class_name, so nothing can reach a constant on it without going through the
## live autoload instance — which the server handlers must not have to do just to
## read a node name. These are plain constants both sides share.

## NPCResource filename slug the cart's NPC is built from.
const NPC_SLUG: StringName = &"traveling_peddler"
## Node name the spawned Peddler is given. The shop window sends this back with
## every request so the server can range-check against the right node.
const NODE_NAME: String = "TravelingPeddler"
## Node name the spawned Vault Chest is given.
const VAULT_NODE_NAME: String = "PeddlerVault"
