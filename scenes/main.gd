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
	&"intimidated", &"overwhelmed",
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
@onready var _end_layer: CanvasLayer = $EndLayer
@onready var _end_rect: ColorRect = $EndLayer/EndRect
@onready var _end_label: Label = $EndLayer/EndLabel


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
	if _switching or GameState.run_over:
		# run_over: the run ended mid-encounter (corruption max) — the end
		# overlay is already up and the tree is pausing; don't swap scenes
		# underneath it.
		return
	var outcome: StringName = result.get("outcome", &"")
	var engaged: int = GameState.engaged_enemy_index
	GameState.engaged_enemy_index = -1
	if engaged >= 0 and engaged < GameState.enemy_roster.size():
		_log_encounter(GameState.enemy_roster[engaged]["data"], result)
	if outcome in REMOVE_OUTCOMES:
		if engaged >= 0 and engaged < GameState.enemy_roster.size():
			GameState.enemy_roster.remove_at(engaged)
	elif outcome in IMMUNITY_OUTCOMES:
		GameState.pending_immunity_ticks = 1
	exit_encounter(result)


## Appends the plan-schema encounter record to the run log (pulled forward
## from Phase 6 because Phase 5's run-end record consumes it, Decision 28).
func _log_encounter(enemy_data: EnemyData, result: Dictionary) -> void:
	GameState.run_log.append({
		"enemy_name": enemy_data.enemy_name,
		"encounter_flavor": enemy_data.encounter_flavor,
		"trigger_type": enemy_data.trigger_type,
		"verbs_chosen": result.get("verbs_chosen", []),
		"outcome": result.get("outcome", &""),
		"corruption_delta": result.get("corruption_delta", 0),
		"turns_elapsed": result.get("turns_elapsed", 0),
	})


func _on_player_died() -> void:
	# Loss condition 1. end_run records the run and re-emits through
	# run_ended, where the overlay is chosen — one place decides visuals.
	GameState.end_run(&"death")


func _on_run_ended(reason: StringName) -> void:
	match reason:
		&"corruption":
			# Loss condition 2 gets the DISTINCT end (lockdown §6): her
			# track's Bad End text on an armor-red field.
			_show_end_overlay(GameState.corruption_track.bad_end_text, Color(0.22, 0.02, 0.05, 0.95))
		&"death":
			_show_end_overlay("She falls.\n\nThe dream closes over the place she was.",
					Color(0.04, 0.04, 0.07, 0.95))
		_:
			_show_end_overlay("The run is over. (%s)" % reason, Color(0.04, 0.04, 0.07, 0.95))


## Minimal run-over screen (Decision 27): overlay plus a paused tree. The
## title -> run -> end -> title loop is Phase 6; until then, relaunch.
func _show_end_overlay(text: String, tint: Color) -> void:
	_end_rect.color = tint
	# The restart loop is Phase 6; until then the honest instruction is F5.
	_end_label.text = "%s\n\n(Run over — relaunch to start again.)" % text
	_end_layer.visible = true
	get_tree().paused = true
