# Dream-Space PoC — Phase 0 Design Lockdown (DRAFT for approval)

Status: **DRAFT.** Items marked [DECIDE] are proposed defaults, not settled facts. Approve or amend each, delete the markers, commit to `docs/design-lockdown.md`, and re-run the gate.

---

## 1. The 60-Second Script

You press up. The athlete steps one tile north; the world ticks — a hulking shadow two tiles east takes a step toward you. You press up again. She steps; the shadow closes to adjacent; the encounter fires and the screen shatters into the encounter view. The shadow fills the top of the screen; your HP (20) and corruption (0) sit bottom-left; the menu bottom-right reads Fight / Talk / Flee / Use Item. It reached you, so it acts first: its ATK 4 minus your DEF 2 drops your HP to 18; the number flashes. You press down to highlight Talk and confirm. It is not receptive — "It only growls" prints, and it strikes again: HP 16. You select Fight. Your ATK 5 minus its DEF 2 deals 3; its HP bar drops; it counterattacks: HP 14. You select Fight again; its HP hits 0; it collapses; the screen shatters back to the grid and its tile is empty. You press right twice; the world ticks twice; nothing moves. In a wall alcove ahead, a pale figure glows, stationary — a beckoner. You press right a third time, stepping deliberately into its cell. The encounter fires with the invitation framing: your menu appears first, reading Resist / Yield / Redirect / Flee. The figure offers warmth for a price; the panel shows corruption 0. You select Yield. Corruption ticks visibly up to 10; the figure presses a heal item into your hands; the encounter ends and the grid returns, the alcove empty. Corruption 10 now sits under your HP. You press up toward the corridor, and the world ticks on.

*(Both flavors present; every input and every response named, in order. No sentence contains a system without a mechanical rule below.)*

## 2. Exploration Verb Set

- **Movement: 4-way.** [DECIDE] Simpler input, cleaner adjacency checks, matches the classic-roguelike feel of the PoC. 8-way is a post-PoC question.
- **Move** — if target cell is walkable and unoccupied: step, world ticks. Otherwise: bump animation, no turn consumed.
- **Wait** — player skips their action; every other actor still ticks. (Tactical use: let a patroller pass, bait a wanderer.)
- **Interact: CUT.** [DECIDE] Nothing in the PoC needs it — beckoners trigger by step-in, items pick up on walk-over, the exit fires on entry. Cutting it keeps input to arrows + one wait key.

## 3. Combat Verb Set (all four confirmed)

- **Fight** — damage = attacker ATK − defender DEF, minimum 1, subtracted from HP; enemy counterattacks with the same formula.
- **Talk** — if `talk_receptivity` is true: advance a 2–3 line exchange; completing it ends the encounter peacefully. If false: turn wasted, enemy acts.
- **Flee** — roll d100; success if roll ≥ `flee_difficulty` × 100. Success exits the encounter with one tick of encounter immunity; failure wastes the turn, enemy acts.
- **Use Item** — open inventory, consume one item, apply its effect (heal = +8 HP, capped at max HP [DECIDE]); enemy acts.

## 4. Intimate Verb Set (all four confirmed)

Intimate enemies run a 3-stage sequence. Each failed Resist or Redirect advances it one stage; if it completes, the encounter resolves as a **forced yield**: corruption + `yield_corruption_value`, no boon. [DECIDE — this closes the "what happens if you keep failing" hole; without it, failure has no endpoint.]

- **Resist** — roll d100 vs `resist_difficulty` × 100; success ends the encounter (exit, one tick immunity); failure: corruption +2, sequence advances.
- **Yield** — corruption + `yield_corruption_value` (default 10 [DECIDE]); encounter ends peacefully; boon granted. The transaction is explicit on-screen.
- **Redirect** — if `redirect_options` is non-empty, roll d100 vs `redirect_difficulty` × 100 [DECIDE — plan gives no resolution mechanism; a roll parallels Flee/Resist]; success ends the encounter with no corruption and no boon; failure wastes the turn, sequence advances.
- **Flee** — identical to combat Flee, shared code.

## 5. The Athlete's Corruption Triggers

- **Combat:** When the player chooses **Fight against a talk-receptive enemy**, corruption increases by **3**, which causes the corruption track to advance toward its band thresholds (each band crossed: ATK +2, max HP −5, and the band's verb mutation applies). [DECIDE on the 3.]
- **Intimate:** When the player chooses **Yield**, corruption increases by **`yield_corruption_value` (default 10)**, which causes the same band advancement. Per the plan's intent, the intimate trigger pays more per firing than the combat trigger (10 vs 3); Resist-failure's +2 is a lesser third feed into the same track.

## 6. Run Shape

- **Start:** athlete spawns on the entrance tile of the hand-made floor. HP 20 / 20, corruption 0 / 100, empty inventory, ATK 5, DEF 2. [DECIDE on all numbers.]
- **Win:** step onto the exit tile.
- **Loss 1:** HP ≤ 0 (death end screen).
- **Loss 2:** corruption ≥ 100 (the armor takes her — distinct Bad End screen). Bands per the schema: 0–24 / 25–49 / 50–74 / 75–99 / 100 = end.

## 7. Encounter Trigger Types (enum, confirmed as specified)

- `proximity` — enemy adjacent to player at end of tick (standard hostile).
- `player_initiated` — player steps into the enemy's cell deliberately (beckoner).
- `enemy_initiated` — enemy steps into the player's cell (ambush).
- Each enemy resource declares exactly one. Trigger type sets opening framing: `player_initiated` → player menu first; the other two → enemy acts first.
