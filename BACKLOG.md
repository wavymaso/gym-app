# Backlog

Parked on 17 Oct 2026 (step 4 was narrowed to: Mac swap sheet fix, swap, single-food keep, servings in
product units). Feature freeze until **7 Nov 2026**: bug fixes only until then.

## Regenerate (food, meal, day)

- **Regenerate a food**: the next option for that template slot, from the same ranking the planner uses
  (`MealBuilder.rank`). Each tap takes the next *distinct* option and cycles back to the first.
- **Regenerate a meal**: every unkept slot in that meal takes its next option. Kept foods stay.
- **Regenerate the day**: the same for every open meal. Eaten, locked and kept foods stay.
- **Undo** steps back through the changes. Undo exists today for swaps and keeps: it re-plans from
  scratch with the earlier edits, which reproduces the earlier plan exactly.
- **Engine notes**: store turns in `DayEdits` as `slotTurns["slot|kind"]`, `mealTurns["slot"]` and
  `dayTurns`. In `select`, pick `ranked[(offset + mealTurns + slotTurns) % ranked.count]`. A regenerated
  meal is "dirty" in the warm path, so it is re-selected while the other meals are only resized. A day
  regenerate is a cold plan.
- **Tests**: 4 turns give 4 different proteins; a meal regenerate changes only that meal; undo restores
  the plan.

## Style chips

- A segmented control on the Plan view: **My usual / Basic / Anything**, bound to `PlannerSettings.style`.
  The setting and the engine behaviour already exist; only the chips are parked.
- Changing style re-plans from scratch.
- Swap alternatives already follow the style.

## Preference model

- **Likes and dislikes** per food (key or canonical id). A like ranks the food higher in `rank` (+2);
  a dislike ranks it lower (−4). A dislike never excludes the food.
- **Learning from rejections**: count each time you swap a food away. At 2, ask
  "Stop suggesting [food]?" with three answers:
  - **Never**: add it to `exclusions`.
  - **Not at [meal]**: add it to `slotExclusions[meal]`; `rank`/`allowed` leave it out only at that meal.
  - **Keep suggesting it**: don't ask about it again.
- **Never auto-exclude.**
- **Settings fields** (each added to the tolerant decoder, with a round-trip test): `likes`,
  `dislikes`, `rejections: [key: Int]`, `keepSuggesting`, `slotExclusions: [meal: [key]]`.
- **Tests**: a like ranks higher; a dislike ranks lower but is still offered; "not at lunch" leaves the
  food out at lunch and keeps it at dinner; the decoder round-trips.

## Other ideas noted along the way

- Your staple "Brotes de espinaca" has no fibre on its label, so the planner counts it as 0 g. Spinach
  is ~2.2 g/100 g. A "fill in missing fibre from the canonical food" prompt is an option (never silent).
