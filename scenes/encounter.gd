## Encounter — Mode 2: the CHOOSE loop.
##
## What this is: the encounter screen. Enemy on top, athlete's status
## bottom-left, verb menu bottom-right — Pokémon layout, deliberately
## uninnovative (plan task 3.1). The menu renders whatever the enemy's
## verb_set lists; every verb maps to a resolution function through one
## dictionary, so this scene never knows what "Fight" means thematically
## and never switches on encounter flavor (plan task 3.5). Adding a verb
## anywhere in the game = one function here + one entry in a data file.
##
## Why the strict alternation matters: player chooses → resolution text →
## enemy acts (if the encounter continues) → menu returns. Every rule from
## design-lockdown.md §3/§4 resolves inside one of the _verb_* functions
## below, so the lockdown can be checked against this file line by line.
##
## How it connects: Main calls setup() with the triggering enemy's data
## before adding this scene (Phase 4). Exits go out through
## Events.encounter_resolved with the full result payload, or
## Events.player_died. Run encounter.tscn directly (F6) to test standalone:
## a test enemy loads, one heal item is seeded, and E swaps between the
## combat and intimate test enemies (technical plan, Decision 21).
extends Node2D

## Every enemy the standalone test mode can load: the 60-second script's
## hostile, a talk-receptive combat enemy (Talk's peaceful branch and the
## Fight-vs-receptive corruption trigger are untestable without one), the
## intimate beckoner, and the dummy "strange" flavor that proves unknown
## variants run without rewiring (Phase 4.5 DoD).
const TEST_ENEMIES: Array[Resource] = [
	preload("res://resources/enemies/test_hostile.tres"),
	preload("res://resources/enemies/test_receptive.tres"),
	preload("res://resources/enemies/test_beckoner.tres"),
	preload("res://resources/enemies/test_dummy.tres"),
]
const HEAL_ITEM := preload("res://resources/items/heal_item.tres")

## Which TEST_ENEMIES entry an F6 standalone run loads. Static so it
## survives the scene reload that the E cycle key performs.
static var _standalone_test_index := 0

## The enemy this encounter is about — injected by Main via setup(), or a
## test resource when absent.
var data: EnemyData
## How the encounter started (lockdown §7). Decides the opening beat:
## you approached → you act first; it reached you → it acts first.
var trigger_type: StringName = &"proximity"

var _enemy_hp := 0
var _menu_index := 0
## Intimate 3-stage sequence position (lockdown §4). Encounter-local by
## design: walking away and coming back starts the seduction over.
var _stage := 0
## Progress through a receptive enemy's dialogue_lines (Decision 9).
var _dialogue_index := 0
## Verb name -> resolution Callable. THE extension point: the menu looks
## verbs up here and calls blindly (plan task 3.5).
var _verb_handlers: Dictionary = {}

## Result payload bookkeeping (plan task 3.7).
var _verbs_chosen: Array[StringName] = []
var _turns_elapsed := 0
var _corruption_delta := 0

## True once an exit path fired; locks the menu. In the real game Main
## frees this scene moments later; standalone it just sits, showing the
## outcome.
var _done := false
var _standalone := false

@onready var _enemy_rect: ColorRect = $EnemyRect
@onready var _enemy_label: Label = $EnemyLabel
@onready var _narration: Label = $NarrationLabel
@onready var _status_label: Label = $StatusLabel
@onready var _menu: VBoxContainer = $VerbMenu


## Called by Main before this scene enters the tree (Phase 4 wires it).
func setup(enemy_data: EnemyData, p_trigger_type: StringName) -> void:
	data = enemy_data
	trigger_type = p_trigger_type


