# Technical Plan — Phases 1–4

Derived from `Dream-Space Proof of Concept — Implementation Plan (v2).md`.
All rules and numbers come from `design-lockdown.md` (the authoritative design
document). This file breaks the plan's Phases 1 through 4 into concrete tasks:
what files to create, what the node/scene structure is, which signals are used,
and how to test each task. Per-phase Definitions of Done are copied verbatim
from the implementation plan.

Engine: **Godot 4.x** (4.3 or later; see Decisions). Language: GDScript.

---

## Project conventions

Directory layout (kept flat and small; the PoC does not need deep nesting):

```
res://
  project.godot
  autoloads/
    game_state.gd        # GameState singleton
    events.gd            # Events signal bus singleton
  scenes/
    main.tscn / main.gd            # persistent root, mode switching
    exploration.tscn / exploration.gd
    encounter.tscn / encounter.gd
  actors/                # Phase 2: grid_actor, player, enemy
  resources/             # Phase 2/3: EnemyData script + .tres files
  docs/                  # design + planning documents (this file)
```

Scripts sit next to the scene they drive. Every `.gd` file opens with a
comment block: what the script is, why it exists, how it connects to other
scripts. Classes and functions get `##` doc comments.

**Signal bus contract** (fixed in Phase 1, used by everything after — the
signatures below are designed so Phases 3 and 4 never have to change them):

| Signal | Arguments | Emitted by | Consumed by |
|---|---|---|---|
| `encounter_triggered` | `enemy_data: Resource, trigger_type: StringName` | Exploration (dispatcher; debug key in Phase 1) | Main |
| `encounter_resolved` | `result: Dictionary` | Encounter | Main |
| `player_died` | — | Encounter (HP hits 0) | Main |
| `run_ended` | `reason: StringName` | Main / GameState | Main (end screens are Phase 6; Phase 1–4 just print) |

`result` payload shape (Phase 3 fills it fully; Phase 1 sends a stub):
`{ outcome: StringName, verbs_chosen: Array[StringName], turns_elapsed: int, corruption_delta: int }`.

Scenes never reference each other directly. Exploration and Encounter talk
only to the bus; Main is the only listener that switches modes. This is the
"Signal bus" and "Cross-mode state" rows of the Architecture Decisions table.

---

## Decisions

Choices made where the plan was ambiguous. Simplest option taken; scope not
expanded. (The plan's own Decision Log in `design-lockdown.md` still governs
design; these are implementation-level only.)

1. **Phase 4.5 excluded.** The task scope is "Phases 1 through 4 only";
   Phase 4.5 (Encounter Variant Routing) is a separate later phase. Phase 4's
   wiring keeps the `enter_encounter(enemy_data)` seam narrow so the router
   can be inserted in Phase 4.5 without rewiring.
   *(Superseded after the Phases 1–4 merge: Phase 4.5 was added to scope by
   request — see the Phase 4.5 section below. The narrow seam paid off as
   intended: inserting the router touched only Main.)*
2. **Godot 4.x, not 3.x.** The plan names Godot without a version. Godot 4 is
   current, and the plan's TileMap custom-data-layer approach and typed
   `Array[StringName]` exports are Godot 4 features.
3. **Tile size 16×16.** Not specified. 16 px divides the 640×360 logical
   resolution evenly (40×22.5 tiles), leaving room for a small floor plus UI.
4. **Phase 1 placeholder movement.** Phase 1's DoD requires "position
   preserved" across a mode switch, which is only testable if position can
   change. The exploration placeholder moves a rectangle in whole-tile steps
   and writes the grid position to GameState — no walls, no world tick. It is
   debug scaffolding, replaced by the real MOVE loop in Phase 2.
5. **Phase 1 HP debug key.** Phase 1's DoD requires "HP value set in one mode
   is readable in the other". The encounter placeholder binds H to subtract
   1 HP from GameState; both placeholder scenes display HP. Removed in
   Phase 3 when real verbs change HP.
