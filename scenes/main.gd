## Main — the persistent root scene. Owns mode switching; never unloaded.
##
## What this is: the node that lives for the whole program and decides which
## mode scene (Exploration or Encounter) is loaded as its child. Since
## Phase 4 it also applies encounter outcomes to the world: a defeated or
## resolved enemy leaves the roster before exploration reloads, and a
## fled-from one stays, with one tick of encounter immunity armed so the
## return can't chain straight back into the same trigger.
##
## Why outcome-handling is here: the encounter scene doesn't know the grid
## exists, and the exploration scene is dead while the encounter runs.
## Something above both has to translate "outcome: victory" into "that
## roster entry is gone" — and Main is the only thing above both.
##
## How it connects: listens to every signal on the Events bus. Exploration
## emitting encounter_triggered makes Main ask the EncounterRouter for the
## scene that runs this enemy's flavor (Phase 4.5); Encounter emitting
## encounter_resolved makes Main apply the outcome and swap Exploration
## back in. Both swaps run through a 0.3s fade. State survives only in the
## GameState autoload.
extends Node

const EXPLORATION_SCENE := preload("res://scenes/exploration.tscn")

## Outcomes after which the engaged enemy leaves the grid: it died, was
## talked or redirected down, or was yielded to (chosen or forced) — in
## every case the encounter is spent (plan task 4.2). The boon itself was
## already granted inside the encounter.
const REMOVE_OUTCOMES: Array[StringName] = [
	&"victory", &"talked_down", &"redirected", &"yielded", &"yielded_forced",
]
## Outcomes that leave the enemy in place and grant the lockdown §3
## one-tick encounter immunity on return.
const IMMUNITY_OUTCOMES: Array[StringName] = [&"fled", &"resisted"]

## Half the transition: fade to black, swap, fade back — 0.3s total.
const FADE_TIME := 0.15

## The currently loaded mode scene (Exploration or Encounter instance).
var _active_mode: Node = null
## True while a fade+swap is in flight; bus signals arriving mid-swap are
## dropped rather than starting a second, overlapping transition.
var _switching := false

@onready var _fade_rect: ColorRect = $FadeLayer/FadeRect


func _ready() -> void:
	Events.encounter_triggered.connect(_on_encounter_triggered)
	Events.encounter_resolved.connect(_on_encounter_resolved)
	Events.player_died.connect(_on_player_died)
	Events.run_ended.connect(_on_run_ended)
	# Boot straight into exploration; the fade rect starts opaque so the
	# first thing the player sees is a fade-in.
	_swap_to(EXPLORATION_SCENE.instantiate())


## Asks the router which scene runs this enemy's encounter flavor and swaps
## to it (Phase 4.5). Main no longer knows encounter.tscn exists — the
## router's table is the only place flavors map to scenes.
func enter_encounter(enemy_data: EnemyData, trigger_type: StringName) -> void:
	_swap_to(EncounterRouter.build_encounter(enemy_data, trigger_type))


func exit_encounter(_result: Dictionary) -> void:
	_swap_to(EXPLORATION_SCENE.instantiate())


func _swap_to(instance: Node) -> void:
	_switching = true
	await _fade_to(1.0)
	if _active_mode != null:
		# queue_free, not free(): this often runs inside a signal emitted
		# by the very scene being removed, and freeing a node mid-emission
		# is a crash. queue_free waits until the frame ends.
		_active_mode.queue_free()
	_active_mode = instance
	add_child(instance)
	await _fade_to(0.0)
	_switching = false


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", alpha, FADE_TIME)
	await tween.finished


func _on_encounter_triggered(enemy_data: Resource, trigger_type: StringName) -> void:
	if _switching:
		return
	if enemy_data is EnemyData:
		print("Main: encounter with '%s' (trigger: %s)" % [enemy_data.enemy_name, trigger_type])
	enter_encounter(enemy_data as EnemyData, trigger_type)


## Applies the outcome to the world, then returns to the grid (task 4.2).
func _on_encounter_resolved(result: Dictionary) -> void:
	if _switching:
		return
	var outcome: StringName = result.get("outcome", &"")
	var engaged: int = GameState.engaged_enemy_index
	GameState.engaged_enemy_index = -1
	if outcome in REMOVE_OUTCOMES:
		if engaged >= 0 and engaged < GameState.enemy_roster.size():
			GameState.enemy_roster.remove_at(engaged)
	elif outcome in IMMUNITY_OUTCOMES:
		GameState.pending_immunity_ticks = 1
	exit_encounter(result)


func _on_player_died() -> void:
	# End screens are Phase 6; until then the signal is just acknowledged.
	print("Main: player_died received (death screen arrives in Phase 6)")


func _on_run_ended(reason: StringName) -> void:
	print("Main: run_ended received, reason '%s' (end screens arrive in Phase 6)" % reason)
