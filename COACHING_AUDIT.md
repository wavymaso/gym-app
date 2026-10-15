# Coaching audit (Phase 0, 15 Oct 2026). Nothing was changed.

Scope: trend weight, expenditure, targets and macros, check-ins, refeeds, diet breaks, distribution and
weekly budget, phases, scales, training signals and the AI coach. "Source" means a citation in the code;
today **no constant in the coaching code has a citation**. Several are fitted to MacroFactor's output
on your own data, which is a calibration, not evidence.

## 1. Every formula and constant

### Trend weight (`Gym/Trend.swift`)
| What | Value | Where | Source |
|---|---|---|---|
| V1 (default): days without a weigh-in are filled on a straight line between weigh-ins, then an exponential moving average | α = 0.1 (~10-day memory) | `trendSmoothing`, `trendSeriesV1` | None. Matches MacroFactor's published trend to 0,01 kg on your history (`Tests/backtest`) |
| V2 (option): local linear fit (LOESS-like), tricube weights | ±10 days; filled days weigh 0.25; 3 bisquare passes, 6×MAD | `robustTrend` | None (standard robust-regression choices) |
| One weigh-in per day | the last one of the day wins | `trendSeriesV1` (`uniquingKeysWith`) | None. Multiple weigh-ins are not averaged |
| No uncertainty band and no explicit rate state | | | |

### Expenditure (`Trend.swift`, `Progress.swift`)
| What | Value | Where | Source |
|---|---|---|---|
| **Classic (default)**: 21-day mean intake − density × Δtrend / 20, blended 5 %/day | window 21, density **5 500 kcal/kg**, α 0.05, needs ≥50 % of days logged | `classicExpenditure` | Fitted to MacroFactor (backtest error 62 kcal since Jul 2026). One density for gain and loss |
| Energy density used elsewhere | **7 700 kcal/kg** | `kcalPerKg` (Calc.swift): targets, V1, joint | Convention (the "3 500 kcal/lb" rule). Not direction- or body-fat-dependent |
| V1 Kalman (option) | window 21, min 4 logged days per week, start sd 350, drift 25/day, overlap ×6, max 75 kcal/day | `ExpenditureSettings` | None |
| Joint state-space (option): mass, expenditure, water | start sd 350, drift 26, mass noise 0.01, unlogged 0.2, water AR(1) 0.7 with sd 0.4, scale noise 0.15, outlier z 2.5, water-event sd 0.8 | `JointSettings`, `jointExpenditure` | Tuned on a simulator (`Tests/expsim`) and your history. `gainDensity = lossDensity = 7700` |
| Formula prior | Mifflin–St Jeor (default), Katch–McArdle if body fat is set, Harris–Benedict (revised) | `bmr` | Equations are standard; no citation in code |
| Activity factors | 1.2 / 1.375 / 1.55 / 1.725 / 1.9 | `Activity.factor` | Convention (no citation) |
| Step modifier (optional) | 0.0005 × kg kcal per step, half applied immediately | `expenditureNudges` | None (≈0.04 kcal/step at 80 kg) |
| Predictive goal modifier (optional) | 20 % of a target change, over 14 days | `expenditureNudges` | None |
| Fixed manual expenditure | overrides everything | `expenditureEstimates` | n/a |

