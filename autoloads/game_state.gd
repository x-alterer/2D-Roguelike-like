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

## Where finished runs are recorded (Phase 5, task 5.4 — the seam the Bad
## End system and Phase 6's behavioral profile will consume).
const RUN_HISTORY_PATH := "user://run_history.tres"

var max_hp: int = START_MAX_HP
var hp: int = START_MAX_HP
## Never write this directly — call add_corruption(), which runs the band
## engine (stat shifts, verb mutations, loss condition 2).
var corruption: int = 0
var atk: int = START_ATK
var def_stat: int = START_DEF

## The active character's corruption arc. Swapping in a different track
## file IS how a second character gets a different flaw — no code changes
## (plan task 5.6).
var corruption_track: CorruptionTrack = preload("res://resources/corruption/athlete_track.tres")

## True once a win or either loss condition ended the run; blocks
## double-ending when, say, Overwhelm's HP cost kills at max corruption.
var run_over := false
## Why the run ended ("win", "death", "corruption") — set by end_run, read
## by the end screen, consumed by record_run_end.
var run_end_cause: StringName = &""
## Guards the once-per-run disk write (Decision 32).
var run_recorded := false

## The athlete's items: an array of ItemData resources. Empty at run start;
## encounters grant into it (Yield boons) and consume from it (UseItem).
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

## This run's floor (Phase 8, Decision 40): the plan dictionary produced by
## FloorGenerator (or parsed from the hand-made map). Generated once per
## run on exploration's first load and re-rendered on every load after —
## it can't be re-derived later because the gameplay RNG advances during
## play. Empty = not generated yet.
var floor_plan: Dictionary = {}

## Session-scoped regression switch (Decision 41): true renders the
## hand-made ASCII floor instead of generating. Toggled on the title
## screen; deliberately NOT reset per run — it's a testing mode, not run
## state.
var use_handmade_floor := false

## Exploration scene-restore data (Phase 4, task 4.2): which enemies remain
## on the grid and where. Entries: {"data": EnemyData, "cell": Vector2i}.
## Exploration seeds it from the floor plan once per run, re-reads it on
## every load, and syncs live positions into it when an encounter fires;
## Main removes an entry when an encounter outcome kills or resolves that
## enemy.
var enemy_roster: Array = []
var roster_initialized := false

## Items still lying on the floor: {"data": ItemData, "cell": Vector2i}.
## Same lifecycle as the enemy roster; exploration removes an entry on
## walk-over pickup (Phase 8, task 8.3).
var item_roster: Array = []

## Index into enemy_roster of the enemy currently in an encounter; -1 when
## none. Written by Exploration at trigger time, consumed by Main at
## resolution time so the outcome lands on the right enemy.
var engaged_enemy_index := -1

## One-shot transfer armed by Main after a fled/resisted outcome; the next
## Exploration load reads it into its tick-local immunity counter (lockdown
## §3: "one tick of encounter immunity", technical plan Decision 8).
var pending_immunity_ticks := 0

## Verbs whose mutation has been announced this run (Phase 7, Decision 38).
## Run-scoped because the flash must fire once per run, and the menu that
## first shows the mutation may belong to a later encounter than the one
## where the band crossed.
var announced_mutations: Array[StringName] = []


func _ready() -> void:
	reset_run()


## Restores the locked start condition: HP 20/20, corruption 0, ATK 5, DEF 2,
## empty inventory, fresh seed. Called at boot and by every "new run".
## Pass a non-negative `fixed_seed` to replay that seed's floor and rolls
## (Phase 8, Decision 42); -1 means roll a fresh one.
func reset_run(fixed_seed: int = -1) -> void:
	max_hp = START_MAX_HP
	hp = max_hp
	corruption = 0
	atk = START_ATK
	def_stat = START_DEF
	inventory.clear()
	run_log.clear()
	floor_plan = {}
	enemy_roster.clear()
	item_roster.clear()
	roster_initialized = false
	engaged_enemy_index = -1
	pending_immunity_ticks = 0
	run_over = false
	run_end_cause = &""
	run_recorded = false
	announced_mutations.clear()
	# "Nowhere yet" — Exploration snaps the player to the floor's entrance
	# tile when it sees this sentinel.
	grid_position = NO_POSITION
	# randi() (unseeded, OS entropy) picks fresh seeds; everything after
	# this line must roll through `rng` so the run is reproducible.
	rng_seed = fixed_seed if fixed_seed >= 0 else randi()
	rng.seed = rng_seed


## One d100 roll, 1-100 inclusive. All of design-lockdown.md's d100 checks
## (Flee, Resist, Redirect) must come through here so they draw from the
## run's seeded stream.
func roll_d100() -> int:
	return rng.randi_range(1, 100)


## Which corruption band the athlete is in: the number of thresholds she
## has met. With the lockdown's [25, 50, 75, 100]: 0-24 → 0, 25-49 → 1,
## 50-74 → 2, 75-99 → 3, 100 → 4 (the end).
func corruption_band() -> int:
	var band := 0
	for threshold in corruption_track.band_thresholds:
		if corruption >= threshold:
			band += 1
	return band


