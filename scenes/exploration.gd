## Exploration — Mode 1: the grid the athlete walks.
##
## What this is: the exploration scene. It builds the hand-made floor from
## an ASCII map, owns the player actor, and validates every move attempt —
## a keypress becomes a committed step, a bump, or (from task 2.6 on) an
## encounter trigger, and this script is the single place that decides
## which. The turn scheduler and trigger dispatcher (tasks 2.4/2.6) also
## live here, per the plan: "the scheduler lives in Exploration, not in
## GameState".
##
## Why movement rules are here and not on the player: rules need the whole
## board — walkability, occupancy, trigger types. The actors only know how
## to be somewhere; this scene knows what being there means.
##
## How it connects: reads/writes GameState.grid_position so position
## survives mode switches. Emits Events.encounter_triggered (debug key E
## until the real dispatcher lands); Main responds by swapping in the
## Encounter scene, which frees this one.
extends Node2D

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

const ENEMY_SCENE := preload("res://actors/enemy.tscn")
const HOSTILE_DATA := preload("res://resources/enemies/test_hostile.tres")
const BECKONER_DATA := preload("res://resources/enemies/test_beckoner.tres")

@onready var _floor: TileMapLayer = $Floor
@onready var _actors: Node2D = $Actors
@onready var _player: PlayerActor = $Actors/Player
@onready var _status_label: Label = $StatusLabel

## Filled by _build_floor from the map's marker characters.
var _entrance_cell := Vector2i.ZERO
var _exit_cell := Vector2i.ZERO
var _hostile_spawns: Array[Vector2i] = []
var _beckoner_spawns: Array[Vector2i] = []

## Every living enemy on the grid, in spawn order (which is also their turn
## order within a tick).
var _enemies: Array[EnemyActor] = []


func _ready() -> void:
	_build_floor()
	_spawn_player()
	_spawn_enemies()
	_refresh_status()


## Turns the ASCII map into TileMapLayer cells and records the marker
## positions. Walkability is NOT stored here — it lives on the tileset's
## "walkable" custom data layer, so a tile's identity and its rules stay in
## one place (plan task 2.1).
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


func _spawn_player() -> void:
	if GameState.grid_position == GameState.NO_POSITION:
		# Fresh run: the entrance tile is map data, so GameState left the
		# spawn cell to us (technical plan, Decision 16).
		GameState.grid_position = _entrance_cell
	_player.place_at(GameState.grid_position)


## Instantiates one EnemyActor per map marker. Phase 2 limitation: enemies
## respawn fresh every time this scene loads, including after an encounter —
## persisting the roster across mode switches is Phase 4 (task 4.2).
func _spawn_enemies() -> void:
	for cell in _hostile_spawns:
		_spawn_enemy(HOSTILE_DATA, cell)
	for cell in _beckoner_spawns:
		_spawn_enemy(BECKONER_DATA, cell)


func _spawn_enemy(data: EnemyData, cell: Vector2i) -> void:
	var enemy: EnemyActor = ENEMY_SCENE.instantiate()
	# Data must be set before add_child so the actor's _ready sees it.
	enemy.data = data
	_actors.add_child(enemy)
	enemy.place_at(cell)
	_enemies.append(enemy)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_encounter"):
		# Phase 1 leftover; removed in Phase 4 when real triggers take over.
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
	get_viewport().set_input_as_handled()
	_try_player_move(step)


## The move rule from design-lockdown.md §2: walkable and unoccupied → step;
## otherwise bump, and a rejected move consumes no turn.
func _try_player_move(step: Vector2i) -> void:
	var target := _player.grid_pos + step
	if not _is_walkable(target):
		_player.bump(step)
		return
	_player.step_to(target)
	GameState.grid_position = target


func _is_walkable(cell: Vector2i) -> bool:
	var tile := _floor.get_cell_tile_data(cell)
	# Cells outside the painted map have no tile at all — treat as solid.
	return tile != null and bool(tile.get_custom_data("walkable"))


func _refresh_status() -> void:
	_status_label.text = "HP %d/%d   Corruption %d/%d" % [
		GameState.hp, GameState.max_hp,
		GameState.corruption, GameState.CORRUPTION_MAX,
	]