6. **`EnemyData` resource script is created in Phase 2, not 3.** Phase 2's
   trigger dispatcher must emit "the actor's enemy resource", so the script
   (already fully specified in the plan's Data Schema Reference) is created
   when enemies first exist. Phase 3 adds the test `.tres` files and consumes
   the encounter-side fields.
7. **Flee return placement.** The plan says "place the player one cell away"
   and asks for a precise definition. Definition: the player's logical grid
   position never changes during an encounter, and for `player_initiated`
   encounters the player's move *into* the enemy's cell is not committed —
   the encounter fires instead of the step. So on flee/resist the player
   simply remains on the cell they occupied when the encounter fired, which
   is never the enemy's cell, plus one tick of encounter immunity per the
   lockdown. No relocation logic needed.
8. **Encounter immunity scope.** "One tick of encounter immunity" (lockdown
   §3) is implemented as a counter on the exploration scene, set from the
   `encounter_resolved` payload (`outcome` = fled/resisted), decremented at
   end of tick. While non-zero the trigger dispatcher skips all checks.
   Scene-local because it is exploration bookkeeping, not run state.
9. **Talk exchange representation.** The 2–3 line exchange (lockdown §3) is
   the enemy's `dialogue_lines` array; each Talk choice prints the next
   line, and printing the final line completes the exchange — the encounter
   ends peacefully on that same press (no dead extra press). While the
   exchange is in progress the enemy does not act: the lockdown only says
   "turn wasted, enemy acts" for the non-receptive case, and an enemy that
   attacks mid-conversation would punish the verb the design wants viable.
   Line index is encounter-local state.
10. **Intimate sequence stage display.** The lockdown's 3-stage sequence is
    tracked as an integer 0–3 in the encounter scene and shown as plain text
    ("Stage 2/3") on the status panel. Reaching stage 3 resolves as forced
    yield per lockdown §4.
11. **RNG.** GameState owns one `RandomNumberGenerator` seeded per run (seed
    stored, per Phase 1 task 3). All d100 rolls go through
    `GameState.roll_d100()` so Phase 6's seeded-replay requirement needs no
    retrofit.
12. **Boon on yield (Phase 3/4).** The lockdown's 60-second script grants "a
    heal item" on Yield. The only item type in Phases 1–4 is the heal item
    (+8 HP, lockdown §3), so `boon_on_yield` for the test intimate enemy is
    one heal item added to inventory.
13. **The floor is authored as an ASCII map constant, not editor-painted
    tile data.** The plan says "hand-author in the TileMap editor", but the
    editor stores painted cells as a binary blob (`tile_map_data`) that
    can't be hand-written or code-reviewed. An ASCII map in `exploration.gd`
    is still a hand-made floor — versionable, readable, edited by typing —
    and it builds the same `TileMapLayer` cells at load, so walkability
    still comes from the tileset's custom data layer as the plan requires.
    Spawn markers live in the same map (`@` entrance, `X` exit, `H` hostile,
    `B` beckoner) so the whole floor is one block of text. A third walkable
    tile type gives the exit a visible color.
14. **Two additions to the EnemyData schema:** `redirect_difficulty: float`
    (design-lockdown §4's Redirect roll needs it; the plan's schema lists
    `redirect_options` but omitted the difficulty value) and `color: Color`
    (placeholder-art stand-in for `sprite` until textures exist — Phase 2
    task 5 requires the beckoner to be visually distinct).
15. **"Spots the player" defined.** The plan asks for a spot flash but not a
    range: a proximity-type enemy flashes once per run when its Manhattan
    distance to the player first drops to 5 or less.
16. **Unspawned-position sentinel.** GameState can't know the floor's
    entrance tile (that's map data), so `reset_run()` sets `grid_position`
    to `NO_POSITION` (-1,-1) and Exploration snaps the player to the map's
    `@` cell when it sees the sentinel. Returning from an encounter keeps
    the real position, so mid-run reloads don't teleport the player.
17. **Opening framing lands in Phase 3, not 4.5.** Task 3.4's test replays
    the 60-second script, which starts with "it reached you, so it acts
    first" — impossible without the framing rule. So the encounter scene
    implements lockdown §7's framing (player_initiated → menu first;
    proximity/enemy_initiated → enemy acts first) as soon as it exists, and
    Phase 4.5 verifies it receives the real trigger type rather than adding
    the `if`.
18. **ItemData resource.** Phase 3's UseItem needs an item type, so items
    are data files like enemies: `ItemData { item_name, effect: StringName,
    amount: int }` with one effect ("heal", +8 capped at max HP, lockdown
    §3). `GameState.inventory` holds ItemData resources, and the beckoner's
    `boon_on_yield` points at the heal item file (Decision 12).
19. **No inventory submenu.** With exactly one item type in the PoC until
    Phase 9, UseItem consumes the first item in inventory directly.
    Choosing UseItem with an empty inventory is a menu-level rejection:
    narration only, no turn consumed, the enemy does not act.
20. **What "the enemy acts" means in an intimate encounter.** The sequence
    advancing IS the enemy's action. Failed Resist and Redirect already
    include their advance per lockdown §4; a failed Flee ("turn wasted,
    enemy acts") advances the stage by one, and an enemy-first opening of
    an intimate encounter (none in the test data) would too. Every intimate
    failure therefore advances the sequence exactly once.
21. **Encounter debug affordances replace the Phase 1 ones.** Escape no
    longer exits an encounter and the H damage key is gone — the verbs are
    now the only exit paths. Running `encounter.tscn` directly (F6, the
    plan's standalone test mode) loads the combat test enemy, seeds one
    heal item so UseItem is testable, and E swaps to the other test enemy
    and restarts. The in-game debug-E path (which passes null enemy data)
    falls back to the combat test enemy the same way.

---

## Phase 1 — Godot Skeleton

**Goal:** project boots, switches between two placeholder scenes via debug
keys, state survives the switch.

### Task 1.1 — Project configuration

- **Files:** `project.godot`, `icon.svg` (Godot default placeholder).
- **Settings:** application main scene = `scenes/main.tscn`; viewport
  640×360, stretch mode `canvas_items`, aspect `keep` (fixed logical
  resolution, scales up); 2D pixel snap on (`rendering/2d/snap/…`).
- **Input map (custom actions):** `move_up/down/left/right` (arrows + WASD),
  `wait` (Space), `confirm` (Enter/Z), `cancel` (Escape/X),
  `debug_encounter` (E). Exploration verbs and menu navigation only — per
  lockdown §2 there is no interact key.
- **Test:** project opens in the Godot editor with no import errors; the
  input actions appear in Project Settings.

### Task 1.2 — Autoload singletons

- **Files:** `autoloads/game_state.gd`, `autoloads/events.gd`; both
  registered as autoloads in `project.godot`.
- **`GameState`** holds exactly the plan's list: player HP (`hp`,
  `max_hp`), `corruption` (+ `corruption_max` 100), `inventory:
  Array`, `grid_position: Vector2i`, RNG (`rng_seed` + generator, see
  Decision 11), `run_log: Array` (empty until Phase 6 populates it richly),
  plus the athlete's locked start stats `atk` 5 / `def_stat` 2 and a
  `reset_run()` that restores lockdown §6 start values (HP 20/20,
  corruption 0, empty inventory).
- **`Events`** declares the four bus signals from the contract table above.
  No logic — a signal bus stays dumb.
- **Signals used:** declares all four; none emitted yet.
- **Test:** boot the game; no script errors; autoloads visible in the
  remote scene tree.

### Task 1.3 — Three top-level scenes

- **Files:** `scenes/main.tscn` + `main.gd`, `scenes/exploration.tscn` +
  `exploration.gd`, `scenes/encounter.tscn` + `encounter.gd`.
- **Node structure:**
  - `Main` (Node) — root, never unloaded. One child slot: the active mode
    scene, instantiated/freed by `main.gd`.
  - `Exploration` (Node2D) → `ColorRect` (floor-colored background),
    `Player` (ColorRect placeholder, positioned from
    `GameState.grid_position` × 16), `HpLabel` (Label, shows GameState HP).
  - `Encounter` (Node2D) → `EnemyRect` (ColorRect, top — the plan's
    "colored rectangle"), `StatusLabel` (Label, bottom-left: HP and
    corruption from GameState).
- **Test:** run the project; exploration placeholder appears with the player
  rect and HP label.

### Task 1.4 — Mode switching + debug keys

- **`main.gd`:** `enter_encounter(enemy_data)` frees the exploration
  instance and instantiates encounter; `exit_encounter(result)` does the
  reverse. Connected to `Events.encounter_triggered` / `encounter_resolved`
  in `_ready()`. Also connects `player_died` / `run_ended` to a
  `print` stub (real handling is Phase 6).
- **`exploration.gd`:** on `debug_encounter` (E) → emit
  `Events.encounter_triggered(null, &"debug")`. Placeholder movement per
  Decision 4 writes `GameState.grid_position`.
- **`encounter.gd`:** on `cancel` (Escape) → emit
  `Events.encounter_resolved({outcome = &"debug_exit"})`. Debug key H
  per Decision 5.
- **Signals used:** `encounter_triggered`, `encounter_resolved` (emitted);
  all four connected in Main.
- **Test = Phase 1 DoD:** *"Boot the game, press E, see the encounter
  placeholder, press Escape, return to exploration with position preserved.
  HP value set in one mode is readable in the other."* Concretely: move a
  few tiles, press E, press H twice (HP 20→18), press Escape — player rect
  is where it was, exploration HP label reads 18.

---

## Phase 2 — Mode 1: Grid Exploration

**Goal:** the MOVE loop is real — player steps, world ticks, feedback lands.

### Task 2.1 — TileMap floor

- **Files:** `resources/tileset.tres`, edit `scenes/exploration.tscn`
  (add a `TileMapLayer` node named `Floor`).
- Two tile types (floor, wall) as plain colored 16×16 tiles. Custom data
  layer `walkable: bool` on the tileset — walkability lives in the tile
  data, not a parallel array (per plan task 2.1).
- Hand-author one test floor in the editor: a few rooms/corridors, an
  entrance tile and an exit tile (exit behavior itself is win-condition
  wiring; for Phase 2 it is just a marked tile).
- **Test:** floor renders; querying a wall cell's custom data returns
  `walkable == false`.

### Task 2.2 — GridActor base

- **Files:** `actors/grid_actor.gd` (+ `actors/grid_actor.tscn` base scene:
  `GridActor` (Node2D) → `Rect` (ColorRect 16×16)).
- Holds `grid_pos: Vector2i` (logical truth). `move_to(cell)` updates
  `grid_pos` instantly, then tweens the pixel position over ~0.1 s —
  presentation only, never the source of truth (Architecture Decisions:
  "Grid truth").
- `bump(dir)` — half-step tween out and back, no logical change.
- **Test:** place one GridActor in the editor, call `move_to` from a debug
  key; logical position updates before the tween ends (print both).

### Task 2.3 — Player actor + input

- **Files:** `actors/player.gd` + `actors/player.tscn` (inherits GridActor).
  Replaces the Phase 1 placeholder rect in `exploration.tscn`; delete the
  Decision-4 debug movement.
- On directional input: target = `grid_pos + dir`. Walkable (tile custom
  data) and unoccupied (ask the scheduler's actor list) → move, turn taken.
  Otherwise → `bump()`, **no turn consumed** (lockdown §2). `wait` action:
  no move, turn taken.
- Writes `GameState.grid_position` after every committed step.
- **Test:** walk the floor; walls and occupied cells bump without the world
  ticking; open cells step.

### Task 2.4 — Turn scheduler

- **Files:** logic in `scenes/exploration.gd` (the plan places the scheduler
  in Exploration, not GameState).
- One action per actor per tick (Architecture Decisions: "Turn model"):
  player acts → each other actor acts once, in scene-tree order → end-of-tick
  trigger check (Task 2.6) → control returns to player. Input is ignored
  while a tick is resolving (a simple `is_ticking` flag; tweens are 0.1 s so
  no queueing needed).
- **Test:** each player step visibly advances every enemy exactly one step.
  Waiting also ticks the world.

### Task 2.5 — EnemyData resource + two enemy behaviors

- **Files:** `resources/enemy_data.gd` (the plan's Data Schema Reference,
  verbatim — all fields now, even the Phase 3 ones; see Decision 6),
  `actors/enemy.gd` + `actors/enemy.tscn` (inherits GridActor, exports an
  `EnemyData`), plus two Phase 2 test resources:
  `resources/enemies/test_hostile.tres` (`trigger_type = &"proximity"`),
  `resources/enemies/test_beckoner.tres` (`trigger_type =
  &"player_initiated"`).
- **Hostile wanderer:** each tick 50% straight-line step toward player
  (larger axis first), 50% random step; blocked steps are simply lost.
- **Beckoner:** stationary; visually distinct color per plan.
- Rolls use `GameState.roll_d100()` / rng (Decision 11).
- **Test:** hostile drifts toward the player over several ticks; beckoner
  never moves.

### Task 2.6 — Encounter trigger dispatcher

- **Files:** in `scenes/exploration.gd`, end-of-tick step.
- Per actor, check its declared `trigger_type` (lockdown §7):
  `proximity` → 4-way adjacent to player at end of tick;
  `player_initiated` → player's chosen step this tick targeted the actor's
  cell (the step is not committed — Decision 7);
  `enemy_initiated` → the actor stepped into the player's cell this tick.
  First match wins; emit `Events.encounter_triggered(actor.data,
  actor.data.trigger_type)` and stop the tick.
- Encounter-immunity counter (Decision 8) short-circuits the whole check.
- **Signals used:** emits `encounter_triggered`.
- **Test:** walking adjacent to the hostile fires the signal with
  `proximity`; stepping into the beckoner's cell fires it with
  `player_initiated` (print the arguments; Main still loads the placeholder
  encounter until Phase 4 passes real data through).

### Task 2.7 — Feedback pass

- Bump animation already in GridActor (2.2). Add: one-frame white flash on
  the hostile when it first becomes adjacent-or-visible-and-approaching
  ("spots you"), and a glow/pulse (modulate tween) on the beckoner when the
  player is within 1 cell.
- **Test = Phase 2 DoD:** *"Walk a hand-made floor. Walls block. A hostile
  wanders and pursues; adjacency fires the encounter signal. A beckoner sits
  visibly; stepping into its cell fires the encounter signal with a
  different trigger type. Every player action visibly advances the world one
  tick."*

---

## Phase 3 — Mode 2: Encounter Screen

**Goal:** the CHOOSE loop is real — menu, resolution, exit conditions.
Independent of Phase 2; needs only the Phase 1 skeleton. Testable by running
`encounter.tscn` directly (Godot's run-current-scene), with a fallback test
enemy loaded when none was injected.

### Task 3.1 — Layout

- **Files:** rebuild `scenes/encounter.tscn`.
- **Node structure:** `Encounter` (Node2D) → `CanvasLayer` →
  - `EnemySprite` (TextureRect or ColorRect, top center),
  - `StatusPanel` (PanelContainer, bottom-left: HP `20/20`, corruption
    `0/100`, and — for intimate encounters — the sequence stage,
    Decision 10),
  - `VerbMenu` (PanelContainer bottom-right → VBoxContainer of Labels;
    up/down moves a highlight, `confirm` selects — Pokémon layout, no
    innovation),
  - `NarrationLabel` (bottom strip for resolution text: "It only growls").
- **Test:** scene runs standalone and renders all four regions.

### Task 3.2 — Test enemy resources

- **Files:** `resources/enemies/test_combat.tres` (flavor `combat`,
  `verb_set = ["Fight","Talk","Flee","UseItem"]`, `talk_receptivity`,
  2–3 `dialogue_lines`, `flee_difficulty`) and
  `resources/enemies/test_intimate.tres` (flavor `intimate`, `verb_set =
  ["Resist","Yield","Redirect","Flee"]`, `yield_corruption_value = 10`,
  `resist_difficulty`, one `redirect_options` entry, `boon_on_yield` = heal
  item, Decision 12). Stats per the 60-second script's shadow: HP/ATK 4/DEF 2.
- The menu renders **only** what `verb_set` lists — no hardcoded verb
  assumptions (Architecture Decisions: "Encounter verb sets").
- **Test:** loading each resource renders its own four verbs.

### Task 3.3 — Generic verb resolution

- **Files:** `scenes/encounter.gd`.
- A `Dictionary` maps verb `StringName` → `Callable`. Selecting a menu item
  looks up and calls; the scene never switches on encounter flavor
  (plan task 3.5). Adding a verb = one function + one `verb_set` entry.
- **Test:** a verb name present in a resource but missing from the map logs
  a clear error instead of crashing.

### Task 3.4 — Combat verb set (lockdown §3, verbatim)

- **Fight:** damage = ATK − DEF, min 1; then enemy counterattacks, same
  formula.
- **Talk:** `talk_receptivity` true → advance dialogue (Decision 9),
  completion ends peacefully; false → "wasted turn" narration, enemy acts.
- **Flee:** d100 ≥ `flee_difficulty` × 100 → exit with one-tick immunity
  flag in the payload; fail → enemy acts.
- **UseItem:** inventory list; consume heal → +8 HP capped at `max_hp`;
  enemy acts.
- **Test:** scripted sequence from the 60-second script reproduces exactly:
  enemy first strike 20→18 HP, failed Talk →16, Fight deals 3, counter →14,
  two more Fights kill it.

### Task 3.5 — Intimate verb set (lockdown §4, verbatim)

- Stage counter 0→3 (Decision 10). **Resist:** d100 vs
  `resist_difficulty`×100; success exits (+immunity); fail → corruption +2,
  stage +1. **Yield:** corruption +`yield_corruption_value`; boon granted;
  peaceful end. **Redirect:** requires non-empty `redirect_options`; d100 vs
  `redirect_difficulty`×100; success → clean exit, no corruption, no boon;
  fail → stage +1. **Flee:** same function as combat Flee — shared code.
  Stage 3 reached → **forced yield**: corruption +`yield_corruption_value`,
  **no boon**, encounter ends.
- **Test:** force rolls (temporarily seed rng) to hit each branch; verify
  forced yield grants no boon.

### Task 3.6 — Turn structure

- Strict alternation: player chooses → resolution narration → enemy acts (if
  the encounter didn't end) → menu returns. Trigger-type opening framing
  (`player_initiated` → menu first; others → enemy acts first, per lockdown
  §7) — the framing `if` itself is Phase 4.5's task 3, **but** the encounter
  must already accept `trigger_type` in its setup payload so 4.5 is a
  data-read, not a refactor. For Phase 3 standalone runs, default framing:
  enemy first.
- **Test:** every verb that "wastes the turn" is followed by exactly one
  enemy action.

### Task 3.7 — Exit paths + payload

- Paths: enemy HP 0, talk/redirect success, yield (chosen or forced), flee/
  resist success, player HP ≤ 0.
- Each emits `Events.encounter_resolved(result)` with the full payload
  (`outcome`, ordered `verbs_chosen`, `turns_elapsed`, `corruption_delta`);
  player death emits `Events.player_died` instead.
- **Signals used:** `encounter_resolved`, `player_died`.
- **Test:** print handler in Main; verify each path's payload, including
  `verbs_chosen` order.

### Task 3.8 — Corruption hook

- Both lockdown §5 triggers implemented here: Fight chosen against a
  talk-receptive enemy → corruption +3; Yield → +`yield_corruption_value`;
  (Resist failure's +2 arrives via Task 3.5). All go through one
  `GameState`-mutating helper that also updates the StatusPanel immediately
  — the consequence must be visible at the moment of choice. Corruption ≥
  100 → `Events.run_ended(&"corruption")` (band system itself is Phase 5).
- **Test = Phase 3 DoD:** *"Launch the encounter scene directly with a test
  combat enemy resource and a test intimate enemy resource. All verbs in
  both sets resolve correctly. Corruption visibly changes when either
  trigger condition fires. All exit paths emit correct signals with full
  payloads including `verbs_chosen`."*

---

## Phase 4 — The Transition

**Goal:** the two independent systems become one game.

### Task 4.1 — Wire trigger → real encounter

- **Files:** `scenes/main.gd`.
- `enter_encounter(enemy_data, trigger_type)` now passes the triggering
  enemy's resource + trigger type into the encounter scene's setup before
  adding it to the tree. Remove the Phase 1 `debug_encounter` key path.
- **Test:** meeting the hostile opens an encounter showing that enemy's
  stats; stepping into the beckoner opens the intimate verb set.

### Task 4.2 — Wire resolution → grid consequences

- **Files:** `scenes/exploration.gd`, `scenes/main.gd`.
- Exploration keeps its instance alive across the encounter? **No** — per
  Phase 1 architecture Main frees/reloads mode scenes, so exploration must
  rebuild from state: enemy roster (which enemies remain, with grid
  positions) moves into `GameState` as scene-restore data. On
  `encounter_resolved`, Main applies the outcome before reloading
  exploration: victory / talk-down / redirect-down / yield → remove that
  enemy from the roster (yield additionally grants the boon into
  inventory); flee / resist → enemy stays; player position unchanged
  (Decision 7) and the immunity counter is armed from the payload
  (Decision 8).
- **Test:** each outcome leaves the grid in the documented state; a fled-from
  enemy is still there; a defeated one is gone.

### Task 4.3 — Transition presentation

- 0.3 s fade both directions: a full-screen `ColorRect` on a high
  `CanvasLayer` in Main, alpha-tweened around the scene swap. (The script's
  "shatter" is flavor; a fade is the cheap version the plan allows.)
- **Test:** both directions fade; no input leaks through mid-fade.

### Task 4.4 — State audit

- Write the carry-across list into this file (append below) and assert it:
  **carries across:** HP/max HP, corruption, inventory, grid position,
  enemy roster, RNG state, run log. **Must not carry:** encounter-local
  state (stage counter, dialogue index, verbs_chosen buffer), tweens,
  immunity counter (exploration-local, armed via payload).
- **Test = Phase 4 DoD:** *"A full loop with no debug keys: explore → get
  caught or approach → resolve by any verb → return to the grid in a
  consistent state → repeat. Fleeing does not chain-trigger. Both encounter
  flavors fire from their respective trigger types."*

---

## Phase 4.5 — Encounter Variant Routing

**Goal:** the system knows which encounter *flow* to run based on enemy
data, and is prepared for future variants without rewiring.

### Task 4.5.1 — The router

- **Files:** `scenes/encounter_router.gd` (new).
- A dedicated script (the plan's alternative to putting it in Main), used
  only by Main. It owns one lookup table: `encounter_flavor` →
  `PackedScene`. For the PoC both real flavors map to the same
  `encounter.tscn`, which differentiates itself by the resource's
  `verb_set` — but the table is the explicit decision point: *this* flavor
  produces *this* flow. Post-PoC, a puzzle or chase encounter is one new
  table entry pointing at a different scene, and no other system changes.
- `build_encounter(enemy_data, trigger_type) -> Node` instantiates the
  routed scene and injects data + trigger type via `setup()` before
  returning it. An unknown flavor logs a content error and falls back to
  the default encounter scene rather than crashing.
- **Test:** combat and intimate enemies still route into working
  encounters.

### Task 4.5.2 — Main delegates to the router

- **Files:** `scenes/main.gd`.
- `enter_encounter()` shrinks to "ask the router, swap to what it returns".
  Main no longer preloads or instantiates `encounter.tscn` itself.
- **Test:** the full Phase 4 loop is unchanged in behavior.

### Task 4.5.3 — Trigger-type framing confirmed through the router

- Already implemented in Phase 3 (Decision 17); the router forwards
  `trigger_type` untouched. The framing test is now: proximity encounter →
  enemy strikes first; beckoner step-in → menu first — both *through* the
  router path.

### Task 4.5.4 — The dummy third flavor

- **Files:** `resources/enemies/test_dummy.tres` (new), appended to the
  encounter scene's standalone F6 test cycle.
- A "strange" flavor entry in the router table points at the same scene; a
  test enemy declares it. The encounter scene has no `match` on flavor
  anywhere — only two `if flavor == "intimate"` presentation branches — so
  an unknown flavor simply behaves like a menu-driven encounter with
  whatever verbs its data lists. Nothing may crash; that proves new
  variants don't rewire existing systems.
- **Test = Phase 4.5 DoD:** *"Both encounter flavors route correctly
  through the router. Trigger type influences opening framing. A dummy
  third flavor value loads without errors. Neither Exploration nor
  Encounter scenes reference the router or each other directly."*

### Phase 4.5 decisions

22. **Flavors stay StringNames, not a Godot enum.** The plan says "enum",
    but a hard `enum` would put flavor names in code, defeating the
    data-file seam. The router's Dictionary keys ARE the enum; adding a
    flavor = adding a key. The dummy flavor is named `&"strange"`.
23. **The router is a plain class with a static method, not an autoload.**
    Only Main calls it, and it holds no state — an autoload would advertise
    it to scenes that must not know it exists.

---

## Phase 5 — The Athlete's Corruption Arc

**Goal:** the corruption number becomes the character. Bands shift stats,
mutate verbs, and change her body; max corruption is a distinct Bad End.
All of it defined in data a second character could reuse.

### Task 5.1 — CorruptionTrack resource + band engine

- **Files:** `resources/corruption_track.gd` (the plan's schema, verbatim),
  `resources/corruption/athlete_track.tres`, `autoloads/game_state.gd`,
  `autoloads/events.gd`.
- Bands per lockdown §6: 0–24 / 25–49 / 50–74 / 75–99 / 100 = end, i.e.
  thresholds `[25, 50, 75, 100]`. All corruption mutation moves into
  `GameState.add_corruption()`: it computes bands before/after, applies each
  crossed band's stat modifiers (lockdown §5: ATK +2, max HP −5 per
  crossing), and emits a new bus signal
  `corruption_band_crossed(band, crossing_text)` — an event at the moment
  of crossing, never a per-frame check (plan task 5.1).
- **Test:** corruption 24→25 fires the signal once and shifts stats once;
  24→55 fires twice.

### Task 5.2 — Verb mutation, data-driven

- **Files:** `scenes/encounter.gd`.
- The track's `verb_overrides_per_band` holds cumulative substitutions:
  entering band 2 turns Talk into Intimidate, band 3 turns Resist into
  Overwhelm (lockdown §5 / plan task 5.2). GameState merges the overrides
  up to the current band; the encounter renders and dispatches the
  *effective* verb name — same slot, darker meaning, never a removed
  option. Two new resolution functions join the verb dictionary:
  - **Intimidate:** always ends the encounter; the enemy flees the grid.
    No corruption change in either direction ("no corruption refund").
  - **Overwhelm:** ends the intimate encounter by force — no boon, minor
    HP cost.
- A band crossed mid-encounter re-renders the menu immediately (the
  first-mutation flash is Phase 7's task; the substitution itself must
  already be live).
- **Test:** at corruption 50+, Talk renders as Intimidate and resolves as
  Intimidate; at 75+, Resist renders as Overwhelm.

### Task 5.3 — Presentation per band

- **Files:** `actors/player.gd`, `scenes/exploration.gd`,
  `scenes/encounter.gd`, both status labels.
- Player rect color lerps from her yellow toward a corrupted crimson by
  band (the palette-swap stand-in until sprites exist). Band crossings
  append the track's `band_crossing_text` line to the encounter narration.
  Status panels state the numbers: ATK and DEF join HP and corruption.
- **Test:** yield repeatedly; the rect darkens, the panel's ATK climbs and
  max HP falls at each threshold.

### Task 5.4 — Bad End + RunHistory seam

- **Files:** `resources/run_history.gd`, `scenes/main.gd`, `main.tscn`,
  `autoloads/game_state.gd`.
- Corruption 100 ends the run distinctly from HP death: Main shows a
  full-screen overlay (the track's `bad_end_text`, red-black) and pauses
  the tree; HP death gets its own overlay text. On either end, GameState
  writes the run-end record — character, cause, corruption, seed, and the
  full verb history from the run log — into `user://run_history.tres` (a
  RunHistory resource). Build the seam, not the Bad End feature.
- **Test:** end a run both ways; two records with different causes exist in
  the user:// file; each contains the encounters' verbs_chosen arrays.

### Phase 5 decisions

24. **Band arrays align with thresholds.** `band_thresholds[i]` crossed ⇒
    `stat_modifiers_per_band[i]` applies and
    `verb_overrides_per_band[i]` joins the cumulative merge. Overrides
    accumulate — at band 3 both the band-2 and band-3 mutations are live.
25. **Intimidate and Overwhelm resolution details** (the plan gives one
    line each; the numbers must come from somewhere): Intimidate always
    succeeds, works regardless of talk_receptivity (power purchased with
    self), and removes the enemy from the grid — outcome `intimidated`.
    Overwhelm costs 2 HP, removes the enemy, grants no boon — outcome
    `overwhelmed`; if the 2 HP is all she has, she dies (loss condition 1
    applies — the body pays).
26. **Corruption mutation is centralized in GameState.** The encounter no
    longer touches `GameState.corruption` directly; it calls
    `add_corruption()` and reacts to the band-crossed signal. Loss
    condition 2 also emits from GameState now, not the encounter.
27. **Minimal end overlay, not end screens.** Both loss conditions show a
    distinct full-screen overlay in Main and pause the tree; restarting is
    re-running the game (F5). The title → run → end → title loop is
    Phase 6's task 1, untouched.
28. **Run-log appending arrives with Phase 5.** The plan schedules it for
    Phase 6, but Phase 5's run-end record consumes "the full verb history
    from the run log", so Main appends the plan-schema encounter record at
    resolution time now. The encounter that ends the run is not yet logged
    — player death emits no encounter_resolved, and a corruption max
    writes the run record the instant the threshold is crossed, before the
    encounter can resolve. Phase 6 owns that refinement (log the in-flight
    encounter at run end).
29. **RunHistory format:** `user://run_history.tres`, a RunHistory resource
    holding an array of per-run dictionaries {character, cause, corruption,
    rng_seed, run_log}. Aggregates (verb frequencies, curves) are Phase 6.
30. **Debug corruption key.** Phase 2's content caps reachable corruption
    around ~19, far below band 1 — the arc is untestable in-game until
    Phase 9's content pass. H (the retired debug_damage action, renamed
    `debug_corrupt`) adds +10 corruption in exploration and in the
    encounter's standalone F6 mode. Real-game encounters ignore it.

---

## Phase 6 — Run Structure & Meta-Layer Stub

**Goal:** the game has a beginning, an end, and a next time. Title → run →
end screen → title, seeded runs, per-run behavioral profile, history that
survives restarts. Knowledge is the only meta-progression.

### Task 6.1 — Title and end screens as mode scenes

- **Files:** `scenes/title.tscn/.gd`, `scenes/end_screen.tscn/.gd`,
  `scenes/main.gd`, `scenes/main.tscn`, `autoloads/events.gd`.
- Title and end screens join Exploration/Encounter as swappable mode
  scenes under Main; Phase 5's end overlay + tree pause is removed (it was
  Decision 27's stopgap). Boot lands on the title. Two bus signals join
  the contract: `new_run_requested` (title confirm) and `title_requested`
  (end-screen confirm) — the screens stay bus-only like every other scene.
- Main's `_swap_to` serializes (queues behind an in-flight fade) so
  run_ended arriving near a swap can never interleave two transitions.
- **Test:** boot → title → Enter starts a run → dying/ending returns
  through the end screen → Enter → title → Enter starts a fresh run.

### Task 6.2 — Win condition and full reset

- **Files:** `scenes/exploration.gd`, `autoloads/game_state.gd`.
- Stepping onto the exit tile ends the run with cause "win" (lockdown §6
  finally wired). New run = `GameState.reset_run()` — everything resets
  except the RunHistory file on disk.
- **Test:** walk to the green tile; the end screen says she made it out;
  three consecutive runs need no relaunch.

### Task 6.3 — Run logging closes its gap; aggregates on record

- **Files:** `scenes/encounter.gd`, `scenes/main.gd`,
  `autoloads/game_state.gd`.
- The encounter logs its own record on *every* exit — including the two
  Phase 5 couldn't: player death (outcome "death") and mid-encounter
  corruption max (outcome "corruption_end") — guarded so no encounter logs
  twice. Main's resolution-time logging is removed.
- Recording to disk defers from `end_run()` to the end screen's `_ready`,
  which closes the ordering hole (the run record used to be written before
  the fatal encounter could append itself). The record gains the plan's
  aggregates: encounter count, verb frequency counts, corruption curve.
- **Test:** die mid-encounter; the saved record's run_log includes that
  encounter with its verbs_chosen.

### Task 6.4 — The behavioral mirror

- **Files:** `scenes/end_screen.gd`.
- The end screen shows: cause (corruption max gets the track's Bad End
  text on an armor-red field — the distinctness requirement survives the
  overlay's removal), the seed, this run's profile ("Encounters: 3.
  Fight: 4. Yield: 1.") in neutral, descriptive language (plan risk 7),
  and the history block: runs played, causes tally, best result. The
  title screen shows runs-played so the meta-layer is visible from boot.
- **Test = Phase 6 DoD:** *"Can play three consecutive runs without
  restarting the program. History persists across program restarts. Each
  run's behavioral profile is visible on the end screen."*

### Phase 6 decisions

31. **Screens are mode scenes, not overlays.** Phase 5's overlay + paused
    tree is replaced by real title/end scenes in Main's swap slot; pausing
    is gone entirely. Distinct-Bad-End presentation moves into the end
    screen (armor-red tint + bad_end_text headline).
32. **Deferred disk write.** `end_run()` only marks the run over (storing
    `run_end_cause`) and emits; the single `record_run_end()` disk write
    happens in the end screen's `_ready`, by which point the fatal
    encounter has appended its own record. `run_recorded` guards
    double-writes.
33. **Aggregate formats.** `verb_counts` is a name→count dictionary;
    `corruption_curve` is the per-encounter corruption_delta array in
    encounter order; "best result" = the win with the lowest corruption.
    History shows tallies and best, not every past profile — a 640×360
    screen can't hold them all; full profiles stay in the .tres records.
34. **Scene-freeze flag renamed.** Exploration's `_encounter_fired` became
    `_scene_frozen` — the win path freezes the scene the same way a
    trigger does, and the name should say what it means, not its first
    use case.

---

## Phase 7 — Environmental Polish & Feedback

**Goal:** the game *feels* like something. Inputs are acknowledged,
corruption shifts are unmissable, a first-time player can parse events
without reading code. All presentation — no rules change in this phase.

### Task 7.1 — Sound stubs

- **Files:** `assets/sfx/*.wav` (generated), `autoloads/sfx.gd`,
  `project.godot`, triggers in `exploration.gd` / `encounter.gd`.
- The plan's five events get single tones: move, bump, encounter start,
  corruption gain, verb confirm. The tones are tiny generated sine WAVs
  (enveloped so they don't click); a third autoload `Sfx` owns a small
  round-robin AudioStreamPlayer pool and a `play(name)` API. Silence is
  not acceptable (plan task 7.5); beeps are.
- **Test:** every listed event makes a distinct sound; rapid steps don't
  cut each other off.

### Task 7.2 — Exploration juice

- **Files:** `scenes/exploration.gd`, `actors/enemy.gd`.
- Footstep puff: a small quad at the departed cell that fades and shrinks
  (~0.25s), spawned on every committed player step. Enemy idle: the
  visual rect bobs ±1px on a slow loop — the grid position never moves.
- **Test:** walking leaves a fading trace; idle enemies visibly breathe.

### Task 7.3 — Encounter juice

- **Files:** `scenes/encounter.gd`, `scenes/encounter.tscn`.
- Screen shake (±3px, 0.15s) on any HP damage, either direction. Narration
  text crawls (~60 chars/s, capped so long lines don't drag). Corruption
  gain ticks the displayed number up over ~0.4s instead of snapping — the
  pause IS the moment of consequence.
- **Test:** the 60-second script's opening strike shakes the screen and
  crawls its line; a Yield visibly counts 0→10.

### Task 7.4 — Verb mutation announcement

- **Files:** `scenes/encounter.gd`, `autoloads/game_state.gd`.
- The first time a mutated verb *renders in a menu* this run, its slot
  flashes and briefly reads "Talk → Intimidate" before settling on the new
  name. Announced verbs are tracked per run in GameState (the crossing may
  happen in an encounter whose menu doesn't contain the mutated slot —
  the announcement waits for the moment it matters, plan task 7.3 / risk 6).
- **Test:** cross band 2 in an intimate encounter; the next combat
  encounter's menu flashes Talk's slot.

### Task 7.5 — Band-crossing interstitial

- **Files:** `scenes/encounter.gd`, `scenes/encounter.tscn`.
- Crossing a band inside an encounter raises a full-screen tinted overlay
  with the track's crossing line: ~0.8s hold, ~0.3s fade, input gated
  while it's up. Marks the moment without interrupting flow for long.
- **Test:** H to 25 in standalone mode; the overlay holds, fades, play
  resumes.

### Phase 7 decisions

35. **Camera follow skipped.** The hand-made floor is exactly one screen
    (640×352 of a 640×360 viewport); a limit-clamped camera cannot move,
    so "camera follow with slight lag" is a no-op here. Deferred to
    Phase 8, where generated floors may exceed the screen. The movement
    feel the camera was meant to add comes from step tweens + footstep
    puffs.
36. **Cheap juice over systems.** The footstep "particle" is a tweened
    fading quad, not a particle system — same read, a tenth of the
    config. The enemy idle bob moves only the visual rect; grid truth is
    untouched (Architecture Decisions: "Grid truth").
37. **A third autoload (Sfx).** Phase 1 fixed GameState + Events; sound is
    the first genuinely cross-scene *service* since (exploration,
    encounter, and the F6 standalone mode all need it, so it can't live in
    Main). The Events bus stays signal-only.
38. **Mutation announcements are render-time, run-scoped.** GameState
    keeps the announced list (reset per run); the flash fires when the
    mutated verb first appears in a menu, not when the band crosses —
    "the moment it matters" is when the slot is selectable.
39. **Interstitial lives inside the encounter scene**, not a separate
    screen: band crossings can only happen there, and a scene swap for a
    half-second beat would fight the fade system.

---

## State audit (Phase 4, task 4.4)

The definitive list of what crosses a mode switch. Anything not listed
under "carries across" must not survive one — if it turns out to matter
after a switch, it gets promoted into GameState deliberately, not smuggled.

**Carries across (lives in GameState):**

- `hp`, `max_hp`, `atk`, `def_stat` — the athlete's body
- `corruption` — the run's moral ledger
- `inventory` — ItemData resources (granted by Yield boons, consumed by
  UseItem)
- `grid_position` — where the athlete stands (`NO_POSITION` until first
  spawn)
- `enemy_roster` + `roster_initialized` — who remains on the grid and
  where; seeded from the map once per run, edited only by Main on outcomes
- `engaged_enemy_index` — transfer field: set by Exploration at trigger
  time, consumed and reset by Main at resolution time
- `pending_immunity_ticks` — transfer field: armed by Main on fled/resisted,
  drained into Exploration's local counter on its next load
- `rng` + `rng_seed` — the run's one random stream
- `run_log` — reserved; Phase 6 fills it

**Must NOT carry across (scene-local, rebuilt or discarded):**

- Encounter: `_stage`, `_dialogue_index`, `_verbs_chosen`, `_turns_elapsed`,
  `_corruption_delta`, `_menu_index`, `_enemy_hp` — walking away and coming
  back starts the encounter over by design
- Exploration: `_immunity_ticks` (armed via the transfer field, then
  tick-local), `_is_ticking`, `_encounter_fired`, spawn-marker arrays, the
  actor instances and their tweens
- Main: `_switching`, the fade rect's alpha

---

## Out-of-scope guard (things these phases must NOT do)

From the plan's Explicitly Out of Scope list, the entries these four phases
could accidentally violate: no second character, no procedural generation
(hand-made floor only), no verbs beyond the two locked sets, no verb
mutation/bands (Phase 5), no run history persistence (Phase 6), no juice
beyond the listed feedback minimums (Phase 7), no field-of-view, no
save-mid-run, no per-flavor encounter scenes (one scene, data-driven verbs).