func _ready() -> void:
	_standalone = get_tree().current_scene == self
	if data == null:
		# F6 standalone run (nobody called setup): load a test enemy
		# (Decision 21). Doubles as a safety net against a null injection.
		data = TEST_ENEMIES[_standalone_test_index if _standalone else 0]
		trigger_type = data.trigger_type
		if _standalone and GameState.inventory.is_empty():
			GameState.inventory.append(HEAL_ITEM)

	_verb_handlers = {
		&"Fight": _verb_fight,
		&"Talk": _verb_talk,
		&"Flee": _verb_flee,
		&"UseItem": _verb_use_item,
		&"Resist": _verb_resist,
		&"Yield": _verb_yield,
		&"Redirect": _verb_redirect,
		&"Intimidate": _verb_intimidate,
		&"Overwhelm": _verb_overwhelm,
	}
	# Corruption can cross a band mid-encounter; the menu must mutate the
	# moment it happens, not on the next encounter (plan task 5.2).
	Events.corruption_band_crossed.connect(_on_band_crossed)

	_enemy_hp = data.hp
	_enemy_rect.color = data.color
	_build_menu()
	_refresh_status()

	# Opening framing (lockdown §7, Decision 17). This is the emotional
	# difference between trigger types made mechanical: an ambush costs you
	# the first beat, an approach leaves you in control.
	if trigger_type == &"player_initiated":
		_narrate("You approached %s." % data.enemy_name)
	else:
		_narrate("%s reached you first." % data.enemy_name)
		_enemy_acts()


func _unhandled_input(event: InputEvent) -> void:
	if _standalone and event.is_action_pressed("debug_encounter"):
		# Cycle to the next test enemy and restart clean (Decision 21).
		_standalone_test_index = (_standalone_test_index + 1) % TEST_ENEMIES.size()
		GameState.reset_run()
		get_tree().reload_current_scene()
		return
	if _standalone and event.is_action_pressed("debug_corrupt"):
		# Test lever for the corruption arc (Decision 30): current content
		# can't reach the bands until Phase 9's content pass.
		_apply_corruption(10)
		get_viewport().set_input_as_handled()
		return
	if _done:
		return
	if event.is_action_pressed("move_up"):
		_menu_index = wrapi(_menu_index - 1, 0, data.verb_set.size())
		_update_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_menu_index = wrapi(_menu_index + 1, 0, data.verb_set.size())
		_update_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("confirm"):
		get_viewport().set_input_as_handled()
		_confirm_verb()


## Renders exactly what the enemy's verb_set lists, in its order. No verb
## names appear in this scene or the .tscn — the data file is the menu.
func _build_menu() -> void:
	for child in _menu.get_children():
		child.queue_free()
	for verb in data.verb_set:
		var label := Label.new()
		label.name = String(verb)
		_menu.add_child(label)
	_menu_index = 0
	_update_menu()


func _update_menu() -> void:
	for i in data.verb_set.size():
		var label: Label = _menu.get_child(i)
		var selected := i == _menu_index
		# Corruption substitutes verbs in place — same slot, darker meaning
		# (Phase 5). The data file still lists the original name; the
		# current band decides what actually renders and resolves.
		label.text = ("> " if selected else "  ") + String(_effective_verb(data.verb_set[i]))
		# Dimming the unselected rows is the whole highlight system.
		label.modulate = Color.WHITE if selected else Color(1, 1, 1, 0.55)


## What a listed verb currently IS, after the corruption track's overrides
## (Talk may be Intimidate now). Rendering and dispatch both go through
## this, so the player always gets exactly what the menu says.
func _effective_verb(verb: StringName) -> StringName:
	return GameState.corruption_verb_overrides().get(verb, verb)


func _on_band_crossed(_band: int, crossing_text: String) -> void:
	if not crossing_text.is_empty():
		_narrate_append(crossing_text)
	# Re-render in place: a slot's verb may just have mutated. (The
	# first-mutation flash that makes this unmissable is Phase 7's task.)
	_update_menu()
	_refresh_status()


## Generic dispatch (plan task 3.5): look the verb up, call it. A verb in a
## data file with no function here is a content error, reported loudly
## instead of crashing (task 3.3's test).
func _confirm_verb() -> void:
	var verb: StringName = _effective_verb(data.verb_set[_menu_index])
	if not _verb_handlers.has(verb):
		push_error("No resolution function for verb '%s' — add it to _verb_handlers." % verb)
		_narrate("Nothing happens. ('%s' has no resolution function.)" % verb)
		return
	_verb_handlers[verb].call()
	if not _done:
		_update_menu()


## Records a committed choice. Everything the run log needs later (Phase 6)
## flows from these two lines.
func _take_turn(verb: StringName) -> void:
	_verbs_chosen.append(verb)
	_turns_elapsed += 1


# --- Combat verb set (design-lockdown.md §3, verbatim) ---


