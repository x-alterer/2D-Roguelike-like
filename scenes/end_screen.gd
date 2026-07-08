## EndScreen — the behavioral mirror (Phase 6).
##
## What this is: the screen after every run. It shows how the run ended,
## the seed, and this run's profile — encounters, verb counts, corruption —
## in neutral, descriptive language. A mirror, not a judgment: "Fight: 6"
## is data; the player supplies the verdict (plan risk 7). Below that, the
## history block: runs played, causes, best result. Self-knowledge is the
## only meta-progression the PoC has.
##
## Why the disk write happens here: this scene's _ready is the first moment
## the run log is guaranteed complete — the encounter that ended the run
## appends its own record before Main can swap scenes (Decision 32). So
## record_run_end() runs here, exactly once, then everything on screen is
## read back from the same state that was just persisted.
##
## How it connects: reads GameState (cause, seed, run log) and the
## RunHistory file. Confirm emits Events.title_requested; Main swaps back
## to the title.
extends Node2D

@onready var _background: ColorRect = $Background
@onready var _cause_label: Label = $CauseLabel
@onready var _seed_label: Label = $SeedLabel
@onready var _profile_label: Label = $ProfileLabel
@onready var _history_label: Label = $HistoryLabel


func _ready() -> void:
	GameState.record_run_end()
	_show_cause()
	_seed_label.text = "seed %d" % GameState.rng_seed
	_profile_label.text = _build_profile_text()
	_history_label.text = _build_history_text()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("confirm"):
		get_viewport().set_input_as_handled()
		Events.title_requested.emit()


## The corruption end must stay visually distinct from HP death (lockdown
## §6 demands two different loss presentations): armor-red field and the
## track's Bad End text, versus plain dark and a plain sentence.
func _show_cause() -> void:
	match GameState.run_end_cause:
		&"win":
			_background.color = Color(0.05, 0.09, 0.06)
			_cause_label.text = "She finds the way out."
		&"corruption":
			_background.color = Color(0.16, 0.02, 0.04)
			_cause_label.text = GameState.corruption_track.bad_end_text
		_:
			_background.color = Color(0.04, 0.04, 0.07)
			_cause_label.text = "She falls.\nThe dream closes over the place she was."


## This run, in numbers. Neutral wording only — "Fight: 6" is a mirror,
## "resorted to violence 6 times" would be a lecture.
func _build_profile_text() -> String:
	var verb_counts := {}
	for entry: Dictionary in GameState.run_log:
		for verb: StringName in entry.get("verbs_chosen", []):
			verb_counts[verb] = verb_counts.get(verb, 0) + 1
	var lines: Array[String] = []
	lines.append("THIS RUN")
	lines.append("Encounters: %d" % GameState.run_log.size())
	if verb_counts.is_empty():
		lines.append("No verbs chosen.")
	else:
		var names := verb_counts.keys()
		names.sort_custom(func(a: StringName, b: StringName) -> bool:
			return verb_counts[a] > verb_counts[b])
		for verb: StringName in names:
			lines.append("%s: %d" % [verb, verb_counts[verb]])
	lines.append("Corruption at end: %d" % GameState.corruption)
	return "\n".join(lines)


## Every run so far: counts, causes, best result. The full per-run
## profiles live in the .tres records; the screen shows the shape of them.
func _build_history_text() -> String:
	var history := GameState.load_run_history()
	var causes := {}
	var best_win_corruption := -1
	for run: Dictionary in history.runs:
		var cause: StringName = run.get("cause", &"?")
		causes[cause] = causes.get(cause, 0) + 1
		if cause == &"win":
			var corruption: int = run.get("corruption", 0)
			if best_win_corruption < 0 or corruption < best_win_corruption:
				best_win_corruption = corruption
	var lines: Array[String] = []
	lines.append("HISTORY")
	lines.append("Runs: %d" % history.runs.size())
	for cause: StringName in causes:
		lines.append("%s: %d" % [cause, causes[cause]])
	if best_win_corruption >= 0:
		lines.append("Best: out at corruption %d" % best_win_corruption)
	else:
		lines.append("Best: no way out found yet")
	return "\n".join(lines)
