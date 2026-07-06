## Exploration — Mode 1, Phase 1 placeholder.
##
## What this is: a stand-in for the grid exploration mode. It shows the
## athlete as a rectangle at her GameState grid position and lets the debug
## keys exercise the mode switch. There is no floor, no walls, no turn
## scheduler yet — Phase 2 replaces the movement below with the real MOVE
## loop (TileMap walkability, world tick, enemies).
##
## Why it exists: Phase 1's Definition of Done requires proving that position
## survives a mode switch and that HP set in one mode is readable in the
## other. This scene is the exploration half of that proof.
##
## How it connects: emits Events.encounter_triggered when E is pressed; Main
## hears it and swaps in the Encounter scene (this scene is freed). Reads and
## writes only GameState — never the Encounter scene directly.
extends Node2D

const TILE_SIZE := 16
## Placeholder playable area: the 640x360 viewport in whole 16px tiles.
## Phase 2's TileMap replaces these bounds with real walkability checks.
const GRID_COLS := 40
const GRID_ROWS := 22

@onready var _player: ColorRect = $Player
@onready var _status_label: Label = $StatusLabel


func _ready() -> void:
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_encounter"):
		# null enemy data + "debug" trigger: enemies and real trigger types
		# arrive in Phase 2. Main only needs the signal to switch modes.
		Events.encounter_triggered.emit(null, &"debug")
		get_viewport().set_input_as_handled()
		return

	var step := Vector2i.ZERO
	if event.is_action_pressed("move_up"):
		step = Vector2i.UP
	elif event.is_action_pressed("move_down"):
		step = Vector2i.DOWN
	elif event.is_action_pressed("move_left"):
		step = Vector2i.LEFT
	elif event.is_action_pressed("move_right"):
		step = Vector2i.RIGHT
	if step == Vector2i.ZERO:
		return

	# Placeholder movement (technical plan, Decision 4): whole-tile steps,
	# clamped to the screen, written straight to GameState so the position
	# demonstrably survives the mode switch. No walls, no world tick.
	var target := GameState.grid_position + step
	target.x = clampi(target.x, 0, GRID_COLS - 1)
	target.y = clampi(target.y, 0, GRID_ROWS - 1)
	GameState.grid_position = target
	_refresh()
	get_viewport().set_input_as_handled()


## Redraws everything this scene derives from GameState: the player rect's
## pixel position (grid cell x 16 — logical position is the truth, pixels
## are presentation) and the status readout.
func _refresh() -> void:
	_player.position = Vector2(GameState.grid_position * TILE_SIZE)
	_status_label.text = "HP %d/%d   Corruption %d/%d" % [
		GameState.hp, GameState.max_hp,
		GameState.corruption, GameState.CORRUPTION_MAX,
	]