func _verb_fight() -> void:
	_take_turn(&"Fight")
	var dmg := maxi(GameState.atk - data.def_stat, 1)
	_enemy_hp = maxi(_enemy_hp - dmg, 0)
	_narrate("You strike %s for %d." % [data.enemy_name, dmg])
	# Corruption trigger 1 (lockdown §5): choosing violence against someone
	# who would have talked. Applied before the victory check so the price
	# is paid even on the killing blow.
	if data.talk_receptivity:
		_apply_corruption(3)
	_refresh_status()
	if _enemy_hp <= 0:
		_narrate_append("It collapses.")
		_end_encounter(&"victory")
		return
	_enemy_acts()


func _verb_talk() -> void:
	_take_turn(&"Talk")
	if not data.talk_receptivity:
		# Data-driven rebuff line if the enemy has one ("It only growls").
		if data.dialogue_lines.is_empty():
			_narrate("%s does not respond." % data.enemy_name)
		else:
			_narrate(data.dialogue_lines[0])
		_enemy_acts()
		return
	# Receptive: advance the exchange. The enemy is listening, so it does
	# not act between lines (Decision 9).
	if _dialogue_index < data.dialogue_lines.size():
		_narrate(data.dialogue_lines[_dialogue_index])
		_dialogue_index += 1
	if _dialogue_index >= data.dialogue_lines.size():
		_narrate_append("The exchange settles it peacefully.")
		_end_encounter(&"talked_down")


func _verb_flee() -> void:
	_take_turn(&"Flee")
	if _roll_succeeds(data.flee_difficulty):
		_narrate("You break away.")
		# Phase 4 grants one tick of encounter immunity on this outcome so
		# fleeing can't chain straight back into the same trigger.
		_end_encounter(&"fled")
		return
	_narrate("You can't get away.")
	_enemy_acts()


func _verb_use_item() -> void:
	if GameState.inventory.is_empty():
		# Menu-level rejection: no item, no turn, no enemy action
		# (Decision 19).
		_narrate("You carry nothing.")
		return
	_take_turn(&"UseItem")
	var item: ItemData = GameState.inventory.pop_front()
	_apply_item(item)
	_enemy_acts()


func _apply_item(item: ItemData) -> void:
	match item.effect:
		&"heal":
			GameState.hp = mini(GameState.hp + item.amount, GameState.max_hp)
			_narrate("You use %s. HP +%d." % [item.item_name, item.amount])
		_:
			_narrate("%s does nothing." % item.item_name)
	_refresh_status()


# --- Intimate verb set (design-lockdown.md §4, verbatim) ---


func _verb_resist() -> void:
	_take_turn(&"Resist")
	if _roll_succeeds(data.resist_difficulty):
		_narrate("You hold yourself together and pull away.")
		_end_encounter(&"resisted")
		return
	_narrate("Your resolve slips.")
	# Lockdown §4: failure is corruption +2 AND one stage — the +2 is the
	# lesser third feed into the same corruption track (lockdown §5).
	_apply_corruption(2)
	_advance_stage()


func _verb_yield() -> void:
	_take_turn(&"Yield")
	_narrate("You accept.")
	# Corruption trigger 2 (lockdown §5). The transaction is explicit
	# on-screen: price first, boon second, both narrated.
	_apply_corruption(data.yield_corruption_value)
	if data.boon_on_yield is ItemData:
		var boon: ItemData = data.boon_on_yield
		GameState.inventory.append(boon)
		_narrate_append("%s is pressed into your hands." % boon.item_name)
	_end_encounter(&"yielded")


func _verb_redirect() -> void:
	# Redirect requires somewhere to redirect to (lockdown §4). The verb
	# shouldn't be in a verb_set without options, but data files can lie.
	if data.redirect_options.is_empty():
		_narrate("There is nothing to redirect toward.")
		return
	_take_turn(&"Redirect")
	if _roll_succeeds(data.redirect_difficulty):
		# The clean exit: no corruption, no boon — the asymmetry that keeps
		# Yield-vs-Redirect unsolved (lockdown Decision Log).
		_narrate("%s — and it works. You step away clean." % data.redirect_options[0])
		_end_encounter(&"redirected")
		return
	_narrate("It is not deflected.")
	_advance_stage()


## One step of the 3-stage sequence. Completing it resolves as a forced
## yield: full corruption price, no boon (lockdown §4 — "refusing to choose
## is choosing").
func _advance_stage() -> void:
	_stage += 1
	_refresh_status()
	if _stage >= 3:
		_narrate_append("The sequence completes. Refusing to choose was a choice.")
		_apply_corruption(data.yield_corruption_value)
		_end_encounter(&"yielded_forced")


