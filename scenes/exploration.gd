## Exploration — Mode 1: the grid the athlete walks.
##
## What this is: the exploration scene. It renders whichever floor plan
## the run owns — FloorGenerator's rooms-and-corridors, or the hand-made
## ASCII map parsed into the identical plan shape when the regression
## toggle is on (Phase 8, Decision 40) — owns the player actor, and
## validates every move attempt: a keypress becomes a committed step, a
## bump, a walk-over pickup, the win, or an encounter trigger, and this
## script is the single place that decides which. The turn scheduler and
## trigger dispatcher also live here, per the plan: "the scheduler lives
## in Exploration, not in GameState".
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

## The hand-made regression floor (technical plan, Decisions 13 and 41 —
## kept permanently: generation bugs can never hide gameplay bugs here).
## One character per 16px tile, 40 columns x 22 rows: '#' wall, '.' floor,
## '@' entrance, 'X' exit, 'H' hostile spawn, 'B' beckoner spawn (all four
## markers sit on floor tiles). Layout: entrance room left, corridor to a
## center room (the hostile's patrol ground), corridor to the exit room
## right, and a dead-end alcove below the entrance room where the beckoner
## waits — off the path, so approaching it is always a deliberate choice.
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

## Read from the run's floor plan in _ready.
var _entrance_cell := Vector2i.ZERO
var _exit_cell := Vector2i.ZERO

## Floor-item visuals by cell, so a pickup can remove exactly its quad.
var _item_nodes: Dictionary = {}

## Every living enemy on the grid, in spawn order (which is also their turn
## order within a tick).
var _enemies: Array[EnemyActor] = []

## True while a tick resolves; input is ignored so a held key can't outrun
## the world's animations.
var _is_ticking := false
## Set the instant this scene hands control to Main — a trigger fired or
## the run ended on the exit tile. Main is already replacing the scene, so
## every loop checks this and stops; nothing may act past that moment.
var _scene_frozen := false
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
	if GameState.floor_plan.is_empty():
		GameState.floor_plan = _create_floor_plan()
	_entrance_cell = GameState.floor_plan["entrance_cell"]
	_exit_cell = GameState.floor_plan["exit_cell"]
	_build_from_plan(GameState.floor_plan)
	if not GameState.roster_initialized:
		_seed_rosters(GameState.floor_plan)
	_spawn_player()
	_spawn_enemies()
	_spawn_items()
	# Collect the one-shot immunity grant from a fled/resisted encounter
	# (lockdown §3). The counter itself stays scene-local bookkeeping.
	_immunity_ticks = GameState.pending_immunity_ticks
	GameState.pending_immunity_ticks = 0
	_update_feedback()
	_refresh_status()


## The run's floor, decided once (Decision 40): generated from the run
## seed, unless the regression toggle asks for the hand-made map. A
## generator failure (20 bad attempts — the Decision 45 tripwire) also
## lands on the hand-made floor rather than stranding the player.
func _create_floor_plan() -> Dictionary:
	if GameState.use_handmade_floor:
		return _handmade_plan()
	var plan := FloorGenerator.generate(GameState.rng_seed)
	if plan.is_empty():
		return _handmade_plan()
	return plan


## Parses the ASCII map into the SAME plan shape the generator produces,
## so everything downstream has exactly one code path (Decision 40).
func _handmade_plan() -> Dictionary:
	var cells := {}
	var plan := {
		"cells": cells,
		"entrance_cell": Vector2i.ZERO,
		"exit_cell": Vector2i.ZERO,
		"enemy_spawns": [] as Array[Dictionary],
		"item_spawns": [] as Array[Dictionary],
	}
	for y in FLOOR_MAP.size():
		var row := FLOOR_MAP[y]
		for x in row.length():
			var cell := Vector2i(x, y)
			match row[x]:
				"#":
					continue
				"@":
					plan["entrance_cell"] = cell
				"X":
					plan["exit_cell"] = cell
				"H":
					plan["enemy_spawns"].append({"data": HOSTILE_DATA, "cell": cell})
				"B":
					plan["enemy_spawns"].append({"data": BECKONER_DATA, "cell": cell})
			cells[cell] = true
	return plan


## Renders a floor plan into TileMapLayer cells. Walkability still lives on
## the tileset's "walkable" custom data layer (plan task 2.1) — the plan
## only says which cells are carved.
func _build_from_plan(plan: Dictionary) -> void:
	var cells: Dictionary = plan["cells"]
	for y in FloorGenerator.HEIGHT:
		for x in FloorGenerator.WIDTH:
			var cell := Vector2i(x, y)
			if cells.has(cell):
				_floor.set_cell(cell, TILE_SOURCE, TILE_EXIT if cell == _exit_cell else TILE_FLOOR)
			else:
				_floor.set_cell(cell, TILE_SOURCE, TILE_WALL)


func _spawn_player() -> void:
	if GameState.grid_position == GameState.NO_POSITION:
		# Fresh run: the entrance tile is map data, so GameState left the
		# spawn cell to us (technical plan, Decision 16).
		GameState.grid_position = _entrance_cell
	_player.place_at(GameState.grid_position)
	_player.refresh_corruption_visual()


## Builds the run's enemy and item rosters from the floor plan — once per
## run. From here on the GameState rosters are the truth about what's left
## and where; this scene only renders them (task 4.2 / Phase 8 task 8.3).
func _seed_rosters(plan: Dictionary) -> void:
	GameState.enemy_roster.clear()
	for spawn: Dictionary in plan["enemy_spawns"]:
		GameState.enemy_roster.append({"data": spawn["data"], "cell": spawn["cell"]})
	GameState.item_roster.clear()
	for spawn: Dictionary in plan["item_spawns"]:
		GameState.item_roster.append({"data": spawn["data"], "cell": spawn["cell"]})
	GameState.roster_initialized = true


