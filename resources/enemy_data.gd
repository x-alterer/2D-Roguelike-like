## EnemyData — everything that defines one enemy, as a data file.
##
## What this is: a Resource script — a data schema with no behavior. Each
## enemy in the game is a .tres file filled with these fields (see
## resources/enemies/). New enemy = new data file, zero code changes; this
## is the roster-expansion seam the Architecture Decisions table locks in.
##
## Why one schema serves both encounter flavors: combat-specific and
## intimate-specific fields simply go unused by the other flavor. That's
## simpler than a resource class hierarchy at PoC scale, and the plan's
## Data Schema Reference specifies exactly this shape.
##
## How it connects: EnemyActor carries one of these on the grid and keys its
## behavior off trigger_type. The trigger dispatcher sends the resource
## through Events.encounter_triggered; from Phase 3/4 the encounter screen
## reads verb_set, stats and dialogue from it to run the whole encounter.
class_name EnemyData
extends Resource

@export var enemy_name: String
@export var sprite: Texture2D
## Placeholder-art stand-in for `sprite`: the grid rectangle's color.
## Beckoners must read as visibly distinct from hostiles (Phase 2 task 5;
## technical plan, Decision 14).
@export var color: Color = Color.WHITE
## "combat" or "intimate" — which verb rules the encounter runs.
@export var encounter_flavor: StringName
## design-lockdown.md §7: "proximity", "player_initiated" or
## "enemy_initiated". Decides when this enemy's encounter fires, its grid
## behavior, and (Phase 4.5) who acts first in the opening beat.
@export var trigger_type: StringName
## The verbs this enemy's encounter menu offers, in display order. The menu
## renders exactly this list — no verb is hardcoded into any scene.
@export var verb_set: Array[StringName]

@export_group("Combat stats")
@export var hp: int
@export var atk: int
@export var def_stat: int
## Flee succeeds on a d100 roll >= this value x 100 (design-lockdown.md §3).
@export var flee_difficulty: float

@export_group("Combat-specific")
## True: Talk advances dialogue_lines and can end the encounter peacefully.
## False: Talk wastes the turn. This flag is also half of the combat
## corruption trigger — Fighting a talk-receptive enemy costs +3 corruption
## (design-lockdown.md §5).
@export var talk_receptivity: bool
@export var dialogue_lines: Array[String]

@export_group("Intimate-specific")
## Corruption paid on Yield — and on a forced yield when the 3-stage
## sequence completes (design-lockdown.md §4).
@export var yield_corruption_value: int = 10
## Resist succeeds on a d100 roll >= this value x 100.
@export var resist_difficulty: float
## Redirect succeeds on a d100 roll >= this value x 100 (lockdown §4; added
## to the plan's schema — technical plan, Decision 14).
@export var redirect_difficulty: float
## Redirect is only offered while this is non-empty.
@export var redirect_options: Array[String]
## Granted on a chosen Yield, never on a forced one. Becomes an ItemData
## resource when items exist (Phase 3/4).
@export var boon_on_yield: Resource
