## Title — the run's front door (Phase 6).
##
## What this is: the screen the game boots into and returns to after every
## end screen. One prompt, plus the runs-played count so the meta-layer
## (accumulated self-knowledge, nothing mechanical) is visible from the
## first second.
##
## Why it's a mode scene: it lives in Main's swap slot exactly like
## Exploration and Encounter, and talks to Main the only allowed way —
## through the Events bus. Confirm emits new_run_requested; Main resets
## GameState and starts the run.
##
## How it connects: reads the RunHistory file through GameState (read-only
## here). Emits Events.new_run_requested.
extends Node2D

@onready var _history_label: Label = $HistoryLabel


func _ready() -> void:
	var history := GameState.load_run_history()
	if history.runs.is_empty():
		_history_label.text = "No runs yet."
	else:
		_history_label.text = "Runs so far: %d" % history.runs.size()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("confirm"):
		get_viewport().set_input_as_handled()
		Events.new_run_requested.emit()
