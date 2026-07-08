## Title — the run's front door (Phase 6; seed replay and the regression
## toggle arrived with Phase 8).
##
## What this is: the screen the game boots into and returns to after every
## end screen. One prompt, a seed box, the floor-mode toggle, and the
## runs-played count so the meta-layer (accumulated self-knowledge,
## nothing mechanical) is visible from the first second.
##
## Why the seed box: the Phase 8 DoD requires that any seed shown on the
## end screen can be replayed. Type it here (or click the box and press
## Enter inside it) and the run regenerates that exact floor with those
## exact rolls; leave it blank for a fresh seed. T switches to the
## hand-made regression floor — the level where generation bugs can never
## hide gameplay bugs (Decision 41).
##
## How it connects: reads the RunHistory file through GameState
## (read-only here). Emits Events.new_run_requested with the parsed seed,
## or -1 for random; Main resets GameState and starts the run.
extends Node2D

@onready var _history_label: Label = $HistoryLabel
@onready var _seed_input: LineEdit = $SeedInput
@onready var _floor_label: Label = $FloorLabel


func _ready() -> void:
	var history := GameState.load_run_history()
	if history.runs.is_empty():
		_history_label.text = "No runs yet."
	else:
		_history_label.text = "Runs so far: %d" % history.runs.size()
	# Enter pressed INSIDE the seed box starts the run too — while the box
	# has focus it consumes keys, so _unhandled_input never sees them.
	_seed_input.text_submitted.connect(_on_seed_submitted)
	_refresh_floor_label()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("confirm"):
		get_viewport().set_input_as_handled()
		_start_run()
	elif event.is_action_pressed("toggle_floor"):
		get_viewport().set_input_as_handled()
		GameState.use_handmade_floor = not GameState.use_handmade_floor
		_refresh_floor_label()


func _on_seed_submitted(_text: String) -> void:
	_start_run()


func _start_run() -> void:
	var text := _seed_input.text.strip_edges()
	var fixed_seed := -1
	if not text.is_empty() and text.is_valid_int() and text.to_int() >= 0:
		fixed_seed = text.to_int()
	Events.new_run_requested.emit(fixed_seed)


func _refresh_floor_label() -> void:
	var mode := "hand-made regression floor" if GameState.use_handmade_floor else "generated floor"
	_floor_label.text = "T — floor: %s" % mode