## The band engine (Phase 5, task 5.1). The only legal way to raise
## corruption: applies each crossed band's stat trade, emits the crossing
## event, and fires loss condition 2 at the final threshold. Multiple bands
## crossed by one large gain each fire in order.
func add_corruption(amount: int) -> void:
	if amount <= 0 or run_over:
		return
	var old_band := corruption_band()
	corruption = mini(corruption + amount, CORRUPTION_MAX)
	# The gain itself is one of the five feedback events (plan task 7.5) —
	# sounded here so every source of corruption pays audibly.
	Sfx.play(&"corruption")
	var new_band := corruption_band()
	for band in range(old_band + 1, new_band + 1):
		_cross_band(band)
	if corruption >= CORRUPTION_MAX and not run_over:
		end_run(&"corruption")


## Applies one band crossing: the stat trade (power purchased with self —
## lockdown §5's ATK up, max HP down) and the crossing event. `band` is the
## band being entered; the track arrays are indexed by the threshold just
## crossed, which is band - 1 (Decision 24).
func _cross_band(band: int) -> void:
	var idx := band - 1
	if idx < corruption_track.stat_modifiers_per_band.size():
		var mods: Dictionary = corruption_track.stat_modifiers_per_band[idx]
		atk += mods.get("atk", 0)
		max_hp += mods.get("max_hp", 0)
		max_hp = maxi(max_hp, 1)
		hp = mini(hp, max_hp)
	var text := ""
	if idx < corruption_track.band_crossing_text.size():
		text = corruption_track.band_crossing_text[idx]
	Events.corruption_band_crossed.emit(band, text)


## The band engine's downward mirror (Phase 9, Decision 47): the
## corruption-reduce item lowers the number and symmetrically reverses any
## bands left behind — stat trades undo, and verb overrides un-mutate on
## their own because they're computed live from the current band. Quiet by
## design: no interstitial, no signal; the item's narration carries it.
func remove_corruption(amount: int) -> void:
	if amount <= 0 or run_over:
		return
	var old_band := corruption_band()
	corruption = maxi(corruption - amount, 0)
	var new_band := corruption_band()
	for band in range(old_band, new_band, -1):
		_uncross_band(band)


func _uncross_band(band: int) -> void:
	var idx := band - 1
	if idx < corruption_track.stat_modifiers_per_band.size():
		var mods: Dictionary = corruption_track.stat_modifiers_per_band[idx]
		atk -= mods.get("atk", 0)
		max_hp -= mods.get("max_hp", 0)
		max_hp = maxi(max_hp, 1)
		hp = mini(hp, max_hp)


## Every verb substitution currently in force: the merge of all reached
## bands' overrides (Decision 24 — cumulative, so band 3 keeps band 2's
## mutation). The encounter scene renders and dispatches through this.
func corruption_verb_overrides() -> Dictionary:
	var merged := {}
	var bands_reached := mini(corruption_band(), corruption_track.verb_overrides_per_band.size())
	for i in bands_reached:
		merged.merge(corruption_track.verb_overrides_per_band[i], true)
	return merged


## Ends the run exactly once: marks it over and announces it. `cause` is
## "win", "death", or "corruption". The disk write is deliberately NOT here
## — it happens later, in the end screen's _ready (record_run_end), so the
## encounter that ended the run has time to append its own record to the
## run log first (Decision 32).
func end_run(cause: StringName) -> void:
	if run_over:
		return
	run_over = true
	run_end_cause = cause
	Events.run_ended.emit(cause)


## Appends this run's record to user://run_history.tres, once: who, how it
## ended, corruption, the seed (for replay debugging), the full verb
## history, and the plan's aggregates (Phase 6, task 3). The Bad End
## system and the end screen's history block read from here.
func record_run_end() -> void:
	if run_recorded:
		return
	run_recorded = true
	var verb_counts := {}
	var corruption_curve: Array[int] = []
	for entry: Dictionary in run_log:
		corruption_curve.append(entry.get("corruption_delta", 0))
		for verb: StringName in entry.get("verbs_chosen", []):
			verb_counts[verb] = verb_counts.get(verb, 0) + 1
	var history := load_run_history()
	history.runs.append({
		"character": "athlete",
		"cause": run_end_cause,
		"corruption": corruption,
		"rng_seed": rng_seed,
		"encounters": run_log.size(),
		"verb_counts": verb_counts,
		"corruption_curve": corruption_curve,
		"run_log": run_log.duplicate(true),
	})
	var err := ResourceSaver.save(history, RUN_HISTORY_PATH)
	if err != OK:
		push_error("Could not save run history (error %d)." % err)


## The RunHistory from disk, or a fresh empty one on first launch. Callers
## must not assume the file exists.
func load_run_history() -> RunHistory:
	var history: RunHistory = null
	if ResourceLoader.exists(RUN_HISTORY_PATH):
		history = ResourceLoader.load(RUN_HISTORY_PATH) as RunHistory
	if history == null:
		history = RunHistory.new()
	return history
