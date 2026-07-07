## ItemData — one usable item, as a data file.
##
## What this is: a Resource script, same pattern as EnemyData — a schema with
## no behavior. Each item type is a .tres file (see resources/items/). New
## item = new data file plus, if it has a new effect, one match arm in the
## encounter scene's item resolution.
##
## Why it exists now: Phase 3's UseItem verb needs something to consume, and
## the beckoner's boon_on_yield needs something to grant (technical plan,
## Decision 18). The lockdown defines exactly one effect for the PoC: heal
## +8 HP, capped at max HP. Phase 9 adds a corruption-reduce item by writing
## a second data file.
##
## How it connects: GameState.inventory is an array of these. The encounter
## scene consumes them (UseItem) and grants them (Yield boons); walk-over
## pickup on the grid is Phase 4+ wiring.
class_name ItemData
extends Resource

@export var item_name: String
## What using it does. The encounter scene maps this to a resolution:
## "heal" restores `amount` HP.
@export var effect: StringName = &"heal"
## Effect magnitude — HP restored for "heal".
@export var amount: int = 8
