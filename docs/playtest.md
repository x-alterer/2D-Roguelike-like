# Phase 9 — Self-Playtest Protocol & Findings

The build half of Phase 9 is done: full roster, two items, generation,
the corruption arc, the run loop. This file is the other half — the
instrument. Run the protocol, then fill in the findings form at the
bottom. Per the implementation plan, the last section's answer decides
whether the next milestone is character #2 or a loop redesign.

---

## Protocol

**Setup.** Sound on. Fresh seeds (blank seed box). Play at least five
runs to completion — win, death, or corruption end — and vary your play
deliberately:

1. One run played "virtuously": Talk when receptive, Redirect or Resist
   every intimate encounter, Fight only growlers.
2. One run played "greedily": Yield to every beckoner, Fight everything,
   take every boon.
3. One run played to win as fast as possible, ignoring everything
   optional.
4. At least one run where you deliberately reach corruption band 2+
   (Yield plus the veil's trap will get you there without the debug key)
   and then USE the mutated verbs.
5. One run on a replayed seed: note whether knowing the floor changes
   your choices.

**While playing, note every moment where** you paused because you didn't
know what would happen, were surprised by an outcome, or felt a choice
was fake. Timestamps don't matter; the moments do.

**If an external playtester is available:** watch silently. Note where
they stall, what they never try (did they ever press Redirect?), and
what they say out loud at the end screen.

## The failure-state questions (answer each with an example, not yes/no)

1. **Do decisions ever feel arbitrary?** (If so, the outcome stage is
   broken — which resolution surprised you and why?)
2. **Is it ever unclear what you can do?** (Choice-presentation stage —
   where did you hesitate on the menu?)
3. **Did you ever die without knowing why?** (Feedback stage — what was
   on screen in the three turns before death?)
4. **Does the corruption trade ever feel like the wrong price?** (Which
   number felt too cheap or too cruel? Candidates to tune, all in data
   files: Fight-vs-receptive +3, Yield 10, Resist-fail +2, heal +8,
   cleanse −5, band thresholds, ATK+2/maxHP−5 per band.)
5. **Do the intimate encounters feel like real choices or traps?** (If
   Yield is always the mechanically best button, the flavor is solved
   and dead. Did Resist or Redirect ever feel like the RIGHT play, not
   just the virtuous one? Did the Grasping Veil teach you to fear
   ambushes or just to reload?)
6. **Does the behavioral profile at run-end surprise you?** (If it only
   confirms what you already knew, the mirror isn't adding anything.
   What did "Fight: 9" make you feel?)

---

## Findings (fill in after the protocol — one page, honest)

**Runs played:** _n_, causes: _…_

**Per-question notes:**

1. …
2. …
3. …
4. …
5. …
6. …

**Tuning changes to make (data files only):** …

**The secondary question:** does the behavioral mirror make you want to
play differently next time? …

**The only question that matters:** does the 60-second loop from the
design lockdown exist in this build — press a key, world ticks, threat
closes, screen shatters, four verbs, a price paid in the open — and is
it worth 60 more seconds?

**Verdict (next milestone):** character #2 / loop redesign, because …
