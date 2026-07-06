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

@export var data: EnemyData

@onready var _rect: ColorRect = $Rect


func _ready() -> void:
	# Placeholder art: the resource's color stands in for a sprite until
	# real textures exist (technical plan, Decision 14).
	if data != null:
		_rect.color = data.color
