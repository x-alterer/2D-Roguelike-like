# Dream-Space PoC — Phase 0 Design Lockdown

Status: **LOCKED** (2026-07-06). Amendments require editing this document first; code follows the document, never the reverse.

---

## 1. The 60-Second Script

You press up. The athlete steps one tile north; the world ticks — a hulking shadow two tiles east takes a step toward you. You press up again. She steps; the shadow closes to adjacent; the encounter fires and the screen shatters into the encounter view. The shadow fills the top of the screen; your HP (20) and corruption (0) sit bottom-left; the menu bottom-right reads Fight / Talk / Flee / Use Item. It reached you, so it acts first: its ATK 4 minus your DEF 2 drops your HP to 18; the number flashes. You press down to highlight Talk and confirm. It is not receptive — "It only growls" prints, and it strikes again: HP 16. You select Fight. Your ATK 5 minus its DEF 2 deals 3; its HP bar drops; it counterattacks: HP 14. You select Fight again; its HP hits 0; it collapses; the screen shatters back to the grid and its tile is empty. You press right twice; the world ticks twice; nothing moves. In a wall alcove ahead, a pale figure glows, stationary — a beckoner. You press right a third time, stepping deliberately into its cell. The encounter fires with the invitation framing: your menu appears first, reading Resist / Yield / Redirect / Flee. The figure offers warmth for a price; the panel shows corruption 0. You select Yield. Corruption ticks visibly up to 10; the figure presses a heal item into your hands; the encounter ends and the grid returns, the alcove empty. Corruption 10 now sits under your HP. You press up toward the corridor, and the world ticks on.

## 2. Exploration Verb Set

- **Movement: 4-way.**
- **Move** — if target cell is walkable and unoccupied: step, world ticks. Otherwise: bump animation, no turn consumed.
- **Wait** — player skips their action; every other actor still ticks.
- **Interact: cut.** Beckoners trigger by step-in, items pick up on walk-over, the exit fires on entry. Input surface: four directions plus one wait key.

## 3. Combat Verb Set

- **Fight** — damage = attacker ATK − defender DEF, minimum 1, subtracted from HP; enemy counterattacks with the same formula.
- **Talk** — if `talk_receptivity` is true: advance a 2–3 line exchange; completing it ends the encounter peacefully. If false: turn wasted, enemy acts.
- **Flee** — roll d100; success if roll ≥ `flee_difficulty` × 100. Success exits the encounter with one tick of encounter immunity; failure wastes the turn, enemy acts.
- **Use Item** — open inventory, consume one item, apply its effect (heal = +8 HP, capped at max HP); enemy acts.

## 4. Intimate Verb Set

Intimate enemies run a **3-stage sequence**. Each failed Resist or Redirect advances it one stage. If the sequence completes, the encounter resolves as a **forced yield**: corruption + `yield_corruption_value`, no boon. Refusing to choose is choosing.

- **Resist** — roll d100 vs `resist_difficulty` × 100; success ends the encounter (exit, one tick immunity); failure: corruption +2, sequence advances.
- **Yield** — corruption + `yield_corruption_value` (default 10); encounter ends peacefully; boon granted. The transaction is explicit on-screen.
- **Redirect** — if `redirect_options` is non-empty, roll d100 vs `redirect_difficulty` × 100; success ends the encounter with no corruption and no boon; failure wastes the turn, sequence advances.
- **Flee** — identical to combat Flee, shared code.

## 5. The Athlete's Corruption Triggers

- **Combat:** When the player chooses **Fight against a talk-receptive enemy**, corruption increases by **3**, which advances the corruption track toward its band thresholds (each band crossed: ATK +2, max HP −5, and the band's verb mutation applies).
- **Intimate:** When the player chooses **Yield**, corruption increases by **`yield_corruption_value` (default 10)**, which advances the same track. The intimate trigger pays more per firing than the combat trigger (10 vs 3); Resist-failure's +2 is a lesser third feed into the same track.

## 6. Run Shape

- **Start:** athlete spawns on the entrance tile of the hand-made floor. HP 20 / 20, corruption 0 / 100, ATK 5, DEF 2, empty inventory.
- **Win:** step onto the exit tile.
- **Loss 1:** HP ≤ 0 (death end screen).
- **Loss 2:** corruption ≥ 100 (the armor takes her — distinct Bad End screen). Bands: 0–24 / 25–49 / 50–74 / 75–99 / 100 = end.

## 7. Encounter Trigger Types (enum)

- `proximity` — enemy adjacent to player at end of tick (standard hostile).
- `player_initiated` — player steps into the enemy's cell deliberately (beckoner).
- `enemy_initiated` — enemy steps into the player's cell (ambush).
- Each enemy resource declares exactly one. Trigger type sets opening framing: `player_initiated` → player menu first; the other two → enemy acts first.

---

## Decision Log

| Decision | Choice | Reason |
|---|---|---|
| Movement | 4-way | Diagonal adjacency creates ambiguity in `proximity` triggers; expensive to reverse once the scheduler and dispatcher exist |
| Interact verb | Cut | Every PoC interaction already has a trigger; cheap to re-add post-PoC if needed |
| Intimate failure endpoint | Forced yield on sequence completion | Stalling is itself a choice; the alternative (HP damage) collapses intimate encounters into reskinned combat. Known edge: a player can be corrupted without ever pressing Yield — Phase 9's "real choices or traps?" question tests this rule specifically |
| Redirect mechanism | d100 roll, no cost / no reward on success | Parallels Flee/Resist; the clean exit is harder than Yield's guaranteed boon but pays no corruption — the asymmetry that keeps the choice unsolved |
| All tuning numbers | HP 20, ATK 5, DEF 2, corruption max 100, Fight-vs-receptive +3, Yield 10, Resist-fail +2, heal +8 | First-guess values; Phase 9 replaces them via resource files, no code changes |
