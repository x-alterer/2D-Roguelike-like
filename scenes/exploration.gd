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

## The hand-made test floor (technical plan, Decision 13). One character per
## 16px tile, 40 columns x 22 rows: '#' wall, '.' floor, '@' entrance,
## 'X' exit, 'H' hostile spawn, 'B' beckoner spawn (all four markers sit on
## floor tiles). Layout: entrance room left, corridor to a center room (the
## hostile's patrol ground), corridor to the exit room right, and a dead-end
## alcove below the entrance room where the beckoner waits — off the path,
## so approaching it is always a deliberate choice.
const FLOOR_MAP: Array[String] = [
	"########################################",
	"#..........#############################",
	"#..........#############################",
	"#..........#######..........############",
	"#..........#######..........############",
	"#..@........................####.......#",
	"#..........#######..........####.......#",
	"#..........#######.....H....####.......#",
	"#..........#######.....................#",
	"#..........#######..........####....X..#",
	"#####.############..........####.......#",
	"#####.############..........####.......#",
	"#####.############..........####.......#",
	"#####.##########################.......#",
	"###.....########################.......#",
	"###.....################################",
	"###..B..################################",
	"###.....################################",
	"########################################",
	"########################################",
	"########################################",
	"########################################",
]

const TILE_SOURCE := 0
const TILE_FLOOR := Vector2i(0, 0)
const TILE_WALL := Vector2i(1, 0)
const TILE_EXIT := Vector2i(2, 0)

@onready var _floor: TileMapLayer = $Floor
@onready var _player: ColorRect = $Player
@onready var _status_label: Label = $StatusLabel

## Filled by _build_floor from the map's marker characters.
var _entrance_cell := Vector2i.ZERO
var _exit_cell := Vector2i.ZERO
var _hostile_spawns: Array[Vector2i] = []
var _beckoner_spawns: Array[Vector2i] = []


func _ready() -> void:
	_build_floor()
	_refresh()


## Turns the ASCII map into TileMapLayer cells and records the marker
## positions. Walkability is NOT stored here — it lives on the tileset's
## "walkable" custom data layer, so tile identity and its rules stay in one
## place (plan task 2.1).
func _build_floor() -> void:
	for y in FLOOR_MAP.size():
		var row := FLOOR_MAP[y]
		for x in row.length():
			var cell := Vector2i(x, y)
			var ch := row[x]
			if ch == "#":
				_floor.set_cell(cell, TILE_SOURCE, TILE_WALL)
				continue
			_floor.set_cell(cell, TILE_SOURCE, TILE_EXIT if ch == "X" else TILE_FLOOR)
			match ch:
				"@":
					_entrance_cell = cell
				"X":
					_exit_cell = cell
				"H":
					_hostile_spawns.append(cell)
				"B":
					_beckoner_spawns.append(cell)


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
