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
