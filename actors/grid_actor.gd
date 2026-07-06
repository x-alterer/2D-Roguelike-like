## GridActor — base class for anything that occupies a grid cell.
##
## What this is: shared movement machinery for the player and enemies. It
## owns the one rule the whole grid mode depends on: `grid_pos` (a cell
## coordinate) is the truth about where an actor is, and the pixel position
## is derived from it. Tweens only animate pixels toward what is already
## true logically.
##
## Why it exists: the Architecture Decisions table fixes "Grid truth —
## logical coordinates; tweens are presentation". If gameplay ever read
## pixel positions, an actor could be "between cells" at the moment a rule
## fires — the whole position-desync bug class this design prevents.
##
## How it connects: exploration.gd's turn scheduler calls place_at/step_to/
## bump and reads grid_pos. player.tscn (PlayerActor) and enemy.tscn
## (EnemyActor) both extend this class.
class_name GridActor
extends Node2D

const TILE_SIZE := 16
## Seconds one step animation takes. The scheduler waits slightly longer
## than this before accepting the next input, so held keys advance the
## world at a readable pace.
const STEP_TIME := 0.1

## The actor's cell — the single source of truth. It changes instantly when
## a move is committed, before any animation plays.
var grid_pos: Vector2i

var _tween: Tween


## Instantly puts the actor on a cell, no animation. Used at spawn.
func place_at(cell: Vector2i) -> void:
	grid_pos = cell
	position = Vector2(cell * TILE_SIZE)


## Commits a move: logic updates now, pixels catch up over STEP_TIME.
func step_to(cell: Vector2i) -> void:
	grid_pos = cell
	_restart_tween()
	_tween.tween_property(self, "position", Vector2(cell * TILE_SIZE), STEP_TIME)


## Rejected-move feedback: lean a quarter tile toward `dir` and settle back.
## grid_pos never changes — a bump is pure presentation.
func bump(dir: Vector2i) -> void:
	var home := Vector2(grid_pos * TILE_SIZE)
	_restart_tween()
	_tween.tween_property(self, "position", home + Vector2(dir) * (TILE_SIZE / 4.0), STEP_TIME / 2.0)
	_tween.tween_property(self, "position", home, STEP_TIME / 2.0)


## Kills any in-flight animation first, so two quick moves can't fight over
## the position property and leave the sprite stranded off-cell.
func _restart_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
