# Gym: working notes for Claude

SwiftUI + SwiftData, one multiplatform target (iPhone first, Mac second). Free signing: the phone
install expires 7 days after each install. Never suggest the $99 account or iCloud. Keep this file
current: add each decision when it's made.

## Workflow

- **While iterating:** build the Mac app only, and run the test suites the change touches.
  ```
  xcodebuild -project Gym.xcodeproj -scheme Gym -destination 'platform=macOS' -derivedDataPath build build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | sort -u
  Tests/<suite>/run.sh          # migration, backup, export: run.sh <copy of the store> (see tools/check.sh)
  ```
- **At review points only:** run the full gate, `tools/check.sh` (both builds and every suite; capture
  the exit code), then install with `tools/install-mac.sh` and `tools/install-phone.sh` (or
  `tools/plan-bench.sh`, which installs and times the planner on the phone).
- **Stop for the user only on:** sample plans (`tools/sample-plan.sh`), evidence registry changes,
  data migrations, and anything that changes targets. Otherwise carry on.
- Small commits, all tests passing, each ending with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Push to origin/main when asked.
- Data-model changes ship with a migration test (Tests/migration) and a sync round-trip (Sync.swift
  encode and decode).
- Use real data only via a copy of the Mac store, never the live one:
  `~/Library/Containers/com.wavymaso.gym/Data/Library/Application Support/default.store*`.
- The backtest is `tools/backtest.sh` (`full`, `cohere`); the engine report is `tools/engine.sh`
  (BACKTEST.md).
- The app follows MacroFactor's fundamentals with our own styling (see DESIGN.md). Ask before
  departing from MacroFactor's flow.

## Feature freeze: 17 Oct to 7 Nov 2026

Bug fixes and polish only. New features go in BACKLOG.md with a spec. Part B
(information architecture, Plan in the food log, dashboard, settings, engine switch, Mac) is planned in
PART-B-PLAN.md and is not built before 7 Nov.

## Targets and floors

- **Never change the coaching engine's targets** without the user's explicit approval. That covers
  the engine's rules, and any change of trend or expenditure feeding the targets.
- **Calorie floor:** your own floor (`Profile.calorieFloorKcal`) if you set one; otherwise BMR, at least
  1200 kcal. BMR uses Katch–McArdle when lean mass is known (a body-fat reading or tape measurements in
  the last 90 days), otherwise Mifflin–St Jeor. `makeTargets` clamps to it.
- **The floor holds on every day**, not just the daily target. The refeed, training-day extras and the
  weekly budget never push a day under it: `floorWeek` raises low days and takes the difference
  from days above the floor. Fasting days are exempt.
- **Fat floor** (coached): max(40 g, 0.5 g/kg).
- **Protein:** first, but at most 40% of calories.
- **Planner fibre floor:** 14 g per 1000 kcal (`fibre.per1000kcal`).
- **Planner carbs:** pre-workout carbs = min(0.75 g/kg, 30% of the day); rest-day carbs at least
  1.0 g/kg.
- **Check-in:** within ±50 kcal, no change. Otherwise it moves 35–70% of the gap, depending on how sure
  the estimate is, at most 150 kcal (75 down on a bulk).
- **Check-in questions** (hunger, energy, sleep, training, stress, plan difficulty) only make
  proposals that you accept or decline. Nothing changes automatically.

## A1 (18 Oct 2026): one trend everywhere

- **The engine trend** (EngineTrend, a Kalman filter on trend, rate and water) is on every screen and
  inside the targets (the rate and protein per kg).
- **The engine's expenditure** (EngineEnergy, built on that trend) is behind the targets. Both are the
  defaults (`""`).
- **The trend choice is one synced setting** (`Profile.trendAlgorithm`), not per device.
- **The algorithm pickers live in More → Diagnostics → Developer**, for comparison only.
- **The ~1 kg gap to MacroFactor's/classic trend is the EMA lag**, not a bias. The classic trend (α 0.1)
  trails a moving weight by about 9 days; after removing that lag the residual is about 0 every month
  from Jul 2025 to Oct 2026 (`GAP=1` in `tools/backtest.sh cohere`).