### Targets and macros (`Calc.swift`)
| What | Value | Where | Source |
|---|---|---|---|
| Daily delta | goal % × weight × 7 700 / 7 | `makeTargets` | Convention |
| Rate menu | lose 0.25/0.5/0.75/1.0 %, gain 0.1/0.25/0.5 %; defaults 0.5 and 0.25 | `GoalType.rates` | None |
| Calorie floor | **1 500 men / 1 200 women**, or your own; 800 without guardrails | `calorieFloor`, `makeTargets` | Convention. Not relative to fat-free mass or expenditure |
| Protein (no lean mass) | 1.6 / 2.0 / 2.4 / 2.8 g/kg × training factor (0.75 none, 0.85 cardio, 1.0 lifting); weight capped at BMI 27 for height | `ProteinLevel`, `proteinGrams` | None (1.6 matches Morton 2018, not cited) |
| Protein (lean mass known) | 2.0 / 2.4 / 2.8 / 3.2 g/kg FFM, clamped to 1.5–2.6 g/kg body weight | `proteinGrams` | None (range overlaps Helms 2014, not cited) |
| Protein cap | ≤ 40 % of calories | `makeTargets` | None |
| Fat | balanced 30 %, low-fat 20 %; low-carb 20 % carbs; keto 30 g carbs | `DietStyle`, `makeTargets` | None |
| Fat minimum (coached) | max(40 g, 0.5 g/kg) | `makeTargets`, `checkInSummary`, `replayCheckIns` | None, **duplicated in three places** |
| Carbs | remainder; no training minimum | `makeTargets` | |
| Per-meal protein | not modelled | | |

### Check-in (`Progress.swift: smoothed, checkInSummary, finishCheckIn`)
| What | Value | Source |
|---|---|---|
| Deadband | ±50 kcal of the raw target: no change | None |
| Step | 35 % + 35 % × confidence of the gap | None |
| Caps | +150 up; −150 down (−75 on a bulk) | None |
| Protein hysteresis | keep current protein unless it moved ≥10 g | None |
| Big-change confirmation | expenditure moved >250 kcal since last targets → asks first | None |
| Low-adherence rule | none: few logged days only lower confidence indirectly; the check-in still proposes | — |
| Stored record | `TargetSet` (targets, expenditure, reason, date). **Inputs, intermediates and rules fired are not stored**; `replayCheckIns` recomputes with today's code | — |
| Collaborative | engine's calories, your protein and carb/fat split; week plan rescaled | — |

### Distribution, refeeds, diet breaks, weekly budget (`Models.swift`, `Progress.swift`)
| What | Value | Source |
|---|---|---|
| Training-day extra | your kcal, week total kept, difference in carbs | n/a (your setting) |
| Fasting days | 600 kcal default, macros scaled | Convention |
| Refeed | your extra kcal, all carbs, taken back evenly over 6 days | None |
| Diet break | maintenance = max(expenditure, target), same protein | None |
| Weekly budget | under/over earlier in the week spread over the days left, ±20 %/day, 60/40 carbs/fat | None |

### Phases and scales (`Phases.swift`)
| What | Value | Source |
|---|---|---|
| Phase queue | goal, rate, weeks or target weight; next phase offered when done; 4 weeks maintenance suggested after | None |
| Recomp | **not a phase type** (maintain only) | — |
| Scale offsets | median gap between a scale's readings and the main scale's two-sided trend; ≥3 readings | None (sound) |

### Training signals (`GymCalc.swift`, `WeeklyReview.swift`, `Bodybuilding.swift`)
| What | Value | Source |
|---|---|---|
| e1RM | Epley, reps capped at 12; weekly review uses reps ≤10 and adds RIR | None (Epley is standard) |
| Progression | double progression, +2.5 kg (equipment step), ~10 % reset when well short | Convention |
| Volume ranges per muscle | your settings | — |
| Strength retention on a cut | displayed only; **not used by coaching** | — |

### AI coach (`Gym/Coach.swift`)
- Builds a plain-text fact list and asks the model for 3–4 bullets. **No structured snapshot, no
  number validator, no evidence references.** It can and does state derived numbers. Example seen
  on your data: "lock in 2 113 kcal", a number the engine never produced. That is exactly the
  failure the new grounding contract prevents.
- Falls back to fixed rules if no AI answers.

## 2. Hard-coded numbers that should be configurable or registry entries
7 700 kcal/kg; 5 500 kcal/kg; the 21-day window and α 0.05; 1 500/1 200 floors; 800 no-guardrail floor;
protein levels (1.6–2.8 g/kg, 2.0–3.2 g/kg FFM) and clamps (1.5–2.6 g/kg); 40 % protein cap; fat 30/20 %;
fat floor 40 g / 0.5 g/kg (×3 copies); deadband 50; caps 150/75; step 35–70 %; protein hysteresis 10 g;
250 kcal confirmation; activity factors; step energy 0.0005 kcal/kg/step; 20 % predictive goal; refeed
give-back over 6 days; weekly budget ±20 % and 60/40; fasting 600 kcal; water-event sd 0.8 and the
joint filter's noises; Epley rep cap 12; progression +2.5 kg / −10 %.

