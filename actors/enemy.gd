## EnemyActor — one enemy on the exploration grid.
##
## What this is: a GridActor plus an identity — the EnemyData resource in
## `data`. The resource says what this enemy is (stats, verbs, trigger
## type); this script is only its body on the grid.
##
## Why behavior keys off data.trigger_type: the plan differentiates the two
## Phase 2 behaviors by trigger type — proximity enemies wander and pursue
## (a threat), player_initiated enemies hold still (an invitation). The
## data file decides; the script obeys. A new enemy kind should never need
## a new actor script.
##
## How it connects: exploration.gd spawns enemy.tscn per map marker and
## assigns `data` before adding it to the tree. The scheduler (task 2.4)
## drives it each tick; the trigger dispatcher (task 2.6) sends `data`
## through Events.encounter_triggered when this enemy's encounter fires.
class_name EnemyActor
extends GridActor

## A hostile notices the player at this Manhattan distance and flashes once
## per run (technical plan, Decision 15).
const SPOT_RANGE := 5

@export var data: EnemyData

var _has_spotted := false
var _glow_tween: Tween

@onready var _rect: ColorRect = $Rect


func _ready() -> void:
	# Placeholder art: the resource's color stands in for a sprite until
	# real textures exist (technical plan, Decision 14).
	if data != null:
		_rect.color = data.color


## Where this enemy wants to move this tick. Returning a cell is a wish,
## not a move — the scheduler validates it against walls, occupancy and
## trigger rules. Returning the current cell means "stay put".
func propose_step(player_cell: Vector2i) -> Vector2i:
	if data.trigger_type == &"player_initiated":
		# Beckoners hold still: the invitation only works if the player is
		# the one who closes the distance.
		return grid_pos
	# Hostile wanderer: 50% step toward the player, 50% random step. Rolls
	# draw from the seeded run RNG so a run replays identically from its
	# seed.
	if GameState.rng.randf() < 0.5:
		return grid_pos + _step_toward(player_cell)
	var dirs: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	return grid_pos + dirs[GameState.rng.randi_range(0, 3)]


## Straight-line pursuit, no pathfinding: step along the axis with the
## larger distance. Good enough to read as a threat; real pathfinding is
## deliberately outside the PoC's scope.
func _step_toward(target_cell: Vector2i) -> Vector2i:
	var delta := target_cell - grid_pos
	if absi(delta.x) >= absi(delta.y):
		return Vector2i(signi(delta.x), 0)
	return Vector2i(0, signi(delta.y))


## Called by the scheduler after every tick settles. Drives the two Phase 2
## feedback cues: the hostile's one-shot "spotted you" flash and the
## beckoner's within-reach glow. The loop's feedback stage breaks if the
## player can't discern what the world is doing (plan task 2.7).
func update_feedback(player_cell: Vector2i) -> void:
	var dist := absi(player_cell.x - grid_pos.x) + absi(player_cell.y - grid_pos.y)
	if data.trigger_type == &"player_initiated":
		# Glow while the player is close enough that their next step could
		# be the approach.
		_set_glowing(dist <= 1)
	elif data.trigger_type == &"proximity" and not _has_spotted and dist <= SPOT_RANGE:
		_has_spotted = true
		_flash()


## One quick blink to white and back — a threat announcing itself.
func _flash() -> void:
	var flash_tween := create_tween()
	flash_tween.tween_property(_rect, "color", Color.WHITE, 0.05)
	flash_tween.tween_property(_rect, "color", data.color, 0.15)


## Soft repeating pulse while glowing; stops (and resets brightness) the
## moment the player steps out of reach.
func _set_glowing(glowing: bool) -> void:
	if glowing and _glow_tween == null:
		_glow_tween = create_tween().set_loops()
		_glow_tween.tween_property(_rect, "modulate", Color(1.7, 1.7, 1.7), 0.4)
		_glow_tween.tween_property(_rect, "modulate", Color.WHITE, 0.4)
	elif not glowing and _glow_tween != null:
		_glow_tween.kill()
		_glow_tween = null
		_rect.modulate = Color.WHITE
