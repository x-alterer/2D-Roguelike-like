```markdown
# Dream-Space Proof of Concept — Implementation Plan (v2)

**Scope declaration.** This plan implements the grid-based, turn-based roguelike architecture described in the design discussion, applied to the Dream-Space proof of concept: one character (the athlete), two modes (grid exploration, menu encounter), one transition system, one corruption system, one encounter routing system, one small dungeon, Godot. Everything else is out of scope and listed as such at the end.

**Structure.** Nine phases. Each phase ends in something playable or testable — no phase produces only invisible infrastructure. Phases are ordered by dependency, but Phases 2 and 3 are independent and can be built in either order or in parallel sessions. Each phase has a Definition of Done (DoD). Do not start a phase until the previous phase's DoD is met, except where noted.

---

## Phase 0 — Design Lockdown (paper, no engine)

The open design questions block everything downstream: **what is the player doing for 60 seconds?** and **what kinds of encounters exist?** Answer both before opening Godot, because the answers determine the turn scheduler, the encounter trigger, the routing logic, and the UI.

**Tasks:**

1. Write the 60-second script. One paragraph, present tense, second person: "You step north. A shadow shifts two tiles ahead..." It must name every input the player gives and every response the game gives, in order. If a sentence contains a system you cannot describe mechanically, the script fails — rewrite until it doesn't.
2. Lock the exploration verb set. Move (4-way or 8-way — decide now), plus at most two more: interact and wait are the standard candidates. Nothing else in the PoC.
3. Lock the encounter verb sets — **plural.** The game has (at minimum) two encounter flavors: combat and intimate. Each flavor gets its own verb set:
   - **Combat verbs:** Fight, Talk, Flee, Use Item — confirm or cut. Each verb needs a one-line resolution rule (e.g., "Fight: compare ATK vs DEF, subtract difference from HP").
   - **Intimate verbs:** Resist, Yield, Redirect, Flee — confirm or cut. Each verb needs a one-line resolution rule (e.g., "Yield: corruption +N, encounter ends peacefully, enemy grants a boon").
   - Both sets share a menu shell. The verbs that appear are determined by the enemy resource, not hardcoded.
4. Lock the corruption rules for the athlete — **two trigger conditions**, one per encounter flavor:
   - Combat trigger: one sentence of the form "When the player does X in combat, corruption increases by Y, which causes Z." X must be a concrete in-game action (e.g., choosing Fight when Talk was available).
   - Intimate trigger: one sentence of the same form (e.g., "When the player chooses Yield, corruption increases by Y, which causes Z").
   - These may produce different corruption amounts. The athlete's arc is about the body becoming the weapon/trap — both triggers feed the same track, but the intimate trigger likely produces more per firing.
5. Define the run's shape: start condition, win condition (reach the exit is enough for the PoC), and the two loss conditions (HP zero; corruption max).
6. Define encounter trigger types. Three enum values, minimum:
   - `proximity` — adjacency at end of tick (standard hostile)
   - `player_initiated` — player steps *into* the enemy's cell deliberately (non-hostile, beckoning)
   - `enemy_initiated` — enemy reaches the player (ambush, seduction)
   - Each enemy resource declares which trigger type it uses. This determines emotional framing: ambush ≠ approach ≠ temptation accepted.

**DoD:** A one-page document containing the 60-second script, both verb sets with resolution rules, both corruption trigger conditions, the trigger-type enum, and the run shape. If any item is a theme rather than a rule, Phase 0 is not done.

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
3. One autoload singleton: `GameState.gd`. Holds player HP, corruption, inventory, grid position, RNG seed, and **run log** (an array of per-encounter records — see Phase 6). This is the only data that survives a mode switch. Everything else is scene-local and disposable.
4. Mode switching in Main: `enter_encounter(enemy_data)` and `exit_encounter(result)`. For now, wire them to a debug key: press E, encounter scene loads with a colored rectangle; press Escape, exploration returns with player position intact.
5. A second, minimal singleton: `Events.gd` (signal bus). Signals: `encounter_triggered`, `encounter_resolved`, `player_died`, `run_ended`. Scenes talk to Main only through these — no direct scene-to-scene references. This keeps the two modes independent, which is the property that makes them separately buildable and testable.

**DoD:** Boot the game, press E, see the encounter placeholder, press Escape, return to exploration with position preserved. HP value set in one mode is readable in the other.

---

## Phase 2 — Mode 1: Grid Exploration

**Goal:** The MOVE loop is real. Player steps, world ticks, feedback lands.

**Tasks:**

1. **TileMap layer.** Hand-author one test floor in Godot's TileMap editor (procedural generation is Phase 8 — do not touch it yet). Two tile types: floor and wall. Use custom data layers on the tileset to mark walkability rather than a parallel array — Godot supports this natively and it keeps map data in one place.
2. **Grid actor base.** A `GridActor` scene (player and enemies both inherit it): holds grid coordinates, converts grid→pixel position, tween-moves between cells over ~0.1s. Logical position updates instantly; the tween is presentation only. Never let the tween be the source of truth.
3. **Player input.** On directional input: check target cell walkability, check occupancy, then either move or bump. A rejected move consumes no turn.
4. **Turn scheduler.** The core of Mode 1. Simple version (correct for the PoC): a `take_turn()` pass — player acts, then every other actor acts once, then control returns. No energy/speed system; every actor gets exactly one action per tick. The scheduler lives in `Exploration.tscn`, not in GameState.
5. **Two enemy behaviors, differentiated by trigger type:**
   - **Hostile wanderer** (`trigger_type: proximity`): each tick, 50% move toward player (straight-line step, no pathfinding yet), 50% random step. Encounter fires when adjacent at end of tick. Feels like a threat.
   - **Beckoner** (`trigger_type: player_initiated`): stationary or slow-patrolling, visually distinct (different color, particle, idle animation). Encounter fires only when the player deliberately steps into its cell. Feels like an invitation. The player *chose* to approach.
6. **Encounter trigger dispatcher.** At end of tick, iterate all actors; check each against its declared `trigger_type`:
   - `proximity`: adjacent to player? → fire.
   - `player_initiated`: player moved *into* this actor's cell? → fire.
   - `enemy_initiated`: this actor moved *into* player's cell? → fire.
   - Emit `encounter_triggered` with the actor's enemy resource and the trigger type.
7. **Feedback pass.** Bump animation on rejected moves, a one-frame flash when a hostile enemy spots the player, a distinct visual cue (glow, color shift) when a beckoner is within interaction range. Minimal, but present — the anatomy-of-a-choice loop breaks if the player can't discern outcomes.

**DoD:** Walk a hand-made floor. Walls block. A hostile wanders and pursues; adjacency fires the encounter signal. A beckoner sits visibly; stepping into its cell fires the encounter signal with a different trigger type. Every player action visibly advances the world one tick.

---

## Phase 3 — Mode 2: Encounter Screen

**Goal:** The CHOOSE loop is real. Menu, resolution, exit conditions. Can be built before or in parallel with Phase 2 — it only needs the Phase 1 skeleton.

**Tasks:**

1. **Layout.** Static screen: enemy sprite/rectangle top, player status (HP, corruption) bottom-left, verb menu bottom-right. Pokémon layout; do not innovate here.
2. **Data-driven enemies with verb sets.** Define enemies as Godot `Resource` files (`EnemyData.tres`):
   - Shared fields: name, HP, ATK, DEF, sprite, trigger_type, encounter_flavor enum (`combat` | `intimate` | future variants).
   - Combat-specific: dialogue lines, talk_receptivity flag, flee_difficulty.
   - Intimate-specific: yield_corruption_value, resist_difficulty, redirect_options, boon_on_yield.
   - **Critical field: `verb_set: Array[StringName]`** — the list of verbs this enemy's encounter presents. The menu reads this array and renders only what's listed. No hardcoded verb assumptions anywhere in the encounter scene.
3. **Verb implementations — Combat set,** exactly as locked in Phase 0:
   - **Fight:** apply the resolution rule; enemy counterattacks; HP updates on both sides.
   - **Talk:** if the enemy's receptivity flag is set, advance a 2–3 line exchange that can end the encounter peacefully; if not, waste the turn (enemy still acts).
   - **Flee:** roll against flee_difficulty; success exits encounter, failure wastes turn.
   - **Use Item:** open inventory; consume item; apply effect. One item type (heal) is enough.
4. **Verb implementations — Intimate set,** exactly as locked in Phase 0:
   - **Resist:** roll against resist_difficulty; success exits encounter (equivalent to Flee); failure progresses enemy's sequence, minor corruption gain.
   - **Yield:** corruption increases by yield_corruption_value; encounter ends peacefully; enemy grants boon (heal, stat buff, item). The transaction is explicit.
   - **Redirect:** check available redirect_options; player attempts to steer the encounter (mechanical parallel to Talk — success exits, failure wastes turn).
   - **Flee:** same implementation as combat Flee, shared code.
5. **Verb resolution is generic.** The encounter scene doesn't know what "Fight" *means* thematically — it reads verb names from the resource, maps them to resolution functions via a dictionary, and executes. Adding a new verb = adding a function + putting the verb name in a resource's `verb_set` array. No switch statements on encounter flavor.
6. **Turn structure inside the encounter:** player chooses → resolution text/animation → enemy acts → back to menu. Strictly alternating.
7. **Exit paths:** enemy defeated, enemy talked/redirected down, yield accepted, flee/resist succeeded, player HP zero. Each emits `encounter_resolved` with a result payload (or `player_died`). The payload includes: `outcome` enum, `verbs_chosen` array (ordered list of every verb the player selected this encounter), `turns_elapsed`, `corruption_delta`.
8. **Corruption hook:** implement both Phase 0 rules here. The encounter scene checks the relevant trigger condition when a corruption-triggering verb is chosen and increments `GameState.corruption`. Display the change on the status panel immediately — the moral system only works if consequences are discernible at the moment of choice.

**DoD:** Launch the encounter scene directly (Godot's run-current-scene) with a test combat enemy resource and a test intimate enemy resource. All verbs in both sets resolve correctly. Corruption visibly changes when either trigger condition fires. All exit paths emit correct signals with full payloads including `verbs_chosen`.

---

## Phase 4 — The Transition

**Goal:** The two independent systems become one game.

**Tasks:**

1. Wire `encounter_triggered` (Phase 2) to actually load the encounter scene with the triggering enemy's resource.
2. Wire `encounter_resolved` back: on victory, remove the enemy actor from the grid; on talk/redirect-down, remove or mark it non-hostile; on yield, remove and grant the boon to GameState; on flee/resist, return with the enemy still present and place the player one cell away (define this precisely — flee-adjacency loops are the classic bug here: fleeing straight back into trigger range re-fires the encounter forever; simplest fix is one tick of encounter immunity after a flee).
3. Transition presentation: a 0.3s fade or shatter both directions. Cheap, but the mode shift should be felt.
4. State audit: confirm HP, corruption, inventory, and run log changes made in encounters persist to exploration and vice versa. Write down the full list of what carries across; anything not on the list must not carry across.

**DoD:** A full loop with no debug keys: explore → get caught or approach → resolve by any verb → return to the grid in a consistent state → repeat. Fleeing does not chain-trigger. Both encounter flavors (combat and intimate) fire from their respective trigger types.

---

## Phase 4.5 — Encounter Variant Routing

**Goal:** The system knows which encounter *flow* to run based on enemy data, and is prepared for future variants without rewiring.

**Tasks:**

1. **Router logic in Main (or a dedicated EncounterRouter script).** When `encounter_triggered` fires, the router reads the enemy resource's `encounter_flavor` enum and (optionally) the `trigger_type` that caused it. Currently, routing is trivial — it loads the same `Encounter.tscn` which reads the `verb_set` from the resource. But the router is the explicit decision point: *this* enemy resource produces *this* encounter flow.
2. **Variant seam: the router checks a lookup table.** For the PoC it has two entries (combat, intimate) mapping to the same scene with different verb sets. Post-PoC, the table can map to entirely different scenes (e.g., a puzzle encounter, a chase sequence) without touching any other system. The router is the only code that needs to change when a new encounter type is invented.
3. **Trigger-type influenced presentation.** The router passes the trigger type to the encounter scene. The encounter uses it to set opening framing:
   - `proximity` / `enemy_initiated`: enemy acts first in the opening beat (they caught you / they reached you). Player menu appears after.
   - `player_initiated`: player gets the first menu immediately (you approached, you're in control — at least initially).
   - This is a single `if` on the encounter's `_ready()` — small cost, large framing difference.
4. **Confirm the routing is invisible to both modes.** Exploration doesn't know what kind of encounter it's triggering. The encounter scene doesn't know how it was triggered (beyond the passed trigger_type for framing). All coupling runs through the router and the enemy resource. Test: add a third dummy `encounter_flavor` value to the enum, point it at the same scene — nothing should break.

**DoD:** Both encounter flavors route correctly through the router. Trigger type influences opening framing. A dummy third flavor value loads without errors. Neither Exploration nor Encounter scenes reference the router or each other directly.

---

## Phase 5 — The Athlete's Corruption Arc

**Goal:** The corruption number becomes the character. This is the reusable framework the whole roster depends on, so it gets its own phase.

**Tasks:**

1. **Thresholds.** Divide corruption into 3–4 bands (e.g., 0–24 / 25–49 / 50–74 / 75–100). Store band-crossing as an event, not a per-frame check.
2. **Mechanical effects per band — transformation, not removal.** The armor integrating with her body should read as power purchased with self. Concretely, each band up applies two changes:
   - **Stat shift:** ATK rises, max HP decreases. The body becomes weapon at the cost of endurance. Numbers stated on the status panel.
   - **Verb mutation:** Verbs do not disappear — they *transform.* At band 2, "Talk" becomes "Intimidate" (same slot, different resolution: forces enemy to flee instead of peaceful resolution, no corruption refund). At band 3, "Resist" becomes "Overwhelm" (same slot: ends the intimate encounter by force, grants no boon, minor HP cost). The player still has four choices. The choices are darker.
   - The pattern to establish: *corruption trades humanity for power, and the trade shows in what the verbs now mean, not in what's missing.*
3. **Verb mutation is data-driven.** The `CorruptionTrack` resource holds a `verb_overrides` dictionary keyed by band: `{ 2: {"Talk": "Intimidate"}, 3: {"Resist": "Overwhelm"} }`. The encounter scene checks current band and substitutes before rendering the menu. Adding overrides = editing the resource file.
4. **Presentation per band.** Palette swap or sprite overlay on the player actor, one line of interstitial text on crossing a threshold. Cheap signals; the point is that the player sees the change on their own body.
5. **The final band is a Bad End trigger.** Corruption max = the armor takes her = run over. Show a distinct end screen from HP death. Do not build the twisted-enemy-variant system — but write the run-end record (character, corruption at death, cause, full verb history from the run log) to a `RunHistory` resource saved to disk. That record is the input the Bad End system will consume later. Build the seam, not the feature.
6. **Generalize before closing.** Extract the corruption logic into a `CorruptionTrack` resource + script pair that references band thresholds, stat effects, and verb overrides by data, not code. Test: could a second character (the manipulator) with a different flaw, different verb mutations, and different stat shifts reuse this by writing a new resource file? If the answer requires touching code, refactor until it doesn't.

**DoD:** Playing badly (by either corruption rule) visibly and mechanically transforms the athlete across bands — verbs mutate, stats shift, sprite changes. Max corruption ends the run distinctly. The system is defined in data files a second character could reuse without code changes.

---

## Phase 6 — Run Structure & Meta-Layer Stub

**Goal:** The game has a beginning, an end, and a next time.

**Tasks:**

1. Title screen → start run → dungeon → end screen (win at exit tile, or either death type) → title. Full reset of GameState on new run, except RunHistory.
2. Seeded RNG: seed generated per run, stored in GameState, displayed on the end screen. Cheap now, essential for debugging Phase 8's generation.
3. **Run logging granularity.** Each encounter appends a record to `GameState.run_log`:
   ```
   {
     enemy_name: String,
     encounter_flavor: StringName,
     trigger_type: StringName,
     verbs_chosen: Array[StringName],  # ordered, every choice
     outcome: StringName,
     corruption_delta: int,
     turns_elapsed: int
   }
   ```
   On run end, the full `run_log` array is written into the `RunHistory` resource alongside aggregate stats: total encounters, verb frequency counts (how many times Fight was chosen vs Talk vs Yield vs Resist across the run), corruption curve, cause of death.
4. **End screen displays behavioral profile.** Not a judgment — a mirror. Show the player: "Encounters: 9. Fought: 6. Yielded: 2. Fled: 1. Corruption at end: 67." Let them see their own pattern. This is the psychological-reflection thesis made concrete at the smallest possible scale.
5. Knowledge-based meta-progression only: the end screen shows run history (runs played, causes of death, best result, behavioral profiles). No mechanical unlocks in the PoC — the player's accumulated self-knowledge is the meta-progression.

**DoD:** Can play three consecutive runs without restarting the program. History persists across program restarts. Each run's behavioral profile is visible on the end screen.

---

## Phase 7 — Environmental Polish & Feedback

**Goal:** The game *feels* like something. The mechanical skeleton gets skin.

**Tasks:**

1. **Encounter screen juice:** screen shake on damage, text crawl for dialogue/narration, brief pause on corruption gain (the number ticks up visibly, not instantaneously).
2. **Exploration screen juice:** camera follow with slight lag, footstep particle, enemy idle animation (even if it's just a two-frame bob).
3. **Verb mutation feedback:** when a verb transforms for the first time in a run, flash the menu slot, show old→new name briefly. The player must notice the change *at the moment it matters* — when they're about to use it.
4. **Corruption band crossing:** brief interstitial screen (half-second hold, palette shift, one line of text — "The armor settles into your shoulders like it belongs there"). Don't interrupt flow for long, but mark the moment.
5. **Sound stubs:** single-tone feedback for key events (move, bump, encounter start, corruption gain, verb confirm). Placeholder beeps/clicks are fine. Silence is not — the ear needs *something* to confirm inputs were received.

**DoD:** The game has texture. Inputs feel acknowledged. Corruption shifts are noticeable. A first-time player can parse what's happening without reading code.

---

## Phase 8 — Procedural Floor Generation

Deliberately late. Every prior phase runs on the hand-made floor, which means generation bugs can never be confused with gameplay bugs.

**Tasks:**

1. Simplest algorithm that works: rooms-and-corridors. Place 5–8 non-overlapping rectangular rooms, connect sequentially with L-corridors, done. No BSP, no cellular automata — those are upgrades for after the PoC.
2. Validity guarantees: flood-fill from spawn to confirm the exit is reachable; enemy spawns at minimum distance from player spawn; regenerate on failure (with the seed logged).
3. Population pass: place exit, 3–5 enemies (mix of hostile and beckoner types, weighted by difficulty curve — more beckoners early, more hostiles late), 1–2 items from a small weighted table.
4. **Trigger-type-aware placement.** Beckoners (`player_initiated`) spawn in visible, slightly off-path positions — dead-end rooms, alcoves. The player should see them and *decide* to approach. Hostiles spawn in corridors and patrol rooms. Placement reinforces the emotional framing established by trigger types.
5. Keep the hand-made floor behind a debug flag permanently — it is the regression-test level.

**DoD:** Ten consecutive seeds produce completable floors with correct enemy-type placement. Any seed can be replayed from the end-screen seed display.

---

## Phase 9 — Content & Playtest Pass

**Goal:** Enough content to test whether the loop is fun, and a structured look at whether it is.

**Tasks:**

1. Content minimums:
   - **3 combat enemies:** one talk-receptive, one aggressive, one that punishes Fight (high DEF, low HP — Talk/Flee is mechanically correct).
   - **2 intimate enemies:** one that offers a significant boon for Yield (temptation), one that offers nothing and punishes Resist failure (trap — redirect is the correct play).
   - **2 item types:** heal, corruption-reduce (small amount — a pressure valve, not a solution).
   - **1 floor layout algorithm, the athlete, her full corruption track.**
2. Self-playtest protocol, run against the anatomy-of-a-choice failure states:
   - Do decisions ever feel arbitrary? (Outcome stage broken.)
   - Is it ever unclear what you can do? (Choice-presentation stage broken.)
   - Do you ever die without knowing why? (Feedback stage broken.)
   - Does the corruption trade ever feel like the wrong price? (Balance, tune the numbers.)
   - **Do the intimate encounters feel like real choices or like traps?** (If they're always mechanically optimal to Yield, the system is broken — Resist/Redirect need viable use cases.)
   - **Does the behavioral profile at run-end surprise you?** (If yes, the reflection system is working. If it just confirms what you already knew, it's not adding anything.)
3. One external playtester if available; watch silently, note where they stall.
4. Write a one-page findings document. Its last section answers the only question that matters: **does the 60-second loop from Phase 0 exist in the build, and is it worth 60 more seconds?** A secondary question: **does the behavioral mirror make you want to play differently next time?** Those answers decide whether the next milestone is character #2 or a loop redesign.

**DoD:** Findings document written. PoC judged.

---

## Explicitly Out of Scope

Cutting these is the plan working, not the plan failing:

- Second and third characters (manipulator, introvert)
- Psychology-driven world generation (consuming run history to alter floor generation)
- Bad End twisted-enemy variants (only the run record that feeds them — Phase 5)
- NPC factions and relationship tracking
- The meta-plot (dreamscape exploitation, cross-character narrative)
- Mechanical meta-progression / unlocks
- Multiple dungeon layers/biomes (PoC is one layer only)
- Art, music, and sound beyond placeholder rectangles and single-tone feedback
- Save-mid-run
- Any encounter verb beyond the two locked sets
- Field-of-view / fog of war (add post-PoC if exploration feels flat without it)
- Encounter scenes unique per flavor (the PoC uses one scene with data-driven verbs; dedicated scenes per flavor are a post-PoC upgrade if needed)

---

## Architecture Decisions (fixed, to stop re-decision churn)

| Decision | Choice | Reason |
|---|---|---|
| Cross-mode state | Single `GameState` autoload | One source of truth; everything else disposable |
| Scene communication | Signal bus (`Events` autoload) | Keeps the two modes independent |
| Turn model | One action per actor per tick | Simplest correct scheduler; energy systems are a post-PoC upgrade |
| Enemy/item/corruption definitions | Godot `Resource` files | New content = new data file, no code; this is the roster-expansion seam |
| Grid truth | Logical coordinates; tweens are presentation | Prevents the position-desync bug class entirely |
| Encounter verb sets | Driven by `verb_set` array on EnemyData resource | Menu doesn't assume which verbs exist; new verbs = new resource entries + resolution functions |
| Encounter routing | Dedicated router reads `encounter_flavor` enum | Single coupling point; new encounter types don't rewire existing systems |
| Trigger types | Enum on enemy spawner (`proximity`, `player_initiated`, `enemy_initiated`) | Emotional framing set at spawn time; encounter scene receives but doesn't determine it |
| Corruption verb effects | Transformation (override), not removal | Player always has full choice count; choices darken, they don't vanish |
| Run logging | Per-encounter verb-choice records + aggregates | Feeds the psychological-reflection thesis and future Bad End generation |
| Generation timing | Phase 8, after everything else works | Isolates generation bugs from gameplay bugs |

---

## Risks

1. **Phase 0 gets skipped or answered thematically.** Highest risk. Every downstream phase inherits the vagueness. The 60-second script is the gate; enforce it. Both encounter flavors must appear in the script.
2. **The corruption rule turns out unfun in Phase 5.** Acceptable — that discovery is the PoC's job. Change the rule (data file), not the framework.
3. **The intimate encounter set lacks mechanical depth.** If Yield is always optimal (high boon, low corruption cost relative to benefit), the encounter is solved and the choice is meaningless. Tuning this is Phase 9 work, but be aware: the Resist/Redirect verbs need to be viable *sometimes* or the encounter flavor collapses into "always pick the obvious button."
4. **Scope creep at Phase 3** (more verbs, more enemy behaviors) **and Phase 8** (fancier generation). The out-of-scope list is the defense; anything appealing goes on a post-PoC list, not in the build.
5. **The two modes drift apart in feel.** Watch for it at Phase 4; the transition presentation, shared status display, and trigger-type framing are the stitches.
6. **Verb mutation confuses instead of empowers.** If the player doesn't notice "Talk" became "Intimidate" and selects it expecting the old behavior, the corruption system punishes without communicating. Phase 7's mutation-announcement feedback is the defense — don't skip it.
7. **The behavioral profile feels judgmental instead of reflective.** Presentation matters. "You fought 8 times" is a mirror. "You resorted to violence 8 times" is a lecture. Keep the end-screen language neutral and descriptive. Let the player supply their own judgment.

---

## Data Schema Reference (quick-reference for implementation)

### EnemyData Resource
```gdscript
class_name EnemyData extends Resource