## Instantiates one EnemyActor per roster entry. A defeated enemy is simply
## no longer in the roster, so it doesn't come back after an encounter.
## _enemies keeps roster order — _fire_encounter relies on the indices
## matching.
func _spawn_enemies() -> void:
	for entry in GameState.enemy_roster:
		var enemy: EnemyActor = ENEMY_SCENE.instantiate()
		# Data must be set before add_child so the actor's _ready sees it.
		enemy.data = entry["data"]
		_actors.add_child(enemy)
		enemy.place_at(entry["cell"])
		_enemies.append(enemy)


## Renders every item still in the roster as a small quad on its cell.
func _spawn_items() -> void:
	for entry: Dictionary in GameState.item_roster:
		var marker := ColorRect.new()
		marker.size = Vector2(8, 8)
		marker.position = Vector2(entry["cell"] * GridActor.TILE_SIZE) + Vector2(4, 4)
		marker.color = Color(0.55, 0.9, 0.6)
		_actors.add_child(marker)
		_item_nodes[entry["cell"]] = marker


## Walk-over pickup (lockdown §2: "items pick up on walk-over"). Removes
## the roster entry and its quad, adds the ItemData to inventory.
func _try_pickup(cell: Vector2i) -> void:
	for i in GameState.item_roster.size():
		if GameState.item_roster[i]["cell"] != cell:
			continue
		GameState.inventory.append(GameState.item_roster[i]["data"])
		GameState.item_roster.remove_at(i)
		if _item_nodes.has(cell):
			_item_nodes[cell].queue_free()
			_item_nodes.erase(cell)
		# The five-tone set has no pickup slot; confirm is the
		# acknowledgment tone (Decision 44).
		Sfx.play(&"confirm")
		_refresh_status()
		return


func _unhandled_input(event: InputEvent) -> void:
	if _is_ticking or _scene_frozen:
		return
	if event.is_action_pressed("debug_corrupt"):
		# Test lever for the corruption arc (Decision 30): current content
		# can't reach the bands until Phase 9's content pass.
		GameState.add_corruption(10)
		_player.refresh_corruption_visual()
		_refresh_status()
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
		Sfx.play(&"bump")
		return
	var departed := _player.grid_pos
	_player.step_to(target)
	Sfx.play(&"move")
	_spawn_step_puff(departed)
	GameState.grid_position = target
	_try_pickup(target)
	if target == _exit_cell:
		# Win condition (lockdown §6): stepping onto the exit ends the run.
		# No tick — the world stops mattering the moment she's out.
		_scene_frozen = true
		GameState.end_run(&"win")
		return
	_run_tick()


## One world tick (plan task 2.4): the player's action already happened, so
## every other actor now acts exactly once, then the trigger dispatcher
## checks the board. No energy or speed system — one action per actor per
## tick is the Architecture Decisions table's turn model.
func _run_tick() -> void:
	_is_ticking = true
	for enemy in _enemies:
		_take_enemy_turn(enemy)
		if _scene_frozen:
			return
	_check_triggers()
	_update_feedback()
	_refresh_status()
	if _scene_frozen:
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
	_scene_frozen = true
	# Persist live positions so the grid restores exactly as it stood
	# (_enemies keeps roster order, so indices line up), and record who's
	# engaged so Main can apply the outcome to the right entry.
	for i in _enemies.size():
		GameState.enemy_roster[i]["cell"] = _enemies[i].grid_pos
	GameState.engaged_enemy_index = _enemies.find(enemy)
	Events.encounter_triggered.emit(enemy.data, enemy.data.trigger_type)


func _enemy_at(cell: Vector2i) -> EnemyActor:
	for enemy in _enemies:
		if enemy.grid_pos == cell:
			return enemy
	return null


## A footstep trace (plan task 7.2): a small quad at the departed cell that
## fades and shrinks. Fire-and-forget presentation; it frees itself.
func _spawn_step_puff(cell: Vector2i) -> void:
	var puff := ColorRect.new()
	puff.size = Vector2(6, 6)
	puff.position = Vector2(cell * GridActor.TILE_SIZE) + Vector2(5, 5)
	puff.color = Color(0.9, 0.9, 1.0, 0.3)
	_actors.add_child(puff)
	var tween := puff.create_tween()
	tween.set_parallel()
	tween.tween_property(puff, "color:a", 0.0, 0.25)
	tween.tween_property(puff, "size", Vector2(2, 2), 0.25)
	tween.tween_property(puff, "position", puff.position + Vector2(2, 2), 0.25)
	tween.chain().tween_callback(puff.queue_free)


func _update_feedback() -> void:
	for enemy in _enemies:
		enemy.update_feedback(_player.grid_pos)


func _is_walkable(cell: Vector2i) -> bool:
	var tile := _floor.get_cell_tile_data(cell)
	# Cells outside the painted map have no tile at all — treat as solid.
	return tile != null and bool(tile.get_custom_data("walkable"))


func _refresh_status() -> void:
	# ATK/DEF are stated because corruption trades them (plan task 5.2).
	_status_label.text = "HP %d/%d   ATK %d  DEF %d   Corruption %d/%d   Items %d" % [
		GameState.hp, GameState.max_hp, GameState.atk, GameState.def_stat,
		GameState.corruption, GameState.CORRUPTION_MAX,
		GameState.inventory.size(),
	]
