## GameState — the run's single source of truth (autoload singleton).
##
## What this is: the only data container that survives a mode switch. It holds
## the athlete's stats, corruption, inventory, grid position, the seeded RNG,
## and the run log. Main frees and recreates the Exploration and Encounter
## scenes on every switch, so anything a scene wants to keep must live here —
## everything else is scene-local and disposable by design.
##
## Why it exists: the implementation plan's Architecture Decisions table fixes
## "Cross-mode state = single GameState autoload". One source of truth
## prevents the classic bug where two scenes each keep their own copy of HP
## and they drift apart.
##
## How it connects: every scene reads and writes this singleton directly
## (autoloads are globally visible as `GameState`). It emits nothing and
## listens to nothing — communication between scenes goes through the Events
## signal bus instead.
extends Node

## Locked start values from design-lockdown.md §6 (Run Shape). Phase 9 moves
## tuning numbers into resource files; until then constants keep them in one
## visible place.
const START_MAX_HP := 20
const START_ATK := 5
const START_DEF := 2
const CORRUPTION_MAX := 100

## Sentinel meaning "not spawned yet". The floor's entrance tile is map
## data, so GameState can't know it — Exploration replaces this with the
## map's entrance cell on first load (technical plan, Decision 16).
const NO_POSITION := Vector2i(-1, -1)

var max_hp: int = START_MAX_HP
var hp: int = START_MAX_HP
var corruption: int = 0
var atk: int = START_ATK
var def_stat: int = START_DEF

## Item container. Phases 3-4 put heal items here; empty at run start.
var inventory: Array = []

## The athlete's logical grid cell. This is the truth about where she is —
## sprites and tweens are presentation only (Architecture Decisions:
## "Grid truth").
var grid_position: Vector2i = Vector2i.ZERO

## One seeded generator for every random roll in the run. Seeding through a
## stored int (instead of calling randi() ad hoc everywhere) is what makes
## Phase 6's "replay any run from its seed" possible without a retrofit.
var rng := RandomNumberGenerator.new()
var rng_seed: int = 0

## Per-encounter records (see the plan's Run Log Entry schema). Phase 6
## populates and persists this; it exists now so the field every later phase
## writes to is already part of the state contract.
var run_log: Array = []


func _ready() -> void:
	reset_run()


## Restores the locked start condition: HP 20/20, corruption 0, ATK 5, DEF 2,
## empty inventory, fresh seed. Called once at boot and again by Phase 6's
## "new run" flow.
func reset_run() -> void:
	max_hp = START_MAX_HP
	hp = max_hp
	corruption = 0
	atk = START_ATK
	def_stat = START_DEF
	inventory.clear()
	run_log.clear()
	# "Nowhere yet" — Exploration snaps the player to the floor's entrance
	# tile when it sees this sentinel.
	grid_position = NO_POSITION
	# randi() (unseeded, OS entropy) picks the run's seed; everything after
	# this line must roll through `rng` so the run is reproducible.
	rng_seed = randi()
	rng.seed = rng_seed


## One d100 roll, 1-100 inclusive. All of design-lockdown.md's d100 checks
## (Flee, Resist, Redirect) must come through here so they draw from the
## run's seeded stream.
func roll_d100() -> int:
	return rng.randi_range(1, 100)
