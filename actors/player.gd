## PlayerActor — the athlete's body on the exploration grid.
##
## What this is: a GridActor with nothing extra yet. It exists as its own
## class and scene so the player has a stable identity in the scene tree
## and a place for later phases to hang player-only presentation — Phase 5's
## corruption palette swaps will land here.
##
## Why input is NOT handled here: the turn scheduler in exploration.gd must
## decide whether a keypress becomes a committed move, a bump, or an
## encounter trigger *before* anything moves. Letting the actor move itself
## would split rule decisions across two scripts.
##
## How it connects: exploration.gd spawns player.tscn, drives it through the
## GridActor methods, and mirrors every committed move into
## GameState.grid_position so the position survives mode switches.
class_name PlayerActor
extends GridActor

## Her placeholder color, and the armor-crimson it drowns in band by band.
const BASE_COLOR := Color(0.92, 0.85, 0.42)
const CORRUPTED_COLOR := Color(0.6, 0.08, 0.16)

@onready var _rect: ColorRect = $Rect


## The palette-swap stand-in for Phase 5's per-band presentation: the
## corruption shows on her own body, one band at a time. Exploration calls
## this at spawn (corruption only changes inside encounters, so spawn-time
## is always current).
func refresh_corruption_visual() -> void:
	var band_count := GameState.corruption_track.band_thresholds.size()
	var t := GameState.corruption_band() / float(maxi(band_count, 1))
	_rect.color = BASE_COLOR.lerp(CORRUPTED_COLOR, clampf(t, 0.0, 1.0))
