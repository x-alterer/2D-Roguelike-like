## Events — the global signal bus (autoload singleton).
##
## What this is: a node that declares signals and nothing else. Scenes emit
## into it and listen on it; it has no logic of its own and never will.
##
## Why it exists: the Exploration and Encounter scenes must stay independent
## — that independence is what makes them separately buildable and testable
## (implementation plan, Phase 1 task 5). If Exploration called Encounter
## directly, neither could run without the other. Instead both talk only to
## this bus, and Main is the only listener that reacts by switching modes.
##
## How it connects: Exploration emits encounter_triggered (debug key E in
## Phase 1; the real trigger dispatcher in Phase 2). Encounter emits
## encounter_resolved or player_died. Main connects to all four signals in
## its _ready() and performs the scene switches.
extends Node

## An encounter should begin. `enemy_data` is the triggering enemy's
## EnemyData resource (null in Phase 1's debug path — enemies don't exist
## yet). `trigger_type` is one of design-lockdown.md §7's enum values
## ("proximity", "player_initiated", "enemy_initiated"); it decides the
## encounter's opening framing in Phase 4.5.
signal encounter_triggered(enemy_data: Resource, trigger_type: StringName)

## The encounter ended and exploration should resume. `result` carries the
## outcome payload; from Phase 3 on it holds outcome, verbs_chosen,
## turns_elapsed and corruption_delta (Phase 1 sends a stub).
signal encounter_resolved(result: Dictionary)

## The athlete's HP reached 0 (loss condition 1). Emitted instead of
## encounter_resolved; Main routes it to the death end screen in Phase 6.
signal player_died

## The run is over for any reason ("win", "death", "corruption"). End-screen
## handling is Phase 6; until then Main shows a minimal overlay.
signal run_ended(reason: StringName)

## Corruption crossed into a new band (Phase 5). Emitted by GameState once
## per crossing — an event at the moment it happens, never a per-frame
## check. `crossing_text` is the track's interstitial line for that band;
## the encounter narrates it and re-renders its menu (verbs may have
## mutated), exploration retints the athlete.
signal corruption_band_crossed(band: int, crossing_text: String)