# --- Corruption-mutated verbs (Phase 5): same slots, darker meanings ---


## Talk's band-2 mutation (the athlete's track). Always works — receptivity
## is irrelevant to a threat — and no corruption changes hands in either
## direction ("no corruption refund", plan task 5.2). The enemy flees the
## grid for good.
func _verb_intimidate() -> void:
	_take_turn(&"Intimidate")
	_narrate("%s breaks and runs from what you have become." % data.enemy_name)
	_end_encounter(&"intimidated")


## Resist's band-3 mutation: end the intimate encounter by force. No boon,
## and the body pays 2 HP (Decision 25) — if that is all she has left, loss
## condition 1 applies. Power purchased with self, every time.
func _verb_overwhelm() -> void:
	_take_turn(&"Overwhelm")
	GameState.hp = maxi(GameState.hp - 2, 0)
	_narrate("You end it by force. It costs you a piece of yourself. HP -2.")
	_refresh_status()
	if GameState.hp <= 0:
		_done = true
		_narrate_append("You fall.")
		Events.player_died.emit()
		return
	_end_encounter(&"overwhelmed")


# --- Shared machinery ---


## The enemy's half of the strict alternation. In combat that's a
## counterattack with the same damage formula the player uses (lockdown §3).
## In an intimate encounter the sequence advancing IS the enemy's action
## (Decision 20) — it fires on a failed Flee and on enemy-first openings.
func _enemy_acts() -> void:
	if _done:
		return
	if data.encounter_flavor == &"intimate":
		_advance_stage()
		return
	var dmg := maxi(data.atk - GameState.def_stat, 1)
	GameState.hp = maxi(GameState.hp - dmg, 0)
	_narrate_append("%s hits you for %d." % [data.enemy_name, dmg])
	_refresh_status()
	if GameState.hp <= 0:
		# Loss condition 1 (lockdown §6). player_died replaces
		# encounter_resolved — there is no result to resume from.
		_done = true
		_narrate_append("You fall. (Death screen arrives in Phase 6.)")
		Events.player_died.emit()


## design-lockdown.md's d100 rule, shared by Flee/Resist/Redirect: success
## when the roll meets or beats difficulty x 100. All rolls draw from the
## seeded run RNG.
func _roll_succeeds(difficulty: float) -> bool:
	return GameState.roll_d100() >= int(difficulty * 100.0)


## The corruption hook (plan task 3.8). Every corruption change in an
## encounter flows through here so the status panel updates at the moment
## of choice — the moral system only works if the price is visible when
## it's paid. The band engine (stat trades, verb mutations, loss condition
## 2) lives in GameState.add_corruption; crossings come back to this scene
## through the corruption_band_crossed signal.
func _apply_corruption(amount: int) -> void:
	if amount == 0:
		return
	_corruption_delta += amount
	_narrate_append("Corruption +%d." % amount)
	GameState.add_corruption(amount)
	_refresh_status()


## Every exit path funnels through here with its outcome enum, emitting the
## full result payload the plan's task 3.7 specifies.
func _end_encounter(outcome: StringName) -> void:
	_done = true
	Events.encounter_resolved.emit({
		"outcome": outcome,
		"verbs_chosen": _verbs_chosen.duplicate(),
		"turns_elapsed": _turns_elapsed,
		"corruption_delta": _corruption_delta,
	})
	if _standalone:
		_narrate_append("[outcome: %s] E cycles to the next test enemy." % outcome)


func _narrate(text: String) -> void:
	_narration.text = text


func _narrate_append(text: String) -> void:
	if _narration.text.is_empty():
		_narration.text = text
	else:
		_narration.text += "\n" + text


func _refresh_status() -> void:
	# ATK/DEF are stated because corruption trades them (plan task 5.2:
	# "numbers stated on the status panel").
	var text := "HP %d/%d   ATK %d  DEF %d\nCorruption %d/%d" % [
		GameState.hp, GameState.max_hp, GameState.atk, GameState.def_stat,
		GameState.corruption, GameState.CORRUPTION_MAX,
	]
	if data.encounter_flavor == &"intimate":
		text += "\nSequence %d/3" % _stage
	_status_label.text = text
	var enemy_text := data.enemy_name
	if data.encounter_flavor == &"combat":
		enemy_text += "   HP %d/%d" % [_enemy_hp, data.hp]
	_enemy_label.text = enemy_text
