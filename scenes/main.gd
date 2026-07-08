## Main — the persistent root scene. Owns mode switching; never unloaded.
##
## What this is: the node that lives for the whole program and decides
## which mode scene is loaded as its child. Since Phase 6 that's a full
## loop: Title → Exploration/Encounter → EndScreen → Title. It also applies
## encounter outcomes to the world (Phase 4): a defeated or resolved enemy
## leaves the roster before exploration reloads; a fled-from one stays,
## with one tick of encounter immunity armed.
##
## Why outcome-handling is here: the encounter scene doesn't know the grid
## exists, and the exploration scene is dead while the encounter runs.
## Something above both has to translate "outcome: victory" into "that
## roster entry is gone" — and Main is the only thing above both.
##
## How it connects: listens to every signal on the Events bus and reacts
## with scene swaps — encounter_triggered routes through the
## EncounterRouter (Phase 4.5), run_ended swaps in the end screen,
## new_run_requested resets GameState and starts a run, title_requested
## returns home. Every swap runs through a 0.3s fade. State survives only
## in the GameState autoload.
extends Node

const TITLE_SCENE := preload("res://scenes/title.tscn")
const END_SCREEN_SCENE := preload("res://scenes/end_screen.tscn")
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


func _ready() -> void:
	Events.encounter_triggered.connect(_on_encounter_triggered)
	Events.encounter_resolved.connect(_on_encounter_resolved)
	Events.player_died.connect(_on_player_died)
	Events.run_ended.connect(_on_run_ended)
	Events.new_run_requested.connect(_on_new_run_requested)
	Events.title_requested.connect(_on_title_requested)
	# Boot onto the title; the fade rect starts opaque so the first thing
	# the player sees is a fade-in.
	_swap_to(TITLE_SCENE.instantiate())


## Asks the router which scene runs this enemy's encounter flavor and swaps
## to it (Phase 4.5). Main no longer knows encounter.tscn exists — the
## router's table is the only place flavors map to scenes.
func enter_encounter(enemy_data: EnemyData, trigger_type: StringName) -> void:
	_swap_to(EncounterRouter.build_encounter(enemy_data, trigger_type))


func exit_encounter(_result: Dictionary) -> void:
	_swap_to(EXPLORATION_SCENE.instantiate())


func _swap_to(instance: Node) -> void:
	# Serialize: a swap requested while another is fading (run_ended can
	# land close to a mode switch) waits its turn instead of interleaving.
	while _switching:
		await get_tree().process_frame
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
		# screen is already on its way; don't swap exploration underneath.
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
	# Loss condition 1. end_run re-emits through run_ended, where the swap
	# to the end screen happens — one route for every way a run ends.
	GameState.end_run(&"death")


func _on_run_ended(_reason: StringName) -> void:
	# The end screen reads cause and state from GameState itself, and it —
	# not this handler — performs the once-per-run disk write, because only
	# by its _ready is the run log guaranteed complete (Decision 32).
	_swap_to(END_SCREEN_SCENE.instantiate())


func _on_new_run_requested() -> void:
	if _switching:
		# A double-tapped confirm shouldn't queue a second run start.
		return
	# Full reset except the RunHistory file on disk (plan Phase 6 task 1).
	GameState.reset_run()
	_swap_to(EXPLORATION_SCENE.instantiate())


func _on_title_requested() -> void:
	if _switching:
		return
	_swap_to(TITLE_SCENE.instantiate())
