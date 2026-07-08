## RunHistory — every finished run, persisted to disk.
##
## What this is: a Resource holding one dictionary per completed run:
## {character, cause, corruption, rng_seed, run_log}. GameState appends to
## it and saves it as user://run_history.tres when a run ends.
##
## Why it exists now: Phase 5 builds the seam, not the feature. The future
## Bad End system (twisted enemy variants) and Phase 6's behavioral-profile
## end screen both consume these records; writing them from day one means
## those systems arrive to data that already exists.
##
## How it connects: only GameState touches it (record_run_end). Nothing
## reads it yet — Phase 6's end screen is the first consumer.
class_name RunHistory
extends Resource

## One entry per finished run, oldest first.
@export var runs: Array[Dictionary] = []
