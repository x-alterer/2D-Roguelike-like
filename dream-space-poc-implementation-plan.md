# Dream-Space Proof of Concept — Implementation Plan

**Scope declaration.** This plan implements the grid-based, turn-based roguelike architecture described in the design discussion, applied to the Dream-Space proof of concept: one character (the athlete), two modes (grid exploration, menu encounter), one transition system, one corruption system, one small dungeon, Godot. Everything else is out of scope and listed as such at the end.

**Structure.** Eight phases. Each phase ends in something playable or testable — no phase produces only invisible infrastructure. Phases are ordered by dependency, but Phases 2 and 3 are independent and can be built in either order or in parallel sessions. Each phase has a Definition of Done (DoD). Do not start a phase until the previous phase's DoD is met, except where noted.

---

## Phase 0 — Design Lockdown (paper, no engine)

The one open design question blocks everything downstream: **what is the player doing for 60 seconds?** Answer it before opening Godot, because the answer determines the turn scheduler, the encounter trigger, and the UI.

**Tasks:**

1. Write the 60-second script. One paragraph, present tense, second person: "You step north. A shadow shifts two tiles ahead..." It must name every input the player gives and every response the game gives, in order. If a sentence contains a system you cannot describe mechanically, the script fails — rewrite until it doesn't.
2. Lock the exploration verb set. Move (4-way or 8-way — decide now), plus at most two more: interact and wait are the standard candidates. Nothing else in the PoC.
3. Lock the encounter verb set. Fight, Talk, Flee, Use Item — confirm or cut. Each verb needs a one-line resolution rule (e.g., "Fight: compare ATK vs DEF, subtract difference from HP").
4. Lock the corruption rule for the athlete. One sentence of the form: "When the player does X, corruption increases by Y, which causes Z." X must be a concrete in-game action (e.g., choosing Fight when Talk was available), not a theme.
5. Define the run's shape: start condition, win condition (reach the exit is enough for the PoC), and the two loss conditions (HP zero; corruption max).

**DoD:** A one-page document containing the 60-second script, both verb sets with resolution rules, the corruption rule, and the run shape. If any item is a theme rather than a rule, Phase 0 is not done.

**Estimated effort:** 1–2 sessions. Resist expanding this into a full design doc — one page.

---

## Phase 1 — Godot Skeleton

**Goal:** A project that boots, switches between two placeholder scenes, and holds state across the switch.

**Tasks:**

1. Create the project. Settings: 2D, pixel snap on, fixed logical resolution (e.g., 640×360 scaled), keyboard input map for the exploration verbs plus menu navigation (up/down/confirm/cancel).
2. Scene architecture — three top-level scenes:
   - `Main.tscn` — persistent root. Owns mode switching. Never unloaded.
   - `Exploration.tscn` — Mode 1. Loaded/unloaded by Main.
   - `Encounter.tscn` — Mode 2. Loaded/unloaded by Main.
3. One autoload singleton: `GameState.gd`. Holds player HP, corruption, inventory, grid position, and RNG seed. This is the only data that survives a mode switch. Everything else is scene-local and disposable.
4. Mode switching in Main: `enter_encounter(enemy_data)` and `exit_encounter(result)`. For now, wire them to a debug key: press E, encounter scene loads with a colored rectangle; press Escape, exploration returns with player position intact.
5. A second, minimal singleton: `Events.gd` (signal bus). Signals: `encounter_triggered`, `encounter_resolved`, `player_died`, `run_ended`. Scenes talk to Main only through these — no direct scene-to-scene references. This keeps the two modes independent, which is the property that makes them separately buildable and testable.

**DoD:** Boot the game, press E, see the encounter placeholder, press Escape, return to exploration with position preserved. HP value set in one mode is readable in the other.

---

## Phase 2 — Mode 1: Grid Exploration

**Goal:** The MOVE loop is real. Player steps, world ticks, feedback lands.

**Tasks:**

1. **TileMap layer.** Hand-author one test floor in Godot's TileMap editor (procedural generation is Phase 7 — do not touch it yet). Two tile types: floor and wall. Use custom data layers on the tileset to mark walkability rather than a parallel array — Godot supports this natively and it keeps map data in one place.
2. **Grid actor base.** A `GridActor` scene (player and enemies both inherit it): holds grid coordinates, converts grid→pixel position, tween-moves between cells over ~0.1s. Logical position updates instantly; the tween is presentation only. Never let the tween be the source of truth.
3. **Player input.** On directional input: check target cell walkability, check occupancy, then either move or bump. A rejected move consumes no turn.
4. **Turn scheduler.** The core of Mode 1. Simple version (correct for the PoC): a `take_turn()` pass — player acts, then every other actor acts once, then control returns. No energy/speed system; every actor gets exactly one action per tick. The scheduler lives in `Exploration.tscn`, not in GameState.
5. **One enemy behavior.** A wanderer: each tick, 50% move toward player (straight-line step, no pathfinding yet), 50% random step. This is enough to make the turn system visible.
6. **Encounter trigger.** When an enemy and the player occupy adjacent cells at end of tick, emit `encounter_triggered` with that enemy's data. Delete the debug key from Phase 1.
7. **Feedback pass.** Bump animation on rejected moves, a one-frame flash when an enemy spots the player. Minimal, but present — the anatomy-of-a-choice loop breaks if the player can't discern outcomes.

