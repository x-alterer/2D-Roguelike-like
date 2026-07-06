## Encounter — Mode 2, Phase 1 placeholder.
##
## What this is: a stand-in for the encounter screen. It shows a colored
## rectangle where the enemy will be, the athlete's HP and corruption, and
## two debug keys: H damages her by 1 (to prove state written here is
## readable back in exploration), Escape ends the "encounter". Phase 3
## replaces this with the real screen — verb menu, data-driven enemies,
## resolution rules.
##
## Why it exists: the encounter half of Phase 1's Definition of Done — enter
## via E, leave via Escape, and HP changes made here must survive the switch.
##
## How it connects: emits Events.encounter_resolved when Escape is pressed;
## Main hears it and swaps Exploration back in (this scene is freed). Reads
## and writes only GameState — never the Exploration scene directly.
extends Node2D

@onready var _status_label: Label = $StatusLabel


func _ready() -> void:
	_refresh_status()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		# Stub payload; Phase 3 fills the full contract (outcome,
		# verbs_chosen, turns_elapsed, corruption_delta).
		Events.encounter_resolved.emit({"outcome": &"debug_exit"})
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_damage"):
		# maxi floors at 0 because HP below zero is meaningless; the actual
		# death signal on HP 0 is Phase 3's job, not the debug key's.
		GameState.hp = maxi(GameState.hp - 1, 0)
		_refresh_status()
		get_viewport().set_input_as_handled()


func _refresh_status() -> void:
	_status_label.text = "HP %d/%d\nCorruption %d/%d" % [
		GameState.hp, GameState.max_hp,
		GameState.corruption, GameState.CORRUPTION_MAX,
	]