## 3. Known failure modes
| Case | What happens today | Severity |
|---|---|---|
| **Refeed / diet-break water** | Classic (default) and V1 trend read the jump as tissue: trend rises, expenditure dips for ~3 weeks. Only the optional joint model knows water events | High |
| **Creatine, salty days, travel, illness** | Day notes can be tagged "water event", but only the joint model uses the tags | Medium |
| **Half-logged days** | Days marked partial are excluded from intake (good). Unmarked half-logged days count as real intake → expenditure biased low | Medium |
| **Missing weigh-ins** | V1 fills gaps on a straight line, which can lag; long gaps (e.g. your 138 days in 2025) make the trend jump to the new level, and classic/MacroFactor diverge there | Medium |
| **Several weigh-ins in a day** | Last one wins; morning/evening mix adds noise | Low |
| **Scale changes** | Per-scale offsets work (tested) | OK |
| **Time zones** | Day keys fixed at logging; zone followed when travelling (tested) | OK |
| **Ramadan** | Day start ≥05:00 while on (tested). Check-in still runs weekly as usual; fasting days aren't modelled as such | OK / Low |
| **One energy density** | Gain and loss use the same kcal/kg; early bulk or a lean cut misread | Medium |
| **Low confidence check-ins** | Still propose a change (scaled down); no "no change because data is poor" outcome | Medium |
| **Very low intake** | Floor stops targets going below 1 500/1 200, but nothing notices you eating far below target for weeks | Medium |
| **New user** | Formula prior blends in; no explicit "2 weeks minimum" rule | Low |
| **Replay** | Past check-ins can't be explained: inputs weren't stored and replay uses today's code | High (trust) |
| **AI numbers** | The coach can state numbers the engine never produced | High (trust) |

## 4. Test coverage
| Piece | Tests | Notes |
|---|---|---|
| Targets, protein, floors, fat minimum | `Tests/strategy` (47 checks) | Hand cases; no property tests |
| Check-in smoothing (deadband, caps, confidence, bulk asymmetry) | `Tests/strategy` | Good unit coverage |
| Refeed, diet break, distribution, weekly budget | `Tests/strategy`, `Tests/distribution`, `Tests/budget` | Week totals kept |
| Scales, phases, shadow mode, week plan | `Tests/strategy` | |
| Trend V1 vs V2 | `Tests/trendv2` (5 checks, synthetic) | No uncertainty or rate tests |
| Expenditure algorithms | `Tests/expsim` (simulator, comparative, no pass/fail), `Tests/backtest` (real data vs MacroFactor, report only) | No hand-calculated unit tests; simulator shares the engine's assumptions |
| Time, day boundary, Ramadan | `Tests/time` (21 checks) | |
| Progression, e1RM | `Tests/progression` (8 checks) | Training signals → coaching not tested (none exist) |
| AI coach | none | No eval suite, no validator |

## 5. Things to decide (yours, not mine)
1. **Trend weight.** Your brief asks for a Kalman-style trend. Today's default reproduces MacroFactor's trend almost exactly on your data. A new filter will differ from MacroFactor; I'd keep both and compare in shadow mode before switching. OK?
2. **Default cut rate** (registry will show the evidence: 0.5–1 %/week): 0.5 %, 0.7 % (Garthe), or keep your current 0.5 %?
3. **Default bulk rate** (weak evidence; practitioner convention): 0.25 %/week, or by training age?
4. **Check-in cap:** keep ±150 (−75 on a bulk), or the ±100 you mentioned?
5. **Calorie floor:** move to fat-free-mass-relative (energy availability). It needs a body-fat estimate; without one, fall back to today's 1 500?

Next (after your go-ahead): Phase 1, the Evidence Registry with each citation verified by web search.