**DoD:** Walk a hand-made floor. Walls block. An enemy wanders and pursues. Walking into its neighborhood fires the encounter signal (which currently just loads the Phase 1 placeholder). Every player action visibly advances the world one tick.

---

## Phase 3 — Mode 2: Encounter Screen

**Goal:** The CHOOSE loop is real. Menu, resolution, exit conditions. Can be built before or in parallel with Phase 2 — it only needs the Phase 1 skeleton.

**Tasks:**

1. **Layout.** Static screen: enemy sprite/rectangle top, player status (HP, corruption) bottom-left, verb menu bottom-right. Pokémon layout; do not innovate here.
2. **Data-driven enemies.** Define enemies as Godot `Resource` files (`EnemyData.tres`): name, HP, ATK, DEF, dialogue lines, talk-receptivity flag, flee-difficulty. The encounter scene reads whatever resource it's handed. This is the seam through which Bad-End enemy variants will later enter — build the seam, not the feature.
3. **Verb implementations,** exactly as locked in Phase 0:
   - **Fight:** apply the resolution rule; enemy counterattacks; HP updates on both sides.
   - **Talk:** if the enemy's receptivity flag is set, advance a 2–3 line exchange that can end the encounter peacefully; if not, waste the turn (enemy still acts).
   - **Flee:** roll against flee-difficulty; success exits the encounter, failure wastes the turn.
   - **Use Item:** open inventory; consume the item; apply its effect. One item type (heal) is enough.
4. **Turn structure inside the encounter:** player chooses → resolution text/animation → enemy acts → back to menu. Strictly alternating.
5. **Exit paths:** enemy defeated, enemy talked down, flee succeeded, player HP zero. Each emits `encounter_resolved` with a result payload (or `player_died`).
6. **Corruption hook:** implement the Phase 0 rule here. If the rule is "Fight when Talk was available raises corruption," the encounter scene checks the receptivity flag when Fight is chosen and increments `GameState.corruption`. Display the change on the status panel immediately — the moral system only works if consequences are discernible at the moment of choice.