- **Known engine-trend issue (not fixed, needs approval):** in long gaps without weigh-ins the rate
  carries on unchecked. Feb–Jun 2025 had no weigh-ins, and the trend there drifts up to 24 kg below the
  real weight. Today's values aren't affected.
- **The engine preview** at check-in sits next to the current rules and never changes targets. When
  to switch is a Part B decision.

## Planner

- **Three stages:** 1 templates (each meal's structure); 2 pick foods for the slots (staples, foods
  you eat together, simple whole foods); 3 the solver sizes portions, then repairs. The pure solver is
  in Gym/Engine/Planner, the app adapter in PlannerApp.swift.
- **Templates** are in MealTemplates.swift, seeded from your log (14–16 Oct) and approved with edits:
  - breakfast (rice cakes/bread/oats, spread, a protein, fruit);
  - lunch and dinner (carb base, protein, vegetable, optional bread/pulses/sauce; dinner has a
    lighter carb portion on rest days);
  - merienda (dairy protein, fruit or bread, spread);
  - pre-workout (carb-forward, ≤12 g fat, ≤6 g fibre);
  - post-workout (protein plus a main carb);
  - evening snack (one treat a day, only when treats are on).

  Pre- and post-workout replace the meal in their time window; they never add meals. Repairs only use
  slots and foods the meal's template allows.
- **Food roles** (Taxonomy.swift): protein main, carb side, vegetable, fruit, fat source, dairy, protein
  snack, condiment (only alongside food), treat (once a day, never a meal on its own), drink (not
  planned).
- **Tiers:**
  - **1** whole foods: meat, fish, eggs, rice, potatoes, pasta, oats, bread, fruit, vegetables,
    legumes, plain dairy.
  - **2** simple staples: peanut butter, jam, oil, tinned fish, plain sauces, rice cakes, whey.
  - **3** convenience products: bars, ready meals, snacks. Planned only when in stock, and never a
    meal's only protein.

  Ranking: tier 1 +0.8, tier 3 −0.8.
- **No pork:** no template allows pork, ham, sausages or chorizo, so the planner never plans them
  (the planner tests check this).
- **Never the same canonical food twice in a meal.** At main meals, not the same protein family at
  lunch and dinner.
- **Constraint priorities** (`MealBuilder.severity`, lexicographic):
  1. Hard group: protein beyond the 2 g tolerance, the protein-per-meal minimum, calories outside
     the band, the fat floor beyond 2 g, realism (portion caps), pre-workout carbs.
  2. Fibre last: it never displaces calories, protein or protein per meal.
- **Shortfalls are reported** only beyond 2 g (`Planner.proteinFatTolerance`).
- **When a day is short of fibre,** vegetables and fruit are chosen by fibre per 100 g. Prefer wholemeal
  bread and skin-on potatoes.
- **Edits:** swap (5 options from the same template slot, in your style), keep a single food at a
  portion (never resized), product units (2 eggs, 1 bar, 1 slice), undo. Edits are saved per day
  (`DayEdits`).
- **Parked in BACKLOG.md:** regenerate, style chips, the preference model.
- **Speed (phone):** under 200 ms to re-solve after a swap or log, under 1 s for a full day. Warm
  re-solve of only the changed meal; the week is planned in the background and cached.

## Evidence registry (EvidenceRegistry.swift → EVIDENCE.md)

- **Every coaching rule** and every planner or check-in threshold has an entry with an honest grade.
- **Verify each source by web search before adding it.** Never invent a citation, DOI or number.
- **Unverified entries** are grade D with `verified: false`. Conventions are grade D with the
  `convention` source.
- **Registry changes are a stop point:** show them to the user before committing.

## Design (DESIGN.md, Design.swift, Tokens.swift)

- **Type roles, spacing and radii come from Design.swift** (`Font.screenTitle…`, `Space`, `Radius`).
  If a genuine need has no role, add one to Design.swift and DESIGN.md instead of using a raw font or
  number.
- **Themes:** appearance (light, dark, black) × finish (titanium, silver, graphite, gold, rose gold).
