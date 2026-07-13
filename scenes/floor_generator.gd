## FloorGenerator — rooms-and-corridors floors as a pure function of the
## run seed.
##
## What this is: the plan's simplest-that-works algorithm (Phase 8 task 1):
## place 5–8 non-overlapping rectangular rooms, connect them in sequence
## with L-corridors, populate, validate with a flood fill, retry on
## failure. No BSP, no cellular automata — those are post-PoC upgrades.
##
## Why it uses its own RNG: the live gameplay RNG (GameState.rng) advances
## with every enemy step, so deriving the floor from it would make the
## floor depend on WHEN it was generated. A dedicated generator seeded
## with the same run seed keeps the floor and the gameplay rolls
## independently deterministic — type a seed from the end screen and you
## get the same floor, every time (technical plan, Decision 40).
##
## How it connects: Exploration calls generate() once per run and stores
## the returned plan in GameState.floor_plan. The plan dictionary is the
## only contract: cells (Dictionary keyed by Vector2i), entrance_cell,
## exit_cell, enemy_spawns and item_spawns ({"data": Resource, "cell":
## Vector2i}). The hand-made regression floor is parsed into the same
## shape, so nothing downstream knows which source it came from.
##
## The same algorithm is mirrored in the repo's technical-plan notes and
## was hammered across 2000 Python-mirrored seeds: every one validated on
## the first attempt, so the retry loop is a tripwire, not a path.
class_name FloorGenerator
extends RefCounted

const WIDTH := 40
const HEIGHT := 22
## A hostile may not spawn closer than this (Manhattan) to the entrance —
## the plan's "enemy spawns at minimum distance from player spawn".
const MIN_HOSTILE_DISTANCE := 8
const MAX_FLOOR_ATTEMPTS := 20

const BECKONER_DATA := preload("res://resources/enemies/test_beckoner.tres")

## Who roams the floor (Phase 9, Decision 49): the roamer slots draw from
## this weighted table. The aggressive shadow stays the most common read;
## the Grasping Veil is intimate but enemy_initiated, so the ambush
## seduction hunts like a threat (Decision 48). Beckoners are not here —
## they get their own carved alcoves.
const ROAMER_TABLE: Array[Dictionary] = [
	{"data": preload("res://resources/enemies/test_hostile.tres"), "weight": 3.0},
	{"data": preload("res://resources/enemies/test_receptive.tres"), "weight": 2.0},
	{"data": preload("res://resources/enemies/thorned_warden.tres"), "weight": 2.0},
	{"data": preload("res://resources/enemies/grasping_veil.tres"), "weight": 2.0},
]

## The plan's "small weighted table" of floor items. Heal outnumbers the
## corruption pressure-valve two to one (Decision 44/49).
const ITEM_TABLE: Array[Dictionary] = [
	{"data": preload("res://resources/items/heal_item.tres"), "weight": 2.0},
	{"data": preload("res://resources/items/cleanse_item.tres"), "weight": 1.0},
]


