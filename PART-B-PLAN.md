# Part B: plan for after the freeze (from 7 Nov 2026)

Status: **proposal only, nothing built.** Revise it with your notes from three weeks of use. Effort is
in working sessions of about 2–3 hours, including tests, snapshots and a phone check. The order at the
end is a suggestion.

## 1. Information architecture: one model for phone and Mac (4–5 sessions)

**Today.**
- **Phone tabs:** Dashboard, Food log, ＋, Strategy, Training, plus More behind the profile button.
- **Mac sidebar (8 pages):** Dashboard, Food log, Weight, Insights, Strategy, Workouts, Exercises,
  Settings.
- **The problem:** the two disagree (Weight and Insights are pages on the Mac but buried on the phone),
  and nothing is organised around how often you do things.

**Proposal: group by how often you do it.**

| How often | What you do | Where it lives (phone tab / Mac sidebar) |
|---|---|---|
| Daily | Eat to plan, train, weigh in | **Today** (home), **Food log** (with the plan), **Training** |
| Weekly | Check-in, review progress, change strategy | **Progress** (check-in, weight, insights, strategy) |
| Rarely | Settings, data, integrations, diagnostics | **More** (phone) / **Settings** (Mac, at the bottom) |

**Today becomes the home**, replacing the Dashboard. Top to bottom:
1. Calories and macros left (the rings).
2. The next planned meal, with a one-tap **Eaten** and a swap.
3. Today's workout (start, or done ✓).
4. The weigh-in prompt until you've weighed in.
5. One line for the check-in when it's due.

Everything else moves to Progress or Insights.

**Tabs:** Today · Food log · ＋ · Progress · Training. The Mac sidebar uses the same five, plus
Exercises and Settings at the bottom. Strategy becomes a section of Progress; on the Mac it also stays
reachable from the sidebar under Progress.

**Effort:** new Today screen (2), Progress merging Weight/Insights/Strategy (1.5), navigation and
deep links/Shortcuts on both platforms (1), snapshots and checklist (0.5).

**Decision for you:** whether Strategy should be its own tab instead of part of Progress. Your notes
on how often you open it will tell.

## 2. Plan as a first-class part of the food log (2 sessions)

**Today:** Food log → ⋯ → View → Plan, a separate mode.

**Proposal:** one food log in which planned meals sit in the timeline as faint cards at their times.
Already started in Part A: the next planned meal shows in the timeline.
- Tap a planned card to eat, swap, keep or change a portion. Logging it turns it solid.
- **Planned meals:** a toggle in the header (on by default once a plan exists). The ⋯ View menu only
  chooses Timeline or Meals.
- **"Week & groceries"** moves to the header's calendar menu.
- **Adherence** ("as planned / swapped / skipped") becomes a small line under the day's macro bars.

**Effort:** timeline merge (1), edits and undo in the log (0.5), tests and snapshots (0.5).

## 3. Dashboard: from 19 cards to at most 5 (1 session, plus Today in item 1)

**Today's default layout:**
- **Nutrition (4):** macros, calories, fibre, sodium.
- **Insights (11):** expenditure, weight trend, scale weight, nutrition trend, energy balance,
  goal, protein per meal, strength, training, week, activity.
- **Habits (4):** supplements, habit score, weigh-ins, food logging.

**Proposed default on Today (5):**
1. Calories & macros (the rings).
2. Next planned meal.
3. Today's workout.
4. Weight trend (with the weigh-in prompt).
5. Expenditure.

**Move to Insights:** scale weight, nutrition trend, energy balance, goal progress, protein per meal,
strength, week grid, activity, habit score, food-logging and weigh-in streaks, fibre, sodium and the
other nutrients.

**Supplements** become a row on Today, only if you track any.

Customize stays, so anything can be added back.

## 4. Settings: halve what a normal user sees (2 sessions)

**Inventory first** (part of the work): every toggle, picker and row in More, Strategy and Planner
settings. The code has 36 toggles and 83 pickers in total (not all of them settings). More has 19
rows and Strategy has 21.

**Proposed starting points:**
- **Move to Developer:**
  - expenditure modifiers (step-informed, predictive goal) and the BMR equation;
  - calculation start date and static expenditure;
  - shadow mode;
  - the photo-AI model names;
  - the Coach's "which AI".
