## Main — the persistent root scene. Owns mode switching; never unloaded.
##
## What this is: an almost-empty node that lives for the whole program. Its
## one job is deciding which mode scene (Exploration or Encounter) is loaded
## as its child at any moment.
##
## Why it exists: the two modes must never load or reference each other —
## that coupling is what the architecture forbids. Something above both has
## to do the swapping, and that something is this scene.
##
## How it connects: listens to every signal on the Events bus. Exploration
## emitting encounter_triggered makes Main swap in the Encounter scene;
## Encounter emitting encounter_resolved swaps Exploration back in. State
## survives the swap only because it lives in the GameState autoload, not in
## the scenes being freed.
extends Node

const EXPLORATION_SCENE := preload("res://scenes/exploration.tscn")
const ENCOUNTER_SCENE := preload("res://scenes/encounter.tscn")

## The currently loaded mode scene (Exploration or Encounter instance).
var _active_mode: Node = null


func _ready() -> void:
	Events.encounter_triggered.connect(_on_encounter_triggered)
	Events.encounter_resolved.connect(_on_encounter_resolved)
	Events.player_died.connect(_on_player_died)
	Events.run_ended.connect(_on_run_ended)
	_switch_to(EXPLORATION_SCENE)


## Swaps the encounter screen in. `_enemy_data` is unused in Phase 1 (the
## debug path passes null); Phase 4 threads the real EnemyData resource
## through to the encounter scene here.
func enter_encounter(_enemy_data: Resource) -> void:
	_switch_to(ENCOUNTER_SCENE)


## Swaps exploration back in. `_result` is the encounter's outcome payload;
## Phase 4 applies it (remove defeated enemy, grant boon, arm flee immunity)
## before reloading exploration.
func exit_encounter(_result: Dictionary) -> void:
	_switch_to(EXPLORATION_SCENE)


func _switch_to(scene: PackedScene) -> void:
	if _active_mode != null:
		# queue_free, not free(): this runs inside a signal emitted by the
		# very scene being removed, and freeing a node while it is still
		# mid-emission is a crash. queue_free waits until the frame ends.
		_active_mode.queue_free()
	_active_mode = scene.instantiate()
	add_child(_active_mode)


func _on_encounter_triggered(enemy_data: Resource, trigger_type: StringName) -> void:
	# Console proof of the Phase 2 DoD: which enemy fired, via which trigger
	# type. Phase 4 threads this data into the encounter scene itself.
	if enemy_data is EnemyData:
		print("Main: encounter with '%s' (trigger: %s)" % [enemy_data.enemy_name, trigger_type])
	enter_encounter(enemy_data)


func _on_encounter_resolved(result: Dictionary) -> void:
	exit_encounter(result)


func _on_player_died() -> void:
	# End screens are Phase 6; until then the signal is just acknowledged.
	print("Main: player_died received (death screen arrives in Phase 6)")


func _on_run_ended(reason: StringName) -> void:
	print("Main: run_ended received, reason '%s' (end screens arrive in Phase 6)" % reason)
