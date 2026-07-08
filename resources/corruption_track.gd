## CorruptionTrack — one character's whole corruption arc, as a data file.
##
## What this is: a Resource script defining how corruption transforms a
## character: where the bands sit, what each crossing does to stats, which
## verbs darken into which, what the game says at each threshold, and what
## the final consumption reads like. The athlete's arc is
## resources/corruption/athlete_track.tres.
##
## Why it exists as data: this is the framework the whole roster depends on
## (plan Phase 5). A second character — the manipulator, the introvert —
## gets a different flaw by writing a new .tres file: different thresholds,
## different stat trades, different verb mutations. If adding a character
## required touching this script, the design would have failed its own test
## (plan task 5.6). Only a brand-new verb needs code: its resolution
## function in the encounter scene.
##
## How it connects: GameState holds the active track and runs the band
## engine against it (add_corruption). The encounter scene reads the merged
## verb overrides through GameState when rendering its menu.
##
## Indexing rule (technical plan, Decision 24): the arrays align with
## band_thresholds — crossing band_thresholds[i] applies
## stat_modifiers_per_band[i], adds verb_overrides_per_band[i] to the
## cumulative override merge, and narrates band_crossing_text[i].
class_name CorruptionTrack
extends Resource

## Corruption values at which a new band begins. Lockdown §6: 0–24 / 25–49
## / 50–74 / 75–99 / 100 = end, so [25, 50, 75, 100].
@export var band_thresholds: Array[int]
## Stat changes applied once per crossing, e.g. {"atk": 2, "max_hp": -5} —
## the body becomes weapon at the cost of endurance (lockdown §5).
@export var stat_modifiers_per_band: Array[Dictionary]
## Verb substitutions gained at each crossing, e.g. {&"Talk": &"Intimidate"}.
## Cumulative: every band reached so far contributes its overrides.
@export var verb_overrides_per_band: Array[Dictionary]
## One narration line per crossing — the cheap interstitial (plan task 5.4).
@export var band_crossing_text: Array[String]
## Shown on the distinct Bad End when corruption hits the final threshold.
@export var bad_end_text: String
