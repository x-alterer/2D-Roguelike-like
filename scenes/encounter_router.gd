## EncounterRouter — the single decision point between "an encounter was
## triggered" and "this scene runs it".
##
## What this is: one lookup table (encounter_flavor -> PackedScene) and one
## build function. For the PoC every flavor maps to the same encounter.tscn,
## which differentiates itself by the enemy resource's verb_set — so the
## routing looks trivial. It exists anyway because it is the seam the whole
## roster expansion plan hangs on: when a post-PoC encounter type needs its
## own scene (a puzzle, a chase), that is ONE new entry in this table, and
## no other system changes (Architecture Decisions: "Encounter routing").
##
## Why it is not an autoload: only Main calls it and it holds no state. An
## autoload would advertise it globally to scenes that must not know it
## exists — Exploration and Encounter never reference the router, and the
## router never references them beyond instantiating the routed scene.
##
## How it connects: Main hands it the enemy data and trigger type from
## encounter_triggered; it returns a ready-to-add encounter scene with both
## injected via setup(). The trigger type passes through untouched — the
## encounter scene, not the router, owns what framing means.
class_name EncounterRouter
extends RefCounted

const DEFAULT_ENCOUNTER := preload("res://scenes/encounter.tscn")

## The de-facto flavor enum (technical plan, Decision 22): a flavor exists
## if it has a key here. "strange" is the deliberately dumb third entry the
## plan demands — it proves a new variant loads without rewiring anything.
const FLAVOR_SCENES: Dictionary = {
	&"combat": DEFAULT_ENCOUNTER,
	&"intimate": DEFAULT_ENCOUNTER,
	&"strange": DEFAULT_ENCOUNTER,
}


## Picks the scene for this enemy's flavor, instantiates it, and injects
## the encounter's inputs. Returns the node ready for add_child.
static func build_encounter(enemy_data: EnemyData, trigger_type: StringName) -> Node:
	var scene: PackedScene = FLAVOR_SCENES.get(enemy_data.encounter_flavor)
	if scene == null:
		# A data file declared a flavor nobody registered. Content error,
		# not a crash: fall back to the default flow so play continues.
		push_error(
			"No route for encounter_flavor '%s' (enemy '%s') — add it to EncounterRouter.FLAVOR_SCENES."
			% [enemy_data.encounter_flavor, enemy_data.enemy_name]
		)
		scene = DEFAULT_ENCOUNTER
	var encounter := scene.instantiate()
	encounter.setup(enemy_data, trigger_type)
	return encounter
