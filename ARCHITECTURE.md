# Gym: architecture

One SwiftUI app (iPhone primary, Mac secondary) plus a widget extension. ~22k lines in `Gym/`,
tests as standalone harnesses in `Tests/`. Everything is checked by `tools/check.sh`.

## Data model (SwiftData)
All models are in `allModels` (`Models.swift`). Main ones:

| Model | File | What |
|---|---|---|
| `Profile` | Models.swift | You: units, body, settings that sync (refeed, scales, phases, week plan…) |
| `Program`, `TargetSet` | Models.swift | A goal (lose/maintain/gain, rate, mode) and each targets change with its reason |
| `WeightEntry` | Models.swift | Weigh-ins, tagged by scale (`trendKg` applies the scale offset) |
| `Food`, `RecipeIngredient` | Food.swift | Foods (`key`: off:/usda:/custom:/recipe:/ai:), recipes as ingredient rows |
| `FoodEntry` | Food.swift | One logged food: `day` key (fixed when logged), `time`, nutrients |
| `Workout`, `WorkoutSet`, `Exercise`, `Routine` | GymModels.swift | Training |
| `Measurement`, `ProgressPhoto` | Body.swift | Tape and photos |
| `SavedMeal`, `DayNote`, `Supplement…`, `WaterEntry`, `DailyActivity` | various | |
| `Tombstone` | Sync.swift | A deletion, so the other device deletes too |

Rules:
- Every save goes through `ModelContext.commit()` (Sync.swift): it stamps `modifiedAt`, records
  tombstones and bumps `dataVersion`, which invalidates the caches (intake, weights, targets, trend).
  `commitSoon()` debounces typing.
- A "day" is a `yyyy-MM-dd` key in the zone you're in (`dayKey(_:)`, Calc.swift). `dayKey()` is
  today, shifted by the optional day-start hour. Entries keep the key they were logged with, so
  travel never moves them. Day arithmetic (`addDays`, `daysBetween`) is pure calendar maths.
- Units are stored metric (kg, cm, kcal) and converted for display only.

## Data safety
- **Before a model change** (`StoreSafety.swift`): the store files are copied to
  `Backups/Before update …` (last 5), detected by a fingerprint of the schema.
- **If the store won't open**: no crash; `RecoveryView` puts it aside and restores the newest backup.
- **Backups** (`Backup.swift`): JSON of every record (the sync format), daily when the app goes to the
  background; 14 daily + weekly for 13 weeks in the app, 30 daily + weekly in a chosen folder (iCloud Drive).
  Restore in Settings → Backups. `Tests/backup` proves a lossless round trip on your real data.
- **Integrity check** (`Integrity.swift`) at every launch: duplicate sync IDs (newest kept, no
  tombstone sent), orphan recipe ingredients removed, loose sets and impossible numbers reported.
- **Undo** (`Undo.swift`): deletes, copies and moves restore exactly from the sync encoding.

## Sync (Mac ⇄ iPhone)
- The Mac runs `SyncServer` (NWListener on 127.0.0.1:8010, published over Tailscale HTTPS);
  the phone's `SyncClient` sends its changes since the last sync and receives the Mac's.
- Each record: `syncID` (stable), `modifiedAt`; per record, the newest edit wins; a tombstone
  wins over older edits only (`applySync`). Upserts by `syncID` make retries idempotent.
- Food entries and sets are separate records, so edits on both devices merge naturally.
- The phone also sends meal photos to the Mac's local AI through the same server (`/gym/photo`).

## Algorithms (where they live)
| What | File | Notes |
|---|---|---|
| Weight trend | Trend.swift (`trendSeriesV1`, `trendSeries`) | V1 default: matches MacroFactor's trend |
| Expenditure | Trend.swift (`classicExpenditure`, `jointExpenditure`, V1 variants) | "classic" default: fitted to MacroFactor |
| Targets, protein, guardrails | Calc.swift (`makeTargets`, `proteinGrams`) | |
| Weekly check-in | Progress.swift (`CheckInSummary`, `smoothed`, `finishCheckIn`, `dayTargets`) | deadband, cap, confidence |
| Phases, scales, shadow mode, week plan | Phases.swift | |
| Progression, volume, e1RM | GymCalc.swift, WeeklyReview.swift | |
| Photo AI | PhotoAI.swift | Ollama (qwen3-vl) on the Mac, Gemini fallback chain; dishes → ingredients; inferred oil |
| Food search | LocalFoods.swift | FTS5 on foods.sqlite, accent and Arabic folding, typo correction |
| Coaching note | Coach.swift | facts → AI prompt → 3–4 bullets, once a day |

**Rule:** algorithm changes must keep outputs identical unless approved; prove it with
`Tests/backtest` before and after.

## Backtesting
```
D=~/Library/Containers/com.wavymaso.gym/Data/Library/Application\ Support
M=$(mktemp -d); cp -p "$D"/default.store* "$M/"
MFCMP=1 Tests/backtest/run.sh "$M/default.store" "$PWD/.backups/backtest/mf-expenditure.csv"
```
Prints each expenditure algorithm's average error against MacroFactor's own numbers. Never point
tests at the live store: always a copy.

## UI
- Design system in `Design.swift` (springs, haptics, spacing, radii, type roles, undo toast,
  empty/problem/working states, options pages); documented in `DESIGN.md`.
- Colours per theme in `Theme.swift` (`Palette`); 23 themes.
- Phone: `GymApp.swift` keeps each tab alive in a ZStack with a spring cross-fade; the custom tab
  bar is in `Navigation.swift`. Mac: `NavigationSplitView`.

## Observability
- `Log.swift`: os.Logger categories (sync, database, ai, coaching, import, network); `Log.problem`
  keeps the last 60 problems for More → Diagnostics (`Diagnostics.swift`), which also shows MetricKit
  crash/hang summaries, integrity results and an exportable text bundle.

## Tests
`./tools/check.sh` builds both apps and runs every suite (gate for each commit). Suites that need
real data run on a temporary copy of the Mac app's store. Notable: `strategy` (coaching rules),
`backtest` (real data vs MacroFactor), `time` (DST, travel, day start), `integrity`, `undo`,
`backup` (lossless round trip), `migration` (opens the real store with the current model).

## Install
`tools/install-mac.sh` (backs up, replaces /Applications/Gym.app) and `tools/install-phone.sh`
(free signing, 7 days; the app warns two days before).
