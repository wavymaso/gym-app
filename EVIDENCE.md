# Evidence registry

Generated from `Gym/EvidenceRegistry.swift` (don't edit by hand: `Tests/evidence/run.sh write`).

Every citation was checked by web search on 15–16 Oct 2026; entries marked *unverified* couldn't be confirmed and are graded D. Grades: **A** meta-analysis or several RCTs · **B** a single RCT or strong observational/model study · **C** expert consensus, position stand or narrative review · **D** practitioner convention, a fit to data, or the user's choice.

Where the evidence is weak or mixed (diet breaks, refeeds, bulking rates, sleep), it says so here and in the app.

| Id | What | Default | Range | Grade |
|---|---|---|---|---|
| `protein.daily.gPerKg` | Protein beyond about 1.6 g per kg of body weight a day adds little to muscle gained from lifting; the confidence interval reaches about 2.2. | 1.6 g/kg/day | 1.6–2.2 | A |
| `protein.cut.gPerKgLean` | During contest dieting, 2.3–3.1 g of protein per kg of lean body mass a day. | 2.6 g/kg lean mass/day | 2.3–3.1 | C |
| `protein.perMeal.gPerKg` | About 0.4 g of protein per kg per meal across at least four meals reaches at least 1.6 g/kg/day; up to 0.55 g/kg per meal for 2.2 g/kg/day. | 0.4 g/kg/meal | 0.4–0.55 | C |
| `protein.perMeal.min.gPerKg` | The planner's minimum protein for every meal: 0.3 g per kg of body weight (0.4 g/kg, the entry above, for the meals before and after training). | 0.3 g/kg/meal | 0.24–0.4 | D |
| `protein.clamp.gPerKgBody` | Safety clamp: protein from lean mass stays between 1.5 and 2.6 g per kg of body weight, so a wrong body-fat entry can't swing it. | 2.6 g/kg body weight | 1.5–2.6 | D |
| `rate.cut.pctPerWeek` | Lose about 0.5–1% of body weight a week to keep as much muscle as possible. | 0.5 % body weight/week | 0.25–1 | C |
| `rate.bulk.pctPerWeek` | Gain about 0.25–0.5% of body weight a week as a novice or intermediate lifter; slower when advanced. | 0.25 % body weight/week | 0.1–0.5 | C |
| `rate.bulk.byTrainingAge` | A slower gain the more experienced you are: beginner about 0.25%, intermediate 0.15%, advanced 0.1% a week. | 0.15 % body weight/week | 0.1–0.25 | D |
| `fat.cut.pctCalories` | During a cut, 15–30% of calories from fat. | 25 % of calories | 15–30 | C |
| `fat.min.gPerKg` | Never below about 0.5 g of fat per kg of body weight a day. | 0.5 g/kg/day | 0.5–1.5 | C |
| `energy.fat.kcalPerKg` | Changing a kilogram of body fat takes about 39.5 MJ (about 9 400 kcal). | 9440 kcal/kg | 9000–9500 | B |
| `energy.lean.kcalPerKg` | Changing a kilogram of lean tissue takes about 7.6 MJ (about 1 800 kcal). | 1816 kcal/kg | 1700–1900 | B |
| `energy.rule.kcalPerKg` | The old rule of thumb: 7 700 kcal per kg (3 500 kcal per pound), the same both ways. | 7700 kcal/kg | — | D |
| `energy.fitted.kcalPerKg` | 5 500 kcal per kg of trend-weight change: fitted so the expenditure estimate matches MacroFactor on this user's data. | 5500 kcal/kg | — | D |
| `water.glycogen.gPerG` | Each gram of muscle glycogen is stored with at least 3 g of water. | 3 g water/g glycogen | 3–4 | B |
| `water.creatine.litres` | Creatine loading causes short-term fluid retention of about 0.5–1 litre, roughly matching the early weight gain. | 0.75 L | 0.5–1 | C |
| `dietBreak.benefit` | Diet breaks: in obese men, two-week breaks improved weight and fat loss (MATADOR); in resistance-trained adults, one-week breaks gave similar fat loss and lean-mass retention to dieting straight through, with less hunger (ICECAP). | — | — | B |
| `refeed.benefit` | Two carbohydrate refeed days a week during a diet: the authors reported less fat-free-mass loss; a reanalysis found only dry fat-free mass differed. Fat loss was the same. | — | — | B |
| `sleep.deficit` | Sleeping 5.5 instead of 8.5 hours during a two-week diet shifted weight loss from fat towards lean mass. | — | — | B |
| `floor.ea.kcalPerKgFFM` | Energy availability (intake minus exercise energy, per kg of fat-free mass): about 45 is adequate, 30–45 is a reduced range used for fat loss, and 30 or below is a debated risk indicator for low energy availability. | 30 kcal/kg FFM/day | 30–45 | C |
| `floor.fallback` | Without a body-fat estimate, the calorie floor is the Mifflin–St Jeor resting estimate, and never below 1 500 kcal. | 1500 kcal/day | 1200–2000 | D |
| `bmr.mifflin` | Resting energy from weight, height, age and sex (Mifflin–St Jeor). | 0 kcal/day | — | B |
| `recomp.whenSuitable` | Losing fat and gaining muscle at the same time is documented in trained people too, most readily in newer lifters, people with more body fat, or those returning from a break. | — | — | C |
| `checkin.deadband.kcal` | No change if the new calories are within 50 kcal of the current ones. | 50 kcal | 25–100 | D |
| `checkin.cap.up.kcal` | At most 150 kcal more per check-in. | 150 kcal | 100–200 | D |
| `checkin.cap.down.kcal` | At most 150 kcal less per check-in (75 on a bulk). | 150 kcal | 75–200 | D |
| `trend.alpha` | The trend weight takes in about a tenth of each new day (about a 10-day memory). | 0.1 per day | 0.05–0.2 | D |
| `body.fallbackBodyFat` | Without a body-fat measurement, the engine assumes 20% body fat for energy density and lean mass, and asks for a tape measurement. | 20 % | 10–35 | D |
| `limit.deficit.pctExpenditure` | A cut never asks for more than a 25% deficit below expenditure. | 25 % of expenditure | 15–30 | D |
| `limit.surplus.pctExpenditure` | A bulk never asks for more than a 15% surplus above expenditure. | 15 % of expenditure | 5–20 | D |
| `carbs.min.gPerKg` | Carbs stay at or above about 1.5 g per kg on training phases before fat goes below its preferred share. | 1.5 g/kg/day | 1–3 | D |
| `checkin.minDays` | No coaching changes until there are two weeks of data; until then targets come from the formula. | 14 days | 7–21 | D |
| `checkin.minLogged` | A check-in needs at least 4 of the last 7 days logged and 3 weigh-ins, and no water event in the last 3 days; otherwise it makes no change and says why. | 4 days of 7 | 3–6 | D |
| `signal.e1rm.rule` | Estimated 1-rep max is worked out only from sets of 3–10 reps (adjusted for reps in reserve). Two weeks in a row of it falling on main lifts while cutting faster than planned raises a flag. | 2 weeks | 2–4 | D |
| `steps.kcalPerStepPerKg` | Each extra step costs about 0.0005 kcal per kg of body weight (about 0.04 kcal a step at 80 kg). | 0.0005 kcal/step/kg | 0.0004–0.0007 | D |
| `timing.totalFirst` | Total daily protein matters more than its timing: once total intake was accounted for, timing made no clear difference to muscle or strength. | — | — | A |
| `timing.protein.everyHours` | Spread protein in doses of about 20–40 g (0.25–0.40 g/kg) every 3–4 hours. | 3.5 hours | 3–4 | C |
| `timing.preSleep.casein` | About 30–40 g of casein protein before sleep raises overnight muscle protein synthesis; over 12 weeks it went with larger gains, though that group also ate more protein overall. | 35 g | 30–40 | B |
| `timing.preWorkout.carbs` | A meal or snack with carbohydrate (and protein) in the hours before training supports performance. | 2 hours before | 1–4 | C |
| `timing.preWorkout.lowFatFibre` | Keep the last meal before training lower in fat and fibre for comfort. | — | — | D |
| `timing.postWorkout.protein` | Protein from right after training up to about 2 hours later strongly stimulates muscle growth; the 'anabolic window' is wider than once thought, especially if you ate before training. | 2 hours after | 0–4 | C |
| `carbs.training.gPerKg` | For resistance training, 3–7 g of carbohydrate per kg a day is the usual recommendation; a review argues lower intakes may not hurt lifting performance. | 3 g/kg/day | 3–7 | C |
| `carbs.physique.gPerKg` | Bodybuilders have been advised about 4–7 g of carbohydrate per kg a day. Slater & Phillips say strength-sport advice should be individual; the range is a reference, not a target on a cut. | 4 g/kg/day | 4–7 | C |
| `carbs.cut.gPerKg` | During contest dieting a realistic carbohydrate range is 2–5 g per kg a day; very lean phases often need under 4 g/kg. | 3 g/kg/day | 2–5 | C |
| `carbs.performance.nuance` | Carbohydrate improves lifting performance mainly in longer, higher-volume sessions (over about 10 sets per muscle group) and when the comparison is fasted; in typical sessions with matched calories it rarely changes performance, and there was no dose-response. | 10 sets per muscle group | 6–12 | B |
| `carbs.preWorkout.gPerKg` | Eat an easily digestible carbohydrate meal about 2 hours before training; the amount isn't specified in the research. We plan about 0.5–1 g/kg, lower in fat and fibre. | 0.75 g/kg | 0.5–1 | D |
| `timing.glycogen.hours` | Muscle glycogen is restored within 24 hours when the diet has at least 8 g of carbohydrate per kg; with under 4 hours between sessions, 1.2 g/kg/h of carbohydrate is advised. | 24 hours | 4–24 | C |
| `timing.recovery.within24h` | When the next session is less than about 24 hours away, put more of the day's carbs into the post-workout meal and the meals before the next session. | 24 hours | 12–24 | D |
| `carbs.restDay.minGPerKg` | On rest days carbs can go as low as 1.0 g per kg, so more of the week's carbs can move to training days. | 1 g/kg/day | 0.8–1.5 | D |
| `carbs.dayShift.share` | On training days, carbs go up and fat toward its floor; on rest days fat goes up and carbs down; the week's calories stay the same. | 0.5 share of the shift | 0.25–1 | D |
| `carbs.intra.minMinutes` | Carbohydrate during a session (dates, banana, a sports drink) only for sessions longer than about 90 minutes, and only if you turn it on. | 90 minutes | 60–120 | D |
| `timing.fastedTraining` | Training fasted is fine if you prefer it: eating beforehand improved longer aerobic exercise but not shorter sessions. | — | — | C |
| `checkin.q.hunger.high` | Hunger of 4 or 5 (out of 5) at the weekly check-in counts as high hunger. | 4 score 1–5 | 3–5 | D |
| `checkin.q.hungerTiming` | With high hunger, proposes putting more of the same daily calories at the time of day you're hungriest. | — | — | D |
| `checkin.q.highVolume` | With high hunger, proposes more high-volume, low-energy-density foods (vegetables, fruit). In a year-long trial, adding water-rich foods lowered energy density, and that group reported less hunger and lost somewhat more weight. | — | — | B |
| `checkin.q.training.low` | Training quality of 2 or less (out of 5) during a cut counts as low. | 2 score 1–5 | 1–3 | D |
| `checkin.q.trainingCarbs` | Low training quality during a cut: proposes shifting carbs to training days (same weekly calories). | — | — | D |
| `checkin.q.dietBreak` | High hunger plus a plan that's hard to follow (your rating of 4–5, or under 60% of planned meals eaten as planned) for 2 weeks in a row during a cut: proposes a diet break or a maintenance phase. | 2 weeks | 2–4 | D |
| `fibre.per1000kcal` | About 14 g of fibre per 1 000 kcal eaten. | 14 g/1000 kcal | 10–16 | D |
| `partialDay.rule` | A day with fewer than half your usual number of entries and under 60% of its target looks half-logged and waits for your confirmation. | 0.5 share of usual entries | 0.3–0.7 | D |

## Details

### `protein.daily.gPerKg` (grade A)

Protein beyond about 1.6 g per kg of body weight a day adds little to muscle gained from lifting; the confidence interval reaches about 2.2.

- **Studied in:** Healthy adults doing resistance training, mostly not in a deficit (49 studies, 1 863 people).
- **Note:** 1.62 g/kg/day is the breakpoint estimate; benefit was larger in trained lifters and smaller with age.
- Morton RW et al. 2018. A systematic review, meta-analysis and meta-regression of the effect of protein supplementation on resistance training-induced gains in muscle mass and strength in healthy adults. Br J Sports Med 52(6):376–384. <https://doi.org/10.1136/bjsports-2017-097608>

### `protein.cut.gPerKgLean` (grade C)

During contest dieting, 2.3–3.1 g of protein per kg of lean body mass a day.

- **Studied in:** Lean, resistance-trained natural bodybuilders in contest preparation.
- **Note:** A narrative review. Default is mid-range; the higher end suits leaner, longer cuts.
- Helms ER, Aragon AA, Fitschen PJ. 2014. Evidence-based recommendations for natural bodybuilding contest preparation: nutrition and supplementation. J Int Soc Sports Nutr 11:20. <https://doi.org/10.1186/1550-2783-11-20>

### `protein.perMeal.gPerKg` (grade C)

About 0.4 g of protein per kg per meal across at least four meals reaches at least 1.6 g/kg/day; up to 0.55 g/kg per meal for 2.2 g/kg/day.

- **Studied in:** Young resistance-trained adults (review of acute protein-synthesis studies).
- **Note:** A soft guide, not a rule: meal frequency matters little if the daily total is met.
- Schoenfeld BJ, Aragon AA. 2018. How much protein can the body use in a single meal for muscle-building? Implications for daily protein distribution. J Int Soc Sports Nutr 15:10. <https://doi.org/10.1186/s12970-018-0215-1>

### `protein.perMeal.min.gPerKg` (grade D)

The planner's minimum protein for every meal: 0.3 g per kg of body weight (0.4 g/kg, the entry above, for the meals before and after training).

- **Studied in:** —
- **Note:** Your choice. Acute studies put the dose that maximises muscle protein synthesis at about 0.24 g/kg in young men and higher in older adults; 0.3 adds a margin. Not verified as its own finding, so graded D.
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `protein.clamp.gPerKgBody` (grade D)

Safety clamp: protein from lean mass stays between 1.5 and 2.6 g per kg of body weight, so a wrong body-fat entry can't swing it.

- **Studied in:** —
- **Note:** Our guardrail, not a research finding.
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `rate.cut.pctPerWeek` (grade C)

Lose about 0.5–1% of body weight a week to keep as much muscle as possible.

- **Studied in:** Helms: natural bodybuilders. Garthe: 24 elite athletes, 0.7% vs 1.4% a week.
- **Note:** Garthe found the slower rate (0.7%) kept more lean mass and strength during the diet, but no difference after 12 months. Default 0.5% is the user's choice (an alternative considered: 0.7% tapering to 0.5% as body fat falls).
- Helms ER, Aragon AA, Fitschen PJ. 2014. Evidence-based recommendations for natural bodybuilding contest preparation: nutrition and supplementation. J Int Soc Sports Nutr 11:20. <https://doi.org/10.1186/1550-2783-11-20>
- Garthe I et al. 2011. Effect of two different weight-loss rates on body composition and strength and power-related performance in elite athletes. Int J Sport Nutr Exerc Metab 21(2):97–104. <https://doi.org/10.1123/ijsnem.21.2.97>
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `rate.bulk.pctPerWeek` (grade C)

Gain about 0.25–0.5% of body weight a week as a novice or intermediate lifter; slower when advanced.

- **Studied in:** Bodybuilders in the off-season (narrative review).
- **Note:** Weak evidence; a 10–20% surplus is suggested. Default 0.25% is the user's choice.
- Iraki J, Fitschen P, Espinar S, Helms E. 2019. Nutrition recommendations for bodybuilders in the off-season: a narrative review. Sports 7(7):154. <https://doi.org/10.3390/sports7070154>
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `rate.bulk.byTrainingAge` (grade D)

A slower gain the more experienced you are: beginner about 0.25%, intermediate 0.15%, advanced 0.1% a week.

- **Studied in:** —
- **Note:** Practitioner convention; the review only says advanced lifters should gain more slowly. Recorded as an alternative, not active.
- Iraki J, Fitschen P, Espinar S, Helms E. 2019. Nutrition recommendations for bodybuilders in the off-season: a narrative review. Sports 7(7):154. <https://doi.org/10.3390/sports7070154>
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `fat.cut.pctCalories` (grade C)

During a cut, 15–30% of calories from fat.

- **Studied in:** Natural bodybuilders in contest preparation.
- **Note:** Default mid-range.
- Helms ER, Aragon AA, Fitschen PJ. 2014. Evidence-based recommendations for natural bodybuilding contest preparation: nutrition and supplementation. J Int Soc Sports Nutr 11:20. <https://doi.org/10.1186/1550-2783-11-20>

### `fat.min.gPerKg` (grade C)

Never below about 0.5 g of fat per kg of body weight a day.

- **Studied in:** Bodybuilders in the off-season (narrative review suggests 0.5–1.5 g/kg).
- **Note:** Used as the floor in every phase (also with a 40 g minimum, our own guardrail).
- Iraki J, Fitschen P, Espinar S, Helms E. 2019. Nutrition recommendations for bodybuilders in the off-season: a narrative review. Sports 7(7):154. <https://doi.org/10.3390/sports7070154>

### `energy.fat.kcalPerKg` (grade B)

Changing a kilogram of body fat takes about 39.5 MJ (about 9 400 kcal).

- **Studied in:** Model (Forbes body-composition relationship) checked against data from lean and obese adults.
- Hall KD. 2008. What is the required energy deficit per unit weight loss? Int J Obes 32(3):573–576. <https://doi.org/10.1038/sj.ijo.0803720>

### `energy.lean.kcalPerKg` (grade B)

Changing a kilogram of lean tissue takes about 7.6 MJ (about 1 800 kcal).

- **Studied in:** As above.
- **Note:** So the energy in a kilo lost or gained depends on how much of it is lean, which depends on body fat (Forbes): the 7 700 kcal/kg rule overestimates the deficit needed per kg for people with under about 25 kg of body fat.
- Hall KD. 2008. What is the required energy deficit per unit weight loss? Int J Obes 32(3):573–576. <https://doi.org/10.1038/sj.ijo.0803720>

### `energy.rule.kcalPerKg` (grade D)

The old rule of thumb: 7 700 kcal per kg (3 500 kcal per pound), the same both ways.

- **Studied in:** —
- **Note:** Convention. Hall 2008 shows it fits only people with more than about 30 kg of body fat. Used today in targets and the optional V1/joint models.
- Hall KD. 2008. What is the required energy deficit per unit weight loss? Int J Obes 32(3):573–576. <https://doi.org/10.1038/sj.ijo.0803720>

### `energy.fitted.kcalPerKg` (grade D)

5 500 kcal per kg of trend-weight change: fitted so the expenditure estimate matches MacroFactor on this user's data.

- **Studied in:** One person: this user's 2023–2026 data.
- **Note:** Fitted to MacroFactor, not evidence. The baseline the direction-dependent (Forbes/Hall) energy density must beat in the backtest.
- Gym backtest on the user's own data against MacroFactor's exported estimates (Tests/backtest). `tools/backtest.sh`

### `water.glycogen.gPerG` (grade B)

Each gram of muscle glycogen is stored with at least 3 g of water.

- **Studied in:** 9 trained cyclists recovering from prolonged exercise in the heat.
- **Note:** The 1:3 ratio is long-cited; this study measured at least 3 and up to 17 with extra fluid (the excess likely stored apart from glycogen). 
- Fernández-Elías VE, Ortega JF, Nelson RK, Mora-Rodriguez R. 2015. Relationship between muscle water and glycogen recovery after prolonged exercise in the heat in humans. Eur J Appl Physiol 115:1919–1926. <https://doi.org/10.1007/s00421-015-3175-z>

### `water.creatine.litres` (grade C)

Creatine loading causes short-term fluid retention of about 0.5–1 litre, roughly matching the early weight gain.

- **Studied in:** Position stand summarising supplementation studies.
- **Note:** Correction to the brief: the position stand gives 0.5–1.0 L of fluid, not 1–2 kg, and doesn't quantify the weight gain in kg.
- Kreider RB et al. 2017. International Society of Sports Nutrition position stand: safety and efficacy of creatine supplementation in exercise, sport, and medicine. J Int Soc Sports Nutr 14:18. <https://doi.org/10.1186/s12970-017-0173-z>

### `dietBreak.benefit` (grade B)

Diet breaks: in obese men, two-week breaks improved weight and fat loss (MATADOR); in resistance-trained adults, one-week breaks gave similar fat loss and lean-mass retention to dieting straight through, with less hunger (ICECAP).

- **Studied in:** MATADOR: 51 obese men, 30 weeks. ICECAP: 61 resistance-trained adults, 12 weeks.
- **Note:** Mixed: no fat-loss advantage shown in trained people. The app offers breaks for adherence and hunger, never as a fat-loss tool, and never on a timer alone.
- Byrne NM et al. 2018. Intermittent energy restriction improves weight loss efficiency in obese men: the MATADOR study. Int J Obes 42(2):129–138. <https://pmc.ncbi.nlm.nih.gov/articles/PMC5803575/>
- Peos JJ, Helms ER, Fournier PA, Ong J, Hall C, Krieger J, Sainsbury A. 2021. Continuous versus intermittent dieting for fat loss and fat-free mass retention in resistance-trained adults: the ICECAP trial. Med Sci Sports Exerc 53(8):1685–1698. <https://doi.org/10.1249/MSS.0000000000002636>

### `refeed.benefit` (grade B)

Two carbohydrate refeed days a week during a diet: the authors reported less fat-free-mass loss; a reanalysis found only dry fat-free mass differed. Fat loss was the same.

- **Studied in:** 27 resistance-trained adults, 7 weeks.
- **Note:** Small, short, and contested: refeeds are offered as an option, not recommended as a rule.
- Campbell BI et al. 2020. Intermittent energy restriction attenuates the loss of fat free mass in resistance trained individuals: a randomized controlled trial. J Funct Morphol Kinesiol 5(1):19. <https://doi.org/10.3390/jfmk5010019>
- Peos J, Brown AW, Vorland CJ, Allison DB, Sainsbury A. 2020. Contrary to the conclusions stated in the paper, only dry fat-free mass was different between groups upon reanalysis (comment). J Funct Morphol Kinesiol 5(4):85. <https://doi.org/10.3390/jfmk5040085>

### `sleep.deficit` (grade B)

Sleeping 5.5 instead of 8.5 hours during a two-week diet shifted weight loss from fat towards lean mass.

- **Studied in:** 10 overweight adults, 14-day crossover.
- **Note:** Very small and short; used only to raise a flag when logged sleep is short on a cut.
- Nedeltcheva AV et al. 2010. Insufficient sleep undermines dietary efforts to reduce adiposity. Ann Intern Med 153(7):435–441. <https://doi.org/10.7326/0003-4819-153-7-201010050-00006>

### `floor.ea.kcalPerKgFFM` (grade C)

Energy availability (intake minus exercise energy, per kg of fat-free mass): about 45 is adequate, 30–45 is a reduced range used for fat loss, and 30 or below is a debated risk indicator for low energy availability.

- **Studied in:** Athletes (most data in women; the threshold for men is less clear and possibly lower).
- **Note:** The 2023 statement treats 30 as a risk indicator, not a universal cut-off. The app can't measure exercise energy, so it applies the floor to total intake (30 × FFM), which is a lower bound.
- Mountjoy M et al. 2023. 2023 International Olympic Committee's (IOC) consensus statement on Relative Energy Deficiency in Sport (REDs). Br J Sports Med 57(17):1073–1097. <https://doi.org/10.1136/bjsports-2023-106994>

### `floor.fallback` (grade D)

Without a body-fat estimate, the calorie floor is the Mifflin–St Jeor resting estimate, and never below 1 500 kcal.

- **Studied in:** Mifflin: 498 healthy adults aged 19–78 (indirect calorimetry).
- **Note:** The user's choice. The app asks for a tape measurement while the floor is in fallback mode.
- Mifflin MD et al. 1990. A new predictive equation for resting energy expenditure in healthy individuals. Am J Clin Nutr 51(2):241–247. <https://doi.org/10.1093/ajcn/51.2.241>
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `bmr.mifflin` (grade B)

Resting energy from weight, height, age and sex (Mifflin–St Jeor).

- **Studied in:** 498 healthy adults, normal weight and obese.
- **Note:** Harris–Benedict ran about 5% high in the same data.
- Mifflin MD et al. 1990. A new predictive equation for resting energy expenditure in healthy individuals. Am J Clin Nutr 51(2):241–247. <https://doi.org/10.1093/ajcn/51.2.241>

### `recomp.whenSuitable` (grade C)

Losing fat and gaining muscle at the same time is documented in trained people too, most readily in newer lifters, people with more body fat, or those returning from a break.

- **Studied in:** Narrative review of trained and untrained populations.
- **Note:** Only the abstract was verifiable; the 'most readily in…' part reflects the brief and secondary summaries, so treat it as grade C at best.
- Barakat C et al. 2020. Body recomposition: can trained individuals build muscle and lose fat at the same time? Strength Cond J 42(5):7–21. <https://doi.org/10.1519/SSC.0000000000000584>

### `checkin.deadband.kcal` (grade D)

No change if the new calories are within 50 kcal of the current ones.

- **Studied in:** —
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `checkin.cap.up.kcal` (grade D)

At most 150 kcal more per check-in.

- **Studied in:** —
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `checkin.cap.down.kcal` (grade D)

At most 150 kcal less per check-in (75 on a bulk).

- **Studied in:** —
- **Note:** On a bulk the downward cap is 75: slower to cut calories while gaining.
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `trend.alpha` (grade D)

The trend weight takes in about a tenth of each new day (about a 10-day memory).

- **Studied in:** —
- **Note:** Matches MacroFactor's published trend to within 0,01 kg on this user's data.
- Gym backtest on the user's own data against MacroFactor's exported estimates (Tests/backtest). `tools/backtest.sh`

### `body.fallbackBodyFat` (grade D)

Without a body-fat measurement, the engine assumes 20% body fat for energy density and lean mass, and asks for a tape measurement.

- **Studied in:** —
- **Note:** A placeholder, not an estimate of you: replaced as soon as a reading or tape measurement exists.
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `limit.deficit.pctExpenditure` (grade D)

A cut never asks for more than a 25% deficit below expenditure.

- **Studied in:** —
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `limit.surplus.pctExpenditure` (grade D)

A bulk never asks for more than a 15% surplus above expenditure.

- **Studied in:** —
- **Note:** The review suggests a 10–20% surplus for bodybuilders; capped at the middle.
- Iraki J, Fitschen P, Espinar S, Helms E. 2019. Nutrition recommendations for bodybuilders in the off-season: a narrative review. Sports 7(7):154. <https://doi.org/10.3390/sports7070154>
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `carbs.min.gPerKg` (grade D)

Carbs stay at or above about 1.5 g per kg on training phases before fat goes below its preferred share.

- **Studied in:** —
- **Note:** Our own floor; the off-season review suggests 3–5 g/kg, which most cuts can't fit.
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `checkin.minDays` (grade D)

No coaching changes until there are two weeks of data; until then targets come from the formula.

- **Studied in:** —
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `checkin.minLogged` (grade D)

A check-in needs at least 4 of the last 7 days logged and 3 weigh-ins, and no water event in the last 3 days; otherwise it makes no change and says why.

- **Studied in:** —
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `signal.e1rm.rule` (grade D)

Estimated 1-rep max is worked out only from sets of 3–10 reps (adjusted for reps in reserve). Two weeks in a row of it falling on main lifts while cutting faster than planned raises a flag.

- **Studied in:** —
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `steps.kcalPerStepPerKg` (grade D)

Each extra step costs about 0.0005 kcal per kg of body weight (about 0.04 kcal a step at 80 kg).

- **Studied in:** —
- **Note:** Practitioner convention, not verified against a study; the adjustment is short-term only (capped at ±300 kcal) and off by default.
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `timing.totalFirst` (grade A)

Total daily protein matters more than its timing: once total intake was accounted for, timing made no clear difference to muscle or strength.

- **Studied in:** Resistance-training trials (20–23 studies, about 500 people).
- **Note:** A later letter argued few trials truly tested timing; the conclusion that totals come first is the safe reading. The planner never misses a daily total to satisfy a timing rule.
- Schoenfeld BJ, Aragon AA, Krieger JW. 2013. The effect of protein timing on muscle strength and hypertrophy: a meta-analysis. J Int Soc Sports Nutr 10:53. <https://doi.org/10.1186/1550-2783-10-53>

### `timing.protein.everyHours` (grade C)

Spread protein in doses of about 20–40 g (0.25–0.40 g/kg) every 3–4 hours.

- **Studied in:** Position stand; mostly acute muscle-protein-synthesis studies in young adults.
- Kerksick CM et al. 2017. International society of sports nutrition position stand: nutrient timing. J Int Soc Sports Nutr 14:33. <https://doi.org/10.1186/s12970-017-0189-4>
- Schoenfeld BJ, Aragon AA. 2018. How much protein can the body use in a single meal for muscle-building? Implications for daily protein distribution. J Int Soc Sports Nutr 15:10. <https://doi.org/10.1186/s12970-018-0215-1>

### `timing.preSleep.casein` (grade B)

About 30–40 g of casein protein before sleep raises overnight muscle protein synthesis; over 12 weeks it went with larger gains, though that group also ate more protein overall.

- **Studied in:** Res: 16 young men, one night after training. Snijders: young men, 12 weeks of training.
- **Note:** Optional and off by default: the long-term benefit isn't separated from eating more protein in total.
- Res PT et al. 2012. Protein ingestion before sleep improves postexercise overnight recovery. Med Sci Sports Exerc 44(8):1560–1569. <https://pubmed.ncbi.nlm.nih.gov/22330017/>
- Snijders T et al. 2015. Protein ingestion before sleep increases muscle mass and strength gains during prolonged resistance-type exercise training in healthy young men. J Nutr 145(6):1178–1184. <https://doi.org/10.3945/jn.114.208371>
- Kerksick CM et al. 2017. International society of sports nutrition position stand: nutrient timing. J Int Soc Sports Nutr 14:33. <https://doi.org/10.1186/s12970-017-0189-4>

### `timing.preWorkout.carbs` (grade C)

A meal or snack with carbohydrate (and protein) in the hours before training supports performance.

- **Studied in:** Position stand.
- **Note:** The stand says "several hours before" without an exact window: the 1–4 hour range is our planning default.
- Kerksick CM et al. 2017. International society of sports nutrition position stand: nutrient timing. J Int Soc Sports Nutr 14:33. <https://doi.org/10.1186/s12970-017-0189-4>

### `timing.preWorkout.lowFatFibre` (grade D, unverified)

Keep the last meal before training lower in fat and fibre for comfort.

- **Studied in:** —
- **Note:** Practitioner convention for stomach comfort; not found in the position stand. A small preference in the planner, never a rule.
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `timing.postWorkout.protein` (grade C)

Protein from right after training up to about 2 hours later strongly stimulates muscle growth; the 'anabolic window' is wider than once thought, especially if you ate before training.

- **Studied in:** Position stand and narrative review.
- Kerksick CM et al. 2017. International society of sports nutrition position stand: nutrient timing. J Int Soc Sports Nutr 14:33. <https://doi.org/10.1186/s12970-017-0189-4>
- Aragon AA, Schoenfeld BJ. 2013. Nutrient timing revisited: is there a post-exercise anabolic window? J Int Soc Sports Nutr 10:5. <https://doi.org/10.1186/1550-2783-10-5>

### `carbs.training.gPerKg` (grade C)

For resistance training, 3–7 g of carbohydrate per kg a day is the usual recommendation; a review argues lower intakes may not hurt lifting performance.

- **Studied in:** Review; the recommendation is largely borrowed from endurance research.
- **Note:** Context, not a target: on a cut the engine's calorie target decides; the planner only puts more of the day's carbs around training.
- Escobar KA, VanDusseldorp TA, Kerksick CM. 2016. Carbohydrate intake and resistance-based exercise: are current recommendations reflective of actual need? Br J Nutr 116(12):2053–2065. <https://pubmed.ncbi.nlm.nih.gov/27993175/>

### `carbs.physique.gPerKg` (grade C)

Bodybuilders have been advised about 4–7 g of carbohydrate per kg a day. Slater & Phillips say strength-sport advice should be individual; the range is a reference, not a target on a cut.

- **Studied in:** Narrative reviews of physique and strength athletes; Roberts et al. cite 4–7 g/kg from earlier publications.
- **Note:** Shown beside your daily carbs. A target only on a bulk or at maintenance; on a cut the engine's calories decide and carbs are what's left.
- Roberts BM, Helms ER, Trexler ET, Fitschen PJ. 2020. Nutritional recommendations for physique athletes. J Hum Kinet 71:79–108. <https://pmc.ncbi.nlm.nih.gov/articles/PMC7052702/>
- Slater G, Phillips SM. 2011. Nutrition guidelines for strength sports: sprinting, weightlifting, throwing events, and bodybuilding. J Sports Sci 29(S1):S67–S77 (citation checked; the carbohydrate figures in the full text were not available to check). <https://doi.org/10.1080/02640414.2011.574722>
- Escobar KA, VanDusseldorp TA, Kerksick CM. 2016. Carbohydrate intake and resistance-based exercise: are current recommendations reflective of actual need? Br J Nutr 116(12):2053–2065. <https://pubmed.ncbi.nlm.nih.gov/27993175/>

### `carbs.cut.gPerKg` (grade C)

During contest dieting a realistic carbohydrate range is 2–5 g per kg a day; very lean phases often need under 4 g/kg.

- **Studied in:** Narrative review of physique athletes in contest preparation.
- **Note:** So a cut that lands under the 4–7 range is normal, not a mistake.
- Roberts BM, Helms ER, Trexler ET, Fitschen PJ. 2020. Nutritional recommendations for physique athletes. J Hum Kinet 71:79–108. <https://pmc.ncbi.nlm.nih.gov/articles/PMC7052702/>

### `carbs.performance.nuance` (grade B)

Carbohydrate improves lifting performance mainly in longer, higher-volume sessions (over about 10 sets per muscle group) and when the comparison is fasted; in typical sessions with matched calories it rarely changes performance, and there was no dose-response.

- **Studied in:** Systematic review of 49 studies: acute intake 19, glycogen depletion 6, short-term 7, long-term 17. Carbohydrate helped in 6 of 19 acute studies (mostly vs fasted controls and over 10 sets per muscle group), 3 after depletion (mostly twice-a-day sessions, not with matched calories), none of 7 short-term; 15 of 17 long-term studies found no effect.
- **Note:** Why the planner treats carb timing as a mild preference: it sizes carbs around a session by its volume, never at the cost of protein or the calorie target.
- Henselmans M, Bjørnsen T, Hedderman R, Vårvik FT. 2022. The effect of carbohydrate intake on strength and resistance training performance: a systematic review. Nutrients 14(4):856 (first author as recalled; title, journal and findings checked on PubMed 17 Oct 2026). <https://pubmed.ncbi.nlm.nih.gov/35215506/>

### `carbs.preWorkout.gPerKg` (grade D, unverified)

Eat an easily digestible carbohydrate meal about 2 hours before training; the amount isn't specified in the research. We plan about 0.5–1 g/kg, lower in fat and fibre.

- **Studied in:** —
- **Note:** The timing is from a narrative review; the 0.5–1 g/kg amount is your choice (practitioner convention).
- Roberts BM, Helms ER, Trexler ET, Fitschen PJ. 2020. Nutritional recommendations for physique athletes. J Hum Kinet 71:79–108. <https://pmc.ncbi.nlm.nih.gov/articles/PMC7052702/>
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `timing.glycogen.hours` (grade C)

Muscle glycogen is restored within 24 hours when the diet has at least 8 g of carbohydrate per kg; with under 4 hours between sessions, 1.2 g/kg/h of carbohydrate is advised.

- **Studied in:** Position stand, mostly endurance research.
- **Note:** On a cut 8 g/kg is out of reach, so the planner only leans the day's carbs toward the recovery window, and says so.
- Kerksick CM et al. 2017. International society of sports nutrition position stand: nutrient timing. J Int Soc Sports Nutr 14:33. <https://doi.org/10.1186/s12970-017-0189-4>

### `timing.recovery.within24h` (grade D, unverified)

When the next session is less than about 24 hours away, put more of the day's carbs into the post-workout meal and the meals before the next session.

- **Studied in:** —
- **Note:** Our rule, built on glycogen restoration; the share shifted is a setting. A preference within the calories, never above them.
- Kerksick CM et al. 2017. International society of sports nutrition position stand: nutrient timing. J Int Soc Sports Nutr 14:33. <https://doi.org/10.1186/s12970-017-0189-4>
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `carbs.restDay.minGPerKg` (grade D, unverified)

On rest days carbs can go as low as 1.0 g per kg, so more of the week's carbs can move to training days.

- **Studied in:** —
- **Note:** Your choice (17 Oct 2026). The day's calories and protein are unchanged; only the fat/carb split moves.
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `carbs.dayShift.share` (grade D, unverified)

On training days, carbs go up and fat toward its floor; on rest days fat goes up and carbs down; the week's calories stay the same.

- **Studied in:** —
- **Note:** Practitioner convention. The size of the shift is a setting (default: 30% of rest-day carbs).
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `carbs.intra.minMinutes` (grade D, unverified)

Carbohydrate during a session (dates, banana, a sports drink) only for sessions longer than about 90 minutes, and only if you turn it on.

- **Studied in:** —
- **Note:** Convention; the lifting research found no benefit in typical sessions.
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `timing.fastedTraining` (grade C)

Training fasted is fine if you prefer it: eating beforehand improved longer aerobic exercise but not shorter sessions.

- **Studied in:** Meta-analysis of 46 studies, mostly aerobic exercise.
- **Note:** Resistance sessions weren't analysed in the part we could verify; a secondary summary puts the threshold at about an hour. Your choice in the planner.
- Aird TP, Davies RW, Carson BP. 2018. Effects of fasted vs fed-state exercise on performance and post-exercise metabolism: a systematic review and meta-analysis. Scand J Med Sci Sports 28(5):1476–1493. <https://doi.org/10.1111/sms.13054>

### `checkin.q.hunger.high` (grade D, unverified)

Hunger of 4 or 5 (out of 5) at the weekly check-in counts as high hunger.

- **Studied in:** —
- **Note:** A threshold for asking, not a validated cut-off; the 1–5 questions aren't a validated questionnaire.
- Practitioner convention; no trial of this rule was found (17 Oct 2026). `—`

### `checkin.q.hungerTiming` (grade D, unverified)

With high hunger, proposes putting more of the same daily calories at the time of day you're hungriest.

- **Studied in:** —
- **Note:** Meal timing doesn't change fat loss when calories are equal (timing.totalFirst); this is only about comfort and adherence, and untested.
- Practitioner convention; no trial of this rule was found (17 Oct 2026). `—`

### `checkin.q.highVolume` (grade B)

With high hunger, proposes more high-volume, low-energy-density foods (vegetables, fruit). In a year-long trial, adding water-rich foods lowered energy density, and that group reported less hunger and lost somewhat more weight.

- **Studied in:** 97 obese women, 1 year (71 completers).
- **Note:** A single trial in obese women, not lean lifters; the hunger finding is self-reported.
- Ello-Martin JA, Roe LS, Ledikwe JH, Beach AM, Rolls BJ. 2007. Dietary energy density in the treatment of obesity: a year-long trial comparing 2 weight-loss diets. Am J Clin Nutr 85(6):1465–1477. <https://doi.org/10.1093/ajcn/85.6.1465>

### `checkin.q.training.low` (grade D, unverified)

Training quality of 2 or less (out of 5) during a cut counts as low.

- **Studied in:** —
- Practitioner convention; no trial of this rule was found (17 Oct 2026). `—`

### `checkin.q.trainingCarbs` (grade D, unverified)

Low training quality during a cut: proposes shifting carbs to training days (same weekly calories).

- **Studied in:** —
- **Note:** Carbs help lifting mainly in longer, higher-volume sessions (carbs.performance.nuance, graded separately); low self-rated quality has many causes (sleep, stress), so this is a proposal only.
- Practitioner convention; no trial of this rule was found (17 Oct 2026). `—`

### `checkin.q.dietBreak` (grade D, unverified)

High hunger plus a plan that's hard to follow (your rating of 4–5, or under 60% of planned meals eaten as planned) for 2 weeks in a row during a cut: proposes a diet break or a maintenance phase.

- **Studied in:** —
- **Note:** The trigger is a convention (2 weeks: the user's choice, 17 Oct 2026). What breaks do is in dietBreak.benefit (graded B, mixed: less hunger in ICECAP, no fat-loss advantage in trained people).
- Practitioner convention; no trial of this rule was found (17 Oct 2026). `—`
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`

### `fibre.per1000kcal` (grade D, unverified)

About 14 g of fibre per 1 000 kcal eaten.

- **Studied in:** General adult population guidance.
- **Note:** Only confirmed through secondary sources, so graded D until the primary document is checked.
- Dietary Guidelines for Americans (14 g fibre per 1 000 kcal), as reported by secondary sources; the primary document was not checked. <https://www.dietaryguidelines.gov>

### `partialDay.rule` (grade D)

A day with fewer than half your usual number of entries and under 60% of its target looks half-logged and waits for your confirmation.

- **Studied in:** —
- The user's own choice (15 Oct 2026). `COACHING_AUDIT.md`
