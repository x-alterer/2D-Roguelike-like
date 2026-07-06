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
## survives mode switches. When a trigger condition is met (or debug key E
## is pressed), emits Events.encounter_triggered with the enemy's data;
## Main responds by swapping in the Encounter scene, which frees this one.
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

## Filled by _build_floor from the map's marker characters.
var _entrance_cell := Vector2i.ZERO
var _exit_cell := Vector2i.ZERO
var _hostile_spawns: Array[Vector2i] = []
var _beckoner_spawns: Array[Vector2i] = []

## Every living enemy on the grid, in spawn order (which is also their turn
## order within a tick).
var _enemies: Array[EnemyActor] = []

## True while a tick resolves; input is ignored so a held key can't outrun
## the world's animations.
var _is_ticking := false
## Set the instant a trigger fires. Main is already replacing this scene at
## that point, so every loop checks it and stops — nothing may act after an
## encounter begins.
var _encounter_fired := false
## Ticks during which no encounter can fire. Phase 4 arms this after a
## successful flee (design-lockdown.md §3: "one tick of encounter
## immunity"); the dispatcher already honors it so Phase 4 only has to set
## it (technical plan, Decision 8).
var _immunity_ticks := 0

@onready var _floor: TileMapLayer = $Floor
@onready var _actors: Node2D = $Actors
@onready var _player: PlayerActor = $Actors/Player
@onready var _status_label: Label = $StatusLabel


func _ready() -> void:
	_build_floor()
	_spawn_player()
	_spawn_enemies()
	_update_feedback()
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
	if _is_ticking or _encounter_fired:
		return
	if event.is_action_pressed("debug_encounter"):
		# Phase 1 leftover; removed in Phase 4 when real triggers take over.
		Events.encounter_triggered.emit(null, &"debug")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("wait"):
		# Wait: skip the action, the world still ticks (lockdown §2).
		get_viewport().set_input_as_handled()
		_run_tick()
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


## The move rule from design-lockdown.md §2: walkable and unoccupied → step
## and the world ticks; otherwise bump, and a rejected move consumes no
## turn. One special case: stepping into a beckoner's cell is not a move at
## all — it's the deliberate approach that fires a player_initiated
## encounter (lockdown §7).
func _try_player_move(step: Vector2i) -> void:
	var target := _player.grid_pos + step
	var occupant := _enemy_at(target)
	if occupant != null and occupant.data.trigger_type == &"player_initiated" and _immunity_ticks == 0:
		# The step is NOT committed — the player never occupies the enemy's
		# cell (technical plan, Decision 7), which is also what makes the
		# post-flee return position trivial in Phase 4.
		_fire_encounter(occupant)
		return
	if not _is_walkable(target) or occupant != null:
		_player.bump(step)
		return
	_player.step_to(target)
	GameState.grid_position = target
	_run_tick()


## One world tick (plan task 2.4): the player's action already happened, so
## every other actor now acts exactly once, then the trigger dispatcher
## checks the board. No energy or speed system — one action per actor per
## tick is the Architecture Decisions table's turn model.
func _run_tick() -> void:
	_is_ticking = true
	for enemy in _enemies:
		_take_enemy_turn(enemy)
		if _encounter_fired:
			return
	_check_triggers()
	_update_feedback()
	_refresh_status()
	if _encounter_fired:
		# Main is replacing this scene; no point unlocking input.
		return
	# Hold input until the step tweens land (plus a hair), so holding a key
	# advances the world at a readable pace instead of teleporting actors.
	await get_tree().create_timer(GridActor.STEP_TIME + 0.02).timeout
	_is_ticking = false


func _take_enemy_turn(enemy: EnemyActor) -> void:
	var target := enemy.propose_step(_player.grid_pos)
	if target == enemy.grid_pos:
		return
	if target == _player.grid_pos:
		# Only an ambusher may enter the player's cell — and doing so IS its
		# trigger (lockdown §7, enemy_initiated). Anyone else loses the step.
		if enemy.data.trigger_type == &"enemy_initiated" and _immunity_ticks == 0:
			_fire_encounter(enemy)
		return
	if _is_walkable(target) and _enemy_at(target) == null:
		enemy.step_to(target)
	# Blocked proposals are simply lost — the plan's cheap, correct rule for
	# Phase 2 enemies.


## The end-of-tick half of the trigger dispatcher (plan task 2.6). The other
## two trigger types fire mid-tick, at the step attempt that defines them;
## proximity is the only check that waits for the board to settle.
func _check_triggers() -> void:
	if _immunity_ticks > 0:
		# Grace tick after a flee, so leaving an encounter can't chain
		# straight back into it. Phase 4 arms this.
		_immunity_ticks -= 1
		return
	for enemy in _enemies:
		if enemy.data.trigger_type != &"proximity":
			continue
		var delta := enemy.grid_pos - _player.grid_pos
		# 4-way adjacency (Manhattan distance 1) — the lockdown's Decision
		# Log rejects diagonal adjacency as ambiguous.
		if absi(delta.x) + absi(delta.y) == 1:
			_fire_encounter(enemy)
			return


## Hands the encounter to Main via the bus. Main frees this scene in
## response, so nothing may run here afterwards — hence the flag every loop
## checks before continuing.
func _fire_encounter(enemy: EnemyActor) -> void:
	_encounter_fired = true
	Events.encounter_triggered.emit(enemy.data, enemy.data.trigger_type)


func _enemy_at(cell: Vector2i) -> EnemyActor:
	for enemy in _enemies:
		if enemy.grid_pos == cell:
			return enemy
	return null


func _update_feedback() -> void:
	for enemy in _enemies:
		enemy.update_feedback(_player.grid_pos)


func _is_walkable(cell: Vector2i) -> bool:
	var tile := _floor.get_cell_tile_data(cell)
	# Cells outside the painted map have no tile at all — treat as solid.
	return tile != null and bool(tile.get_custom_data("walkable"))


func _refresh_status() -> void:
	_status_label.text = "HP %d/%d   Corruption %d/%d" % [
		GameState.hp, GameState.max_hp,
		GameState.corruption, GameState.CORRUPTION_MAX,
	]
