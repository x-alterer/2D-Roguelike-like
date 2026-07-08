## Sfx — single-tone feedback for key events (autoload singleton).
##
## What this is: five placeholder beeps (generated sine WAVs in
## assets/sfx/) behind one call: Sfx.play(&"move"). A small pool of
## AudioStreamPlayers rotates so a quick step-step-bump doesn't cut its
## own sounds off.
##
## Why it's a third autoload (technical plan, Decision 37): sound is a
## cross-scene service — exploration, encounter, AND the encounter's F6
## standalone mode all need it, so it can't live in Main, and the Events
## bus stays signal-only. Phase 7's rule: silence is not acceptable; the
## ear needs *something* to confirm inputs were received. Real audio is
## explicitly out of the PoC's scope — these tones are the whole
## soundscape until then.
##
## How it connects: scenes call play() with one of the TONES keys at the
## moment the event happens. Nothing calls back; sound is fire-and-forget.
extends Node

## The plan's five events (task 7.5), one tone each.
const TONES: Dictionary = {
	&"move": preload("res://assets/sfx/move.wav"),
	&"bump": preload("res://assets/sfx/bump.wav"),
	&"encounter": preload("res://assets/sfx/encounter.wav"),
	&"corruption": preload("res://assets/sfx/corruption.wav"),
	&"confirm": preload("res://assets/sfx/confirm.wav"),
}
## Enough simultaneous voices that rapid inputs overlap instead of
## clipping each other.
const POOL_SIZE := 4

var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		# Placeholder tones sit under the (future) mix, not on top of it.
		player.volume_db = -8.0
		add_child(player)
		_players.append(player)


## Plays one of the TONES keys. An unknown name is a content error worth
## hearing about in the log, not a crash.
func play(tone_name: StringName) -> void:
	if not TONES.has(tone_name):
		push_error("Sfx.play: no tone named '%s'." % tone_name)
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = TONES[tone_name]
	player.play()