- **Remove:** settings with one sensible value nobody changes; to be confirmed from your notes.
- **Change defaults:** the planner on by default once staples exist; the weekly budget and
  calorie distribution off until you turn them on.
- **Regroup More into 4 groups:** You · Nutrition & coaching · App · Data.

**Goal:** a normal user sees half of today's rows.

**Effort:** inventory and proposal (0.5), moves and removals with migrations where a setting
disappears (1), snapshots (0.5).

## 5. Coaching engine: switch criteria and a date (0.5 session to set up, then a decision)

**Today:** the new engine runs in preview at each check-in, next to the current rules. A1 already
moved the trend and the expenditure to the engine; what's left is the **target decision rules**.

**Proposed criteria for switching** (all must hold):
1. **Backtest:** on the weekly replay of the last 12 months, the engine's targets give a 4-week weight
   prediction error no worse than the current rules', and change targets no more often (today: 36
   changes in 53 weeks).
2. **Your shadow weeks (3 check-ins, 23 Oct – 6 Nov):**
   - no engine proposal you'd have rejected as unsafe (under the floor, protein cut, a jump over
     150 kcal);
   - at least 2 of 3 weeks within ±100 kcal of what you actually chose, or better by your judgment.
3. **No open grade-D rules** behind any change of more than 100 kcal. Each one is verified, or the
   change is capped.

**Date to decide:** **Monday 9 Nov 2026**, after the 6 Nov check-in. If the criteria hold, switch and
remove the preview. If not, record why in the registry, keep the current rules and delete the preview
code, so there's never a second engine on screen. Re-try no earlier than 3 months later.

**Effort:** a replay report comparing the two (0.5); the switch or the removal (0.5).

## 6. Mac: decide what it's for (3 sessions)

**Proposal:** the Mac is for **analysis, planning the week, and data**, not for daily logging. The
phone does that.
- **Analysis:** Insights as a dashboard of big charts side by side (trend, expenditure, intake vs
  target, strength), all on one range control; the check-in history as a table you can sort.
- **Planning the week:** a 7-day plan grid (meals × days) with drag-and-drop swaps, the grocery list
  beside it, and the weekly carb distribution.
- **Data:** the food library and recipes as editable tables; import/export; backups; sync status;
  the taxonomy review; diagnostics.
- **Logging stays possible** (⌘K quick add), but the Mac doesn't copy the phone's timeline.

**Layout:** a three-column split (sidebar · list or table · inspector) for the data pages; full-width
canvases for analysis and the week plan.

**Effort:** week-plan grid (1.5), analysis dashboard (1), data tables (0.5).

## 7. Visual renewal (dark), with the new Today (2–3 sessions on top of item 1)

**Asked on 27 Oct:** renew Gym's look with the new design skills, keeping a **dark aesthetic**. It's
built with Part B, so screens are only rebuilt once.

**Directions to choose from:** `.impeccable/mocks/decision/index.html` (all dark, each showing the
new Today home):
1. **Discos (my recommendation):** competition plates on a rubber floor. The plate colours carry
   the data (protein red, carbs blue, fat yellow, training green), and today's macros are three
   plates filling as you eat.
2. **Cronos:** a Formula 1 timing tower. Purple means a personal best, green better than last time,
   yellow a warning, on lifts, trend and streaks.
3. **Jueces:** the three referee lights at a meet (Eat, Protein, Train/rest), lighting up as the
   day goes. The most minimal.
4. **Dark Titanium, refined:** today's look, cleaned up.

**Decision:** pick one before 7 Nov, or with your notes. The pick becomes Gym's DESIGN.md world:
tokens in Design.swift and Tokens.swift, the existing lint keeps them honest, and the theme grid
changes to match.

**Effort:** tokens and themes (0.5), Today and the four tabs in the new world (1.5), snapshots,
accessibility and the checklist (0.5).

## Suggested order

1. Engine decision (item 5) on 9 Nov, since it affects what Today shows.
2. Information architecture with the new Today (item 1).
3. Plan in the food log (item 2).
4. Dashboard (item 3), which mostly follows from items 1 and 2.
5. Settings (item 4).
6. Mac (item 6).

The visual renewal (item 7) goes with item 1.

That's 15–17 sessions in all.