**DoD:** Launch the encounter scene directly (Godot's run-current-scene) with a test enemy resource. All four verbs resolve correctly. Corruption visibly changes when the rule fires. All exit paths emit correct signals.

---

## Phase 4 — The Transition

**Goal:** The two independent systems become one game.

**Tasks:**

1. Wire `encounter_triggered` (Phase 2) to actually load the encounter scene with the triggering enemy's resource.
2. Wire `encounter_resolved` back: on victory, remove the enemy actor from the grid; on talk-down, remove or mark it non-hostile; on flee, return with the enemy still present and place the player one cell away (define this precisely — flee-adjacency loops are the classic bug here: fleeing straight back into trigger range re-fires the encounter forever; simplest fix is one tick of encounter immunity after a flee).
3. Transition presentation: a 0.3s fade or shatter both directions. Cheap, but the mode shift should be felt.
4. State audit: confirm HP, corruption, and inventory changes made in encounters persist to exploration and vice versa. Write down the full list of what carries across; anything not on the list must not carry across.

**DoD:** A full loop with no debug keys: explore → get caught → resolve by any verb → return to the grid in a consistent state → repeat. Fleeing does not chain-trigger.

---

## Phase 5 — The Athlete's Corruption Arc

**Goal:** The corruption number becomes the character. This is the reusable framework the whole roster depends on, so it gets its own phase.

**Tasks:**

1. **Thresholds.** Divide corruption into 3–4 bands (e.g., 0–24 / 25–49 / 50–74 / 75–100). Store band-crossing as an event, not a per-frame check.
2. **Mechanical effects per band.** The armor integrating with her should read as power purchased with self. Concretely: each band up, ATK rises and something else degrades — max HP down, Talk options removed, or Flee difficulty up. Pick two effects total for the PoC. The pattern to establish: *corruption trades capability for humanity, and the trade is stated in numbers.*
3. **Presentation per band.** Palette swap or sprite overlay on the player actor, one line of interstitial text on crossing a threshold. Cheap signals; the point is that the player sees the change on their own body.
4. **The final band is a Bad End trigger.** Corruption max = the armor takes her = run over. Show a distinct end screen from HP death. Do not build the twisted-enemy-variant system — but write the run-end record (character, corruption at death, cause) to a `RunHistory` resource saved to disk. That record is the input the Bad End system will consume later. Again: build the seam, not the feature.
5. **Generalize before closing.** Extract the corruption logic into a `CorruptionTrack` resource + script pair that references band thresholds and effect tables by data, not code. Test: could a second character with a different flaw reuse this by writing a new resource file? If the answer requires touching code, refactor until it doesn't.

**DoD:** Playing badly (by the corruption rule) visibly and mechanically transforms the athlete across bands, ends the run at max, and writes a run record to disk. The system is defined in data files a second character could reuse.

---

## Phase 6 — Run Structure & Meta-Layer Stub

**Goal:** The game has a beginning, an end, and a next time.

**Tasks:**

1. Title screen → start run → dungeon → end screen (win at exit tile, or either death type) → title. Full reset of GameState on new run, except RunHistory.
2. Seeded RNG: seed generated per run, stored in GameState, displayed on the end screen. Cheap now, essential for debugging Phase 7's generation.
3. Knowledge-based meta-progression only: the end screen shows run history (runs played, causes of death, best result). No mechanical unlocks in the PoC — the player's accumulated knowledge is the meta-progression, which is the purest form of it anyway.

**DoD:** Can play three consecutive runs without restarting the program. History persists across program restarts.

---

## Phase 7 — Procedural Floor Generation

Deliberately late. Every prior phase runs on the hand-made floor, which means generation bugs can never be confused with gameplay bugs.

**Tasks:**

1. Simplest algorithm that works: rooms-and-corridors. Place 5–8 non-overlapping rectangular rooms, connect sequentially with L-corridors, done. No BSP, no cellular automata — those are upgrades for after the PoC.
2. Validity guarantees, per the know-your-metrics rule: flood-fill from spawn to confirm the exit is reachable; enemy spawns at minimum distance from the player spawn; regenerate on failure (with the seed logged).
3. Population pass: place exit, 3–5 enemies, 1–2 items from small weighted tables.
4. Keep the hand-made floor behind a debug flag permanently — it is the regression-test level.

**DoD:** Ten consecutive seeds produce completable floors. Any seed can be replayed from the end-screen seed display.

---

## Phase 8 — Content & Playtest Pass

**Goal:** Enough content to test whether the loop is fun, and a structured look at whether it is.

**Tasks:**

1. Content minimums: 3 enemy types (one talk-receptive, one aggressive, one that punishes Fight — e.g., high DEF, low HP, so Talk/Flee is correct), 2 item types, 1 floor layout algorithm, the athlete.
2. Self-playtest protocol, run against the anatomy-of-a-choice failure states:
   - Do decisions ever feel arbitrary? (Outcome stage broken.)
   - Is it ever unclear what you can do? (Choice-presentation stage broken.)
   - Do you ever die without knowing why? (Feedback stage broken.)
   - Does the corruption trade ever feel like the wrong price? (Balance, tune the numbers.)
3. One external playtester if available; watch silently, note where they stall.
4. Write a one-page findings document. Its last section answers the only question that matters: **does the 60-second loop from Phase 0 exist in the build, and is it worth 60 more seconds?** That answer decides whether the next milestone is character #2 or a loop redesign.

**DoD:** Findings document written. PoC judged.

---

## Explicitly Out of Scope

Cutting these is the plan working, not the plan failing:

- Second and third characters (manipulator, introvert)
- Psychology-driven world generation
- Bad End twisted-enemy variants (only the run record that feeds them — Phase 5)
- NPC factions and relationship tracking
- The meta-plot (dreamscape exploitation)
- Mechanical meta-progression / unlocks
- Art, music, and sound beyond placeholder rectangles and single-tone feedback
- Save-mid-run
- Any encounter verb beyond the locked four
- Field-of-view / fog of war (add post-PoC if exploration feels flat without it)

## Architecture Decisions (fixed, to stop re-decision churn)

| Decision | Choice | Reason |
|---|---|---|
| Cross-mode state | Single `GameState` autoload | One source of truth; everything else disposable |
| Scene communication | Signal bus (`Events` autoload) | Keeps the two modes independent |
| Turn model | One action per actor per tick | Simplest correct scheduler; energy systems are a post-PoC upgrade |
| Enemy/item/corruption definitions | Godot `Resource` files | New content = new data file, no code; this is the roster-expansion seam |
| Grid truth | Logical coordinates; tweens are presentation | Prevents the position-desync bug class entirely |
| Generation timing | Phase 7, after everything else works | Isolates generation bugs from gameplay bugs |

## Risks

1. **Phase 0 gets skipped or answered thematically.** Highest risk. Every downstream phase inherits the vagueness. The 60-second script is the gate; enforce it.
2. **The corruption rule turns out unfun in Phase 5.** Acceptable — that discovery is the PoC's job. Change the rule (data file), not the framework.
3. **Scope creep at Phase 3** (more verbs, more enemy behaviors) **and Phase 7** (fancier generation). The out-of-scope list is the defense; anything appealing goes on a post-PoC list, not in the build.
4. **The two modes drift apart in feel.** Watch for it at Phase 4; the transition presentation and shared status display are the stitches.