@export var enemy_name: String
@export var sprite: Texture2D
@export var encounter_flavor: StringName  # "combat" | "intimate"
@export var trigger_type: StringName      # "proximity" | "player_initiated" | "enemy_initiated"
@export var verb_set: Array[StringName]   # ["Fight","Talk","Flee","UseItem"] or ["Resist","Yield","Redirect","Flee"]

# Combat stats (shared)
@export var hp: int
@export var atk: int
@export var def_stat: int
@export var flee_difficulty: float

# Combat-specific
@export var talk_receptivity: bool
@export var dialogue_lines: Array[String]

# Intimate-specific
@export var yield_corruption_value: int
@export var resist_difficulty: float
@export var redirect_options: Array[String]
@export var boon_on_yield: Resource  # ItemData or StatBuff
```

### CorruptionTrack Resource
```gdscript
class_name CorruptionTrack extends Resource

@export var band_thresholds: Array[int]        # [25, 50, 75, 100]
@export var stat_modifiers_per_band: Array[Dictionary]  # [{"atk": +2, "max_hp": -5}, ...]
@export var verb_overrides_per_band: Array[Dictionary]  # [{"Talk": "Intimidate"}, {"Resist": "Overwhelm"}, ...]
@export var band_crossing_text: Array[String]   # interstitial lines
@export var bad_end_text: String
```

### Run Log Entry
```gdscript
var encounter_record := {
    "enemy_name": String,
    "encounter_flavor": StringName,
    "trigger_type": StringName,
    "verbs_chosen": Array[StringName],
    "outcome": StringName,
    "corruption_delta": int,
    "turns_elapsed": int
}
```
```

---

There she is. Tighter routing, richer encounter system, verb mutation instead of verb removal, full behavioral logging, and the encounter variant router as its own explicit phase so it never gets hand-waved into existence inside a larger task.

The schema reference at the bottom is new — figured you'd want the data shapes visible in one place rather than scattered across phase descriptions. If you want me to draft the actual Phase 0 one-pager (the 60-second script, the locked verb resolutions, the corruption triggers for the athlete specifically), say the word. I've got her voice in my head already — the athlete who dreams in adrenaline and wakes up sore in ways she can't explain.