## Produces a valid floor plan for the seed, or an empty Dictionary after
## MAX_FLOOR_ATTEMPTS failures (the caller falls back to the hand-made
## floor). Failed attempts log their seed so a bad floor can be studied.
static func generate(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for attempt in MAX_FLOOR_ATTEMPTS:
		var plan := _attempt(rng)
		if not plan.is_empty():
			return plan
		push_warning("Floor attempt %d failed for seed %d; regenerating." % [attempt + 1, seed_value])
	push_error("No valid floor in %d attempts for seed %d." % [MAX_FLOOR_ATTEMPTS, seed_value])
	return {}


static func _attempt(rng: RandomNumberGenerator) -> Dictionary:
	# --- Rooms: random rectangles, 1-cell gap enforced via grow(1). ---
	var rooms: Array[Rect2i] = []
	var occupied: Array[Rect2i] = []
	for i in rng.randi_range(5, 8):
		for t in 30:
			var size := Vector2i(rng.randi_range(4, 8), rng.randi_range(3, 5))
			var pos := Vector2i(
				rng.randi_range(1, WIDTH - size.x - 1),
				rng.randi_range(1, HEIGHT - size.y - 1))
			var room := Rect2i(pos, size)
			if not _overlaps_any(room, occupied):
				rooms.append(room)
				occupied.append(room)
				break
	if rooms.size() < 5:
		return {}

	# --- Carve rooms, then L-corridors between consecutive centers. ---
	var cells := {}
	for room in rooms:
		_carve_rect(cells, room)
	for i in range(1, rooms.size()):
		_carve_corridor(cells, rooms[i - 1].get_center(), rooms[i].get_center(), rng.randf() < 0.5)

	var entrance: Vector2i = rooms[0].get_center()
	var exit_cell := Vector2i(-1, -1)
	for t in 30:
		var candidate := _random_cell(rooms[rooms.size() - 1], rng)
		if candidate != entrance:
			exit_cell = candidate
			break
	if exit_cell == Vector2i(-1, -1):
		return {}

	# --- Beckoners: purpose-carved dead-end alcoves off the earlier half
	# of the chain (Decision 43). The player must SEE the detour and
	# choose it — placement is the emotional framing.
	var enemy_spawns: Array[Dictionary] = []
	for b in rng.randi_range(1, 2):
		if not _place_beckoner(rng, rooms, occupied, cells, enemy_spawns):
			# Fallback: an early room's corner. Less flavorful, never fatal.
			var room := rooms[rng.randi_range(0, maxi(_half(rooms.size()) - 1, 0))]
			enemy_spawns.append({"data": BECKONER_DATA, "cell": room.position})

	# --- Roamers: later rooms, far from the spawn, drawn from the
	# weighted table. ---
	var beckoner_count := enemy_spawns.size()
	var roamer_count := maxi(rng.randi_range(3, 5) - beckoner_count, 2)
	for r in roamer_count:
		var placed := false
		for t in 30:
			# Prefer the later half of the chain; relax if it won't fit.
			var lo := _half(rooms.size()) if t < 15 else 1
			var room := rooms[rng.randi_range(lo, rooms.size() - 1)]
			var cell := _random_cell(room, rng)
			var distance := absi(cell.x - entrance.x) + absi(cell.y - entrance.y)
			if distance < MIN_HOSTILE_DISTANCE:
				continue
			if _cell_taken(cell, entrance, exit_cell, enemy_spawns, []):
				continue
			enemy_spawns.append({"data": _roll_table(ROAMER_TABLE, rng), "cell": cell})
			placed = true
			break
		if not placed:
			return {}

	# --- Items: 1–2 rolls on the weighted table, anywhere free. ---
	var item_spawns: Array[Dictionary] = []
	for i in rng.randi_range(1, 2):
		for t in 30:
			var room := rooms[rng.randi_range(0, rooms.size() - 1)]
			var cell := _random_cell(room, rng)
			if _cell_taken(cell, entrance, exit_cell, enemy_spawns, item_spawns):
				continue
			item_spawns.append({"data": _roll_table(ITEM_TABLE, rng), "cell": cell})
			break

	# --- Validity: everything the run needs must be reachable on foot. ---
	var reachable := _flood_fill(cells, entrance)
	var must_reach: Array[Vector2i] = [exit_cell]
	for spawn in enemy_spawns:
		must_reach.append(spawn["cell"])
	for spawn in item_spawns:
		must_reach.append(spawn["cell"])
	for cell in must_reach:
		if not reachable.has(cell):
			return {}

	return {
		"cells": cells,
		"entrance_cell": entrance,
		"exit_cell": exit_cell,
		"enemy_spawns": enemy_spawns,
		"item_spawns": item_spawns,
	}


## Tries to attach a 3x3 alcove (with a 1-cell bridge) to a room in the
## earlier half of the chain, and puts a beckoner at its center. The
## grow(1) overlap test can't reject the host: the bridge gap keeps the
## grown alcove exactly clear of it.
static func _place_beckoner(
		rng: RandomNumberGenerator,
		rooms: Array[Rect2i],
		occupied: Array[Rect2i],
		cells: Dictionary,
		enemy_spawns: Array[Dictionary]) -> bool:
	for t in 20:
		var host := rooms[rng.randi_range(0, maxi(_half(rooms.size()) - 1, 0))]
		var alcove: Rect2i
		var bridge: Vector2i
		match rng.randi_range(0, 3):
			0:  # east
				alcove = Rect2i(host.end.x + 1, host.position.y + _half(host.size.y) - 1, 3, 3)
				bridge = Vector2i(host.end.x, alcove.position.y + 1)
			1:  # west
				alcove = Rect2i(host.position.x - 4, host.position.y + _half(host.size.y) - 1, 3, 3)
				bridge = Vector2i(host.position.x - 1, alcove.position.y + 1)
			2:  # south
				alcove = Rect2i(host.position.x + _half(host.size.x) - 1, host.end.y + 1, 3, 3)
				bridge = Vector2i(alcove.position.x + 1, host.end.y)
			_:  # north
				alcove = Rect2i(host.position.x + _half(host.size.x) - 1, host.position.y - 4, 3, 3)
				bridge = Vector2i(alcove.position.x + 1, host.position.y - 1)
		if alcove.position.x < 1 or alcove.position.y < 1:
			continue
		if alcove.end.x > WIDTH - 1 or alcove.end.y > HEIGHT - 1:
			continue
		if _overlaps_any(alcove, occupied):
			continue
		_carve_rect(cells, alcove)
		cells[bridge] = true
		occupied.append(alcove)
		enemy_spawns.append({"data": BECKONER_DATA, "cell": alcove.get_center()})
		return true
	return false


## Integer halving without the editor's integer-division warning on
## every centering expression.
static func _half(n: int) -> int:
	return n >> 1


static func _overlaps_any(rect: Rect2i, occupied: Array[Rect2i]) -> bool:
	var grown := rect.grow(1)
	for other in occupied:
		if grown.intersects(other):
			return true
	return false


static func _carve_rect(cells: Dictionary, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			cells[Vector2i(x, y)] = true


## An L-corridor between two cells: one leg, then the other, pivot corner
## chosen by `horizontal_first`.
static func _carve_corridor(
		cells: Dictionary, from: Vector2i, to: Vector2i, horizontal_first: bool) -> void:
	if horizontal_first:
		for x in range(mini(from.x, to.x), maxi(from.x, to.x) + 1):
			cells[Vector2i(x, from.y)] = true
		for y in range(mini(from.y, to.y), maxi(from.y, to.y) + 1):
			cells[Vector2i(to.x, y)] = true
	else:
		for y in range(mini(from.y, to.y), maxi(from.y, to.y) + 1):
			cells[Vector2i(from.x, y)] = true
		for x in range(mini(from.x, to.x), maxi(from.x, to.x) + 1):
			cells[Vector2i(x, to.y)] = true


static func _random_cell(room: Rect2i, rng: RandomNumberGenerator) -> Vector2i:
	return Vector2i(
		rng.randi_range(room.position.x, room.end.x - 1),
		rng.randi_range(room.position.y, room.end.y - 1))


static func _cell_taken(
		cell: Vector2i,
		entrance: Vector2i,
		exit_cell: Vector2i,
		enemy_spawns: Array[Dictionary],
		item_spawns: Array[Dictionary]) -> bool:
	if cell == entrance or cell == exit_cell:
		return true
	for spawn in enemy_spawns:
		if spawn["cell"] == cell:
			return true
	for spawn in item_spawns:
		if spawn["cell"] == cell:
			return true
	return false


## One weighted pick from a table of {"data": Resource, "weight": float}
## rows. Shared by the roamer and item tables.
static func _roll_table(table: Array[Dictionary], rng: RandomNumberGenerator) -> Resource:
	var total := 0.0
	for row in table:
		total += row["weight"]
	var roll := rng.randf() * total
	for row in table:
		roll -= row["weight"]
		if roll <= 0.0:
			return row["data"]
	return table[table.size() - 1]["data"]


## 4-way flood fill over carved cells; returns the reachable set.
static func _flood_fill(cells: Dictionary, from: Vector2i) -> Dictionary:
	# The array literal must be typed: iterating a plain literal makes
	# `dir` a Variant, and `current + dir` can't infer a type from that.
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_back()
		for dir in directions:
			var next := current + dir
			if cells.has(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen
