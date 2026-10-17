import Foundation

// The Evidence Registry: every parameter the coaching engine uses, with its default, allowed range,
// source and how strong the evidence is. EVIDENCE.md is generated from this file (Tests/evidence), so
// the two never disagree.
//
// Grades: A meta-analysis or several RCTs · B a single RCT or strong observational/model study ·
// C expert consensus, position stand or narrative review · D practitioner convention, a fit to data,
// or the user's own choice.
// Every citation below was checked by web search on 15 Oct 2026 (`verified`); where only part of a
// claim could be confirmed, `note` says which part.

struct EvidenceSource: Equatable {
    var citation: String          // authors, year, title, journal
    var link: String              // DOI or URL
}

struct EvidenceEntry: Identifiable, Equatable {
    enum Grade: String { case A, B, C, D }
    var id: String
    var description: String      // plain English (the AI coach may quote only this)
    var value: Double             // default
    var range: ClosedRange<Double>
    var unit: String
    var grade: Grade
    var sources: [EvidenceSource]
    var population: String        // who it was studied in
    var note: String = ""         // disagreements, caveats, why this default
    var verified = true           // the citation was found and says what we claim
}

enum Evidence {
    static func value(_ id: String) -> Double { entry(id)?.value ?? .nan }
    static func entry(_ id: String) -> EvidenceEntry? { all.first { $0.id == id } }

    private static let morton = EvidenceSource(citation: "Morton RW et al. 2018. A systematic review, meta-analysis and meta-regression of the effect of protein supplementation on resistance training-induced gains in muscle mass and strength in healthy adults. Br J Sports Med 52(6):376–384",
                                               link: "https://doi.org/10.1136/bjsports-2017-097608")
    private static let helms = EvidenceSource(citation: "Helms ER, Aragon AA, Fitschen PJ. 2014. Evidence-based recommendations for natural bodybuilding contest preparation: nutrition and supplementation. J Int Soc Sports Nutr 11:20",
                                              link: "https://doi.org/10.1186/1550-2783-11-20")
    private static let schoenfeld = EvidenceSource(citation: "Schoenfeld BJ, Aragon AA. 2018. How much protein can the body use in a single meal for muscle-building? Implications for daily protein distribution. J Int Soc Sports Nutr 15:10",
                                                   link: "https://doi.org/10.1186/s12970-018-0215-1")
    private static let garthe = EvidenceSource(citation: "Garthe I et al. 2011. Effect of two different weight-loss rates on body composition and strength and power-related performance in elite athletes. Int J Sport Nutr Exerc Metab 21(2):97–104",
                                               link: "https://doi.org/10.1123/ijsnem.21.2.97")
    private static let iraki = EvidenceSource(citation: "Iraki J, Fitschen P, Espinar S, Helms E. 2019. Nutrition recommendations for bodybuilders in the off-season: a narrative review. Sports 7(7):154",
                                              link: "https://doi.org/10.3390/sports7070154")
    private static let hall = EvidenceSource(citation: "Hall KD. 2008. What is the required energy deficit per unit weight loss? Int J Obes 32(3):573–576",
                                             link: "https://doi.org/10.1038/sj.ijo.0803720")
    private static let glycogen = EvidenceSource(citation: "Fernández-Elías VE, Ortega JF, Nelson RK, Mora-Rodriguez R. 2015. Relationship between muscle water and glycogen recovery after prolonged exercise in the heat in humans. Eur J Appl Physiol 115:1919–1926",
                                                 link: "https://doi.org/10.1007/s00421-015-3175-z")
    private static let kreider = EvidenceSource(citation: "Kreider RB et al. 2017. International Society of Sports Nutrition position stand: safety and efficacy of creatine supplementation in exercise, sport, and medicine. J Int Soc Sports Nutr 14:18",
                                                link: "https://doi.org/10.1186/s12970-017-0173-z")
    private static let byrne = EvidenceSource(citation: "Byrne NM et al. 2018. Intermittent energy restriction improves weight loss efficiency in obese men: the MATADOR study. Int J Obes 42(2):129–138",
                                              link: "https://pmc.ncbi.nlm.nih.gov/articles/PMC5803575/")
    private static let peos = EvidenceSource(citation: "Peos JJ, Helms ER, Fournier PA, Ong J, Hall C, Krieger J, Sainsbury A. 2021. Continuous versus intermittent dieting for fat loss and fat-free mass retention in resistance-trained adults: the ICECAP trial. Med Sci Sports Exerc 53(8):1685–1698",
                                             link: "https://doi.org/10.1249/MSS.0000000000002636")
    private static let campbell = EvidenceSource(citation: "Campbell BI et al. 2020. Intermittent energy restriction attenuates the loss of fat free mass in resistance trained individuals: a randomized controlled trial. J Funct Morphol Kinesiol 5(1):19",
                                                 link: "https://doi.org/10.3390/jfmk5010019")
    private static let campbellReanalysis = EvidenceSource(citation: "Peos J, Brown AW, Vorland CJ, Allison DB, Sainsbury A. 2020. Contrary to the conclusions stated in the paper, only dry fat-free mass was different between groups upon reanalysis (comment). J Funct Morphol Kinesiol 5(4):85",
                                                           link: "https://doi.org/10.3390/jfmk5040085")
    private static let nedeltcheva = EvidenceSource(citation: "Nedeltcheva AV et al. 2010. Insufficient sleep undermines dietary efforts to reduce adiposity. Ann Intern Med 153(7):435–441",
                                                    link: "https://doi.org/10.7326/0003-4819-153-7-201010050-00006")
    private static let reds = EvidenceSource(citation: "Mountjoy M et al. 2023. 2023 International Olympic Committee's (IOC) consensus statement on Relative Energy Deficiency in Sport (REDs). Br J Sports Med 57(17):1073–1097",
                                             link: "https://doi.org/10.1136/bjsports-2023-106994")
    private static let mifflin = EvidenceSource(citation: "Mifflin MD et al. 1990. A new predictive equation for resting energy expenditure in healthy individuals. Am J Clin Nutr 51(2):241–247",
                                                link: "https://doi.org/10.1093/ajcn/51.2.241")
    private static let barakat = EvidenceSource(citation: "Barakat C et al. 2020. Body recomposition: can trained individuals build muscle and lose fat at the same time? Strength Cond J 42(5):7–21",
                                                link: "https://doi.org/10.1519/SSC.0000000000000584")
    private static let schoenfeld2013 = EvidenceSource(citation: "Schoenfeld BJ, Aragon AA, Krieger JW. 2013. The effect of protein timing on muscle strength and hypertrophy: a meta-analysis. J Int Soc Sports Nutr 10:53",
                                                       link: "https://doi.org/10.1186/1550-2783-10-53")
    private static let kerksick = EvidenceSource(citation: "Kerksick CM et al. 2017. International society of sports nutrition position stand: nutrient timing. J Int Soc Sports Nutr 14:33",
                                                 link: "https://doi.org/10.1186/s12970-017-0189-4")
    private static let res = EvidenceSource(citation: "Res PT et al. 2012. Protein ingestion before sleep improves postexercise overnight recovery. Med Sci Sports Exerc 44(8):1560–1569",
                                            link: "https://pubmed.ncbi.nlm.nih.gov/22330017/")
    private static let snijders = EvidenceSource(citation: "Snijders T et al. 2015. Protein ingestion before sleep increases muscle mass and strength gains during prolonged resistance-type exercise training in healthy young men. J Nutr 145(6):1178–1184",
                                                 link: "https://doi.org/10.3945/jn.114.208371")
    private static let aragon2013 = EvidenceSource(citation: "Aragon AA, Schoenfeld BJ. 2013. Nutrient timing revisited: is there a post-exercise anabolic window? J Int Soc Sports Nutr 10:5",
                                                   link: "https://doi.org/10.1186/1550-2783-10-5")
    private static let escobar = EvidenceSource(citation: "Escobar KA, VanDusseldorp TA, Kerksick CM. 2016. Carbohydrate intake and resistance-based exercise: are current recommendations reflective of actual need? Br J Nutr 116(12):2053–2065",
                                                link: "https://pubmed.ncbi.nlm.nih.gov/27993175/")
    private static let henselmans = EvidenceSource(citation: "Henselmans M, Bjørnsen T, Hedderman R, Vårvik FT. 2022. The effect of carbohydrate intake on strength and resistance training performance: a systematic review. Nutrients 14(4):856 (first author as recalled; title, journal and findings checked on PubMed 17 Oct 2026)",
                                                   link: "https://pubmed.ncbi.nlm.nih.gov/35215506/")
    private static let slater = EvidenceSource(citation: "Slater G, Phillips SM. 2011. Nutrition guidelines for strength sports: sprinting, weightlifting, throwing events, and bodybuilding. J Sports Sci 29(S1):S67–S77 (citation checked; the carbohydrate figures in the full text were not available to check)",
                                               link: "https://doi.org/10.1080/02640414.2011.574722")
    private static let roberts = EvidenceSource(citation: "Roberts BM, Helms ER, Trexler ET, Fitschen PJ. 2020. Nutritional recommendations for physique athletes. J Hum Kinet 71:79–108",
                                                link: "https://pmc.ncbi.nlm.nih.gov/articles/PMC7052702/")
    private static let aird = EvidenceSource(citation: "Aird TP, Davies RW, Carson BP. 2018. Effects of fasted vs fed-state exercise on performance and post-exercise metabolism: a systematic review and meta-analysis. Scand J Med Sci Sports 28(5):1476–1493",
                                             link: "https://doi.org/10.1111/sms.13054")
    private static let dga = EvidenceSource(citation: "Dietary Guidelines for Americans (14 g fibre per 1 000 kcal), as reported by secondary sources; the primary document was not checked", link: "https://www.dietaryguidelines.gov")
    private static let backtest = EvidenceSource(citation: "Gym backtest on the user's own data against MacroFactor's exported estimates (Tests/backtest)", link: "tools/backtest.sh")
    private static let elloMartin = EvidenceSource(citation: "Ello-Martin JA, Roe LS, Ledikwe JH, Beach AM, Rolls BJ. 2007. Dietary energy density in the treatment of obesity: a year-long trial comparing 2 weight-loss diets. Am J Clin Nutr 85(6):1465–1477",
                                                   link: "https://doi.org/10.1093/ajcn/85.6.1465")
    private static let convention = EvidenceSource(citation: "Practitioner convention; no trial of this rule was found (17 Oct 2026)", link: "—")
    private static let mine = EvidenceSource(citation: "The user's own choice (15 Oct 2026)", link: "COACHING_AUDIT.md")

    static let all: [EvidenceEntry] = [
        // MARK: Protein
        .init(id: "protein.daily.gPerKg", description: "Protein beyond about 1.6 g per kg of body weight a day adds little to muscle gained from lifting; the confidence interval reaches about 2.2.",
              value: 1.6, range: 1.6...2.2, unit: "g/kg/day", grade: .A, sources: [morton],
              population: "Healthy adults doing resistance training, mostly not in a deficit (49 studies, 1 863 people).",
              note: "1.62 g/kg/day is the breakpoint estimate; benefit was larger in trained lifters and smaller with age."),
        .init(id: "protein.cut.gPerKgLean", description: "During contest dieting, 2.3–3.1 g of protein per kg of lean body mass a day.",
              value: 2.6, range: 2.3...3.1, unit: "g/kg lean mass/day", grade: .C, sources: [helms],
              population: "Lean, resistance-trained natural bodybuilders in contest preparation.",
              note: "A narrative review. Default is mid-range; the higher end suits leaner, longer cuts."),
        .init(id: "protein.perMeal.gPerKg", description: "About 0.4 g of protein per kg per meal across at least four meals reaches at least 1.6 g/kg/day; up to 0.55 g/kg per meal for 2.2 g/kg/day.",
              value: 0.4, range: 0.4...0.55, unit: "g/kg/meal", grade: .C, sources: [schoenfeld],
              population: "Young resistance-trained adults (review of acute protein-synthesis studies).",
              note: "A soft guide, not a rule: meal frequency matters little if the daily total is met."),
        .init(id: "protein.perMeal.min.gPerKg", description: "The planner's minimum protein for every meal: 0.3 g per kg of body weight (0.4 g/kg, the entry above, for the meals before and after training).",
              value: 0.3, range: 0.24...0.4, unit: "g/kg/meal", grade: .D, sources: [mine],
              population: "—", note: "Your choice. Acute studies put the dose that maximises muscle protein synthesis at about 0.24 g/kg in young men and higher in older adults; 0.3 adds a margin. Not verified as its own finding, so graded D."),
        .init(id: "protein.clamp.gPerKgBody", description: "Safety clamp: protein from lean mass stays between 1.5 and 2.6 g per kg of body weight, so a wrong body-fat entry can't swing it.",
              value: 2.6, range: 1.5...2.6, unit: "g/kg body weight", grade: .D, sources: [mine],
              population: "—", note: "Our guardrail, not a research finding."),

        // MARK: Rate of change
        .init(id: "rate.cut.pctPerWeek", description: "Lose about 0.5–1% of body weight a week to keep as much muscle as possible.",
              value: 0.5, range: 0.25...1.0, unit: "% body weight/week", grade: .C, sources: [helms, garthe, mine],
              population: "Helms: natural bodybuilders. Garthe: 24 elite athletes, 0.7% vs 1.4% a week.",
              note: "Garthe found the slower rate (0.7%) kept more lean mass and strength during the diet, but no difference after 12 months. Default 0.5% is the user's choice (an alternative considered: 0.7% tapering to 0.5% as body fat falls)."),
        .init(id: "rate.bulk.pctPerWeek", description: "Gain about 0.25–0.5% of body weight a week as a novice or intermediate lifter; slower when advanced.",
              value: 0.25, range: 0.1...0.5, unit: "% body weight/week", grade: .C, sources: [iraki, mine],
              population: "Bodybuilders in the off-season (narrative review).",
              note: "Weak evidence; a 10–20% surplus is suggested. Default 0.25% is the user's choice."),
        .init(id: "rate.bulk.byTrainingAge", description: "A slower gain the more experienced you are: beginner about 0.25%, intermediate 0.15%, advanced 0.1% a week.",
              value: 0.15, range: 0.1...0.25, unit: "% body weight/week", grade: .D, sources: [iraki, mine],
              population: "—", note: "Practitioner convention; the review only says advanced lifters should gain more slowly. Recorded as an alternative, not active."),

        // MARK: Fat and carbs
        .init(id: "fat.cut.pctCalories", description: "During a cut, 15–30% of calories from fat.",
              value: 25, range: 15...30, unit: "% of calories", grade: .C, sources: [helms],
              population: "Natural bodybuilders in contest preparation.", note: "Default mid-range."),
        .init(id: "fat.min.gPerKg", description: "Never below about 0.5 g of fat per kg of body weight a day.",
              value: 0.5, range: 0.5...1.5, unit: "g/kg/day", grade: .C, sources: [iraki],
              population: "Bodybuilders in the off-season (narrative review suggests 0.5–1.5 g/kg).",
              note: "Used as the floor in every phase (also with a 40 g minimum, our own guardrail)."),

        // MARK: Energy density of weight change
        .init(id: "energy.fat.kcalPerKg", description: "Changing a kilogram of body fat takes about 39.5 MJ (about 9 400 kcal).",
              value: 9440, range: 9000...9500, unit: "kcal/kg", grade: .B, sources: [hall],
              population: "Model (Forbes body-composition relationship) checked against data from lean and obese adults."),
        .init(id: "energy.lean.kcalPerKg", description: "Changing a kilogram of lean tissue takes about 7.6 MJ (about 1 800 kcal).",
              value: 1816, range: 1700...1900, unit: "kcal/kg", grade: .B, sources: [hall],
              population: "As above.", note: "So the energy in a kilo lost or gained depends on how much of it is lean, which depends on body fat (Forbes): the 7 700 kcal/kg rule overestimates the deficit needed per kg for people with under about 25 kg of body fat."),
        .init(id: "energy.rule.kcalPerKg", description: "The old rule of thumb: 7 700 kcal per kg (3 500 kcal per pound), the same both ways.",
              value: 7700, range: 7700...7700, unit: "kcal/kg", grade: .D, sources: [hall],
              population: "—", note: "Convention. Hall 2008 shows it fits only people with more than about 30 kg of body fat. Used today in targets and the optional V1/joint models."),
        .init(id: "energy.fitted.kcalPerKg", description: "5 500 kcal per kg of trend-weight change: fitted so the expenditure estimate matches MacroFactor on this user's data.",
              value: 5500, range: 5500...5500, unit: "kcal/kg", grade: .D, sources: [backtest],
              population: "One person: this user's 2023–2026 data.",
              note: "Fitted to MacroFactor, not evidence. The baseline the direction-dependent (Forbes/Hall) energy density must beat in the backtest."),

        // MARK: Water
        .init(id: "water.glycogen.gPerG", description: "Each gram of muscle glycogen is stored with at least 3 g of water.",
              value: 3, range: 3...4, unit: "g water/g glycogen", grade: .B, sources: [glycogen],
              population: "9 trained cyclists recovering from prolonged exercise in the heat.",
              note: "The 1:3 ratio is long-cited; this study measured at least 3 and up to 17 with extra fluid (the excess likely stored apart from glycogen). "),
        .init(id: "water.creatine.litres", description: "Creatine loading causes short-term fluid retention of about 0.5–1 litre, roughly matching the early weight gain.",
              value: 0.75, range: 0.5...1.0, unit: "L", grade: .C, sources: [kreider],
              population: "Position stand summarising supplementation studies.",
              note: "Correction to the brief: the position stand gives 0.5–1.0 L of fluid, not 1–2 kg, and doesn't quantify the weight gain in kg."),

        // MARK: Diet breaks and refeeds (weak, mixed)
        .init(id: "dietBreak.benefit", description: "Diet breaks: in obese men, two-week breaks improved weight and fat loss (MATADOR); in resistance-trained adults, one-week breaks gave similar fat loss and lean-mass retention to dieting straight through, with less hunger (ICECAP).",
              value: 0, range: 0...0, unit: "—", grade: .B, sources: [byrne, peos],
              population: "MATADOR: 51 obese men, 30 weeks. ICECAP: 61 resistance-trained adults, 12 weeks.",
              note: "Mixed: no fat-loss advantage shown in trained people. The app offers breaks for adherence and hunger, never as a fat-loss tool, and never on a timer alone."),
        .init(id: "refeed.benefit", description: "Two carbohydrate refeed days a week during a diet: the authors reported less fat-free-mass loss; a reanalysis found only dry fat-free mass differed. Fat loss was the same.",
              value: 0, range: 0...0, unit: "—", grade: .B, sources: [campbell, campbellReanalysis],
              population: "27 resistance-trained adults, 7 weeks.",
              note: "Small, short, and contested: refeeds are offered as an option, not recommended as a rule."),

        // MARK: Sleep
        .init(id: "sleep.deficit", description: "Sleeping 5.5 instead of 8.5 hours during a two-week diet shifted weight loss from fat towards lean mass.",
              value: 0, range: 0...0, unit: "—", grade: .B, sources: [nedeltcheva],
              population: "10 overweight adults, 14-day crossover.",
              note: "Very small and short; used only to raise a flag when logged sleep is short on a cut."),

        // MARK: Floors
        .init(id: "floor.ea.kcalPerKgFFM", description: "Energy availability (intake minus exercise energy, per kg of fat-free mass): about 45 is adequate, 30–45 is a reduced range used for fat loss, and 30 or below is a debated risk indicator for low energy availability.",
              value: 30, range: 30...45, unit: "kcal/kg FFM/day", grade: .C, sources: [reds],
              population: "Athletes (most data in women; the threshold for men is less clear and possibly lower).",
              note: "The 2023 statement treats 30 as a risk indicator, not a universal cut-off. The app can't measure exercise energy, so it applies the floor to total intake (30 × FFM), which is a lower bound."),
        .init(id: "floor.fallback", description: "Without a body-fat estimate, the calorie floor is the Mifflin–St Jeor resting estimate, and never below 1 500 kcal.",
              value: 1500, range: 1200...2000, unit: "kcal/day", grade: .D, sources: [mifflin, mine],
              population: "Mifflin: 498 healthy adults aged 19–78 (indirect calorimetry).",
              note: "The user's choice. The app asks for a tape measurement while the floor is in fallback mode."),
        .init(id: "bmr.mifflin", description: "Resting energy from weight, height, age and sex (Mifflin–St Jeor).",
              value: 0, range: 0...0, unit: "kcal/day", grade: .B, sources: [mifflin],
              population: "498 healthy adults, normal weight and obese.", note: "Harris–Benedict ran about 5% high in the same data."),

        // MARK: Recomposition
        .init(id: "recomp.whenSuitable", description: "Losing fat and gaining muscle at the same time is documented in trained people too, most readily in newer lifters, people with more body fat, or those returning from a break.",
              value: 0, range: 0...0, unit: "—", grade: .C, sources: [barakat],
              population: "Narrative review of trained and untrained populations.",
              note: "Only the abstract was verifiable; the 'most readily in…' part reflects the brief and secondary summaries, so treat it as grade C at best."),

        // MARK: Check-in rules and model settings (our own choices)
        .init(id: "checkin.deadband.kcal", description: "No change if the new calories are within 50 kcal of the current ones.",
              value: 50, range: 25...100, unit: "kcal", grade: .D, sources: [mine], population: "—"),
        .init(id: "checkin.cap.up.kcal", description: "At most 150 kcal more per check-in.", value: 150, range: 100...200, unit: "kcal", grade: .D, sources: [mine], population: "—"),
        .init(id: "checkin.cap.down.kcal", description: "At most 150 kcal less per check-in (75 on a bulk).", value: 150, range: 75...200, unit: "kcal", grade: .D, sources: [mine], population: "—",
              note: "On a bulk the downward cap is 75: slower to cut calories while gaining."),
        .init(id: "trend.alpha", description: "The trend weight takes in about a tenth of each new day (about a 10-day memory).",
              value: 0.1, range: 0.05...0.2, unit: "per day", grade: .D, sources: [backtest], population: "—",
              note: "Matches MacroFactor's published trend to within 0,01 kg on this user's data."),
        .init(id: "body.fallbackBodyFat", description: "Without a body-fat measurement, the engine assumes 20% body fat for energy density and lean mass, and asks for a tape measurement.",
              value: 20, range: 10...35, unit: "%", grade: .D, sources: [mine], population: "—",
              note: "A placeholder, not an estimate of you: replaced as soon as a reading or tape measurement exists."),
        .init(id: "limit.deficit.pctExpenditure", description: "A cut never asks for more than a 25% deficit below expenditure.",
              value: 25, range: 15...30, unit: "% of expenditure", grade: .D, sources: [mine], population: "—"),
        .init(id: "limit.surplus.pctExpenditure", description: "A bulk never asks for more than a 15% surplus above expenditure.",
              value: 15, range: 5...20, unit: "% of expenditure", grade: .D, sources: [iraki, mine], population: "—",
              note: "The review suggests a 10–20% surplus for bodybuilders; capped at the middle."),
        .init(id: "carbs.min.gPerKg", description: "Carbs stay at or above about 1.5 g per kg on training phases before fat goes below its preferred share.",
              value: 1.5, range: 1...3, unit: "g/kg/day", grade: .D, sources: [mine], population: "—",
              note: "Our own floor; the off-season review suggests 3–5 g/kg, which most cuts can't fit."),
        .init(id: "checkin.minDays", description: "No coaching changes until there are two weeks of data; until then targets come from the formula.",
              value: 14, range: 7...21, unit: "days", grade: .D, sources: [mine], population: "—"),
        .init(id: "checkin.minLogged", description: "A check-in needs at least 4 of the last 7 days logged and 3 weigh-ins, and no water event in the last 3 days; otherwise it makes no change and says why.",
              value: 4, range: 3...6, unit: "days of 7", grade: .D, sources: [mine], population: "—"),
        .init(id: "signal.e1rm.rule", description: "Estimated 1-rep max is worked out only from sets of 3–10 reps (adjusted for reps in reserve). Two weeks in a row of it falling on main lifts while cutting faster than planned raises a flag.",
              value: 2, range: 2...4, unit: "weeks", grade: .D, sources: [mine], population: "—"),
        .init(id: "steps.kcalPerStepPerKg", description: "Each extra step costs about 0.0005 kcal per kg of body weight (about 0.04 kcal a step at 80 kg).",
              value: 0.0005, range: 0.0004...0.0007, unit: "kcal/step/kg", grade: .D, sources: [mine], population: "—",
              note: "Practitioner convention, not verified against a study; the adjustment is short-term only (capped at ±300 kcal) and off by default."),
        // MARK: Timing and distribution (meal planner). Strong: daily totals and protein spread. Weak: exact timing.
        .init(id: "timing.totalFirst", description: "Total daily protein matters more than its timing: once total intake was accounted for, timing made no clear difference to muscle or strength.",
              value: 0, range: 0...0, unit: "—", grade: .A, sources: [schoenfeld2013],
              population: "Resistance-training trials (20–23 studies, about 500 people).",
              note: "A later letter argued few trials truly tested timing; the conclusion that totals come first is the safe reading. The planner never misses a daily total to satisfy a timing rule."),
        .init(id: "timing.protein.everyHours", description: "Spread protein in doses of about 20–40 g (0.25–0.40 g/kg) every 3–4 hours.",
              value: 3.5, range: 3...4, unit: "hours", grade: .C, sources: [kerksick, schoenfeld],
              population: "Position stand; mostly acute muscle-protein-synthesis studies in young adults."),
        .init(id: "timing.preSleep.casein", description: "About 30–40 g of casein protein before sleep raises overnight muscle protein synthesis; over 12 weeks it went with larger gains, though that group also ate more protein overall.",
              value: 35, range: 30...40, unit: "g", grade: .B, sources: [res, snijders, kerksick],
              population: "Res: 16 young men, one night after training. Snijders: young men, 12 weeks of training.",
              note: "Optional and off by default: the long-term benefit isn't separated from eating more protein in total."),
        .init(id: "timing.preWorkout.carbs", description: "A meal or snack with carbohydrate (and protein) in the hours before training supports performance.",
              value: 2, range: 1...4, unit: "hours before", grade: .C, sources: [kerksick],
              population: "Position stand.", note: "The stand says \"several hours before\" without an exact window: the 1–4 hour range is our planning default."),
        .init(id: "timing.preWorkout.lowFatFibre", description: "Keep the last meal before training lower in fat and fibre for comfort.",
              value: 0, range: 0...0, unit: "—", grade: .D, sources: [mine], population: "—",
              note: "Practitioner convention for stomach comfort; not found in the position stand. A small preference in the planner, never a rule.", verified: false),
        .init(id: "timing.postWorkout.protein", description: "Protein from right after training up to about 2 hours later strongly stimulates muscle growth; the 'anabolic window' is wider than once thought, especially if you ate before training.",
              value: 2, range: 0...4, unit: "hours after", grade: .C, sources: [kerksick, aragon2013],
              population: "Position stand and narrative review."),
        .init(id: "carbs.training.gPerKg", description: "For resistance training, 3–7 g of carbohydrate per kg a day is the usual recommendation; a review argues lower intakes may not hurt lifting performance.",
              value: 3, range: 3...7, unit: "g/kg/day", grade: .C, sources: [escobar],
              population: "Review; the recommendation is largely borrowed from endurance research.",
              note: "Context, not a target: on a cut the engine's calorie target decides; the planner only puts more of the day's carbs around training."),
        .init(id: "carbs.physique.gPerKg", description: "Bodybuilders have been advised about 4–7 g of carbohydrate per kg a day. Slater & Phillips say strength-sport advice should be individual; the range is a reference, not a target on a cut.",
              value: 4, range: 4...7, unit: "g/kg/day", grade: .C, sources: [roberts, slater, escobar],
              population: "Narrative reviews of physique and strength athletes; Roberts et al. cite 4–7 g/kg from earlier publications.",
              note: "Shown beside your daily carbs. A target only on a bulk or at maintenance; on a cut the engine's calories decide and carbs are what's left."),
        .init(id: "carbs.cut.gPerKg", description: "During contest dieting a realistic carbohydrate range is 2–5 g per kg a day; very lean phases often need under 4 g/kg.",
              value: 3, range: 2...5, unit: "g/kg/day", grade: .C, sources: [roberts],
              population: "Narrative review of physique athletes in contest preparation.",
              note: "So a cut that lands under the 4–7 range is normal, not a mistake."),
        .init(id: "carbs.performance.nuance", description: "Carbohydrate improves lifting performance mainly in longer, higher-volume sessions (over about 10 sets per muscle group) and when the comparison is fasted; in typical sessions with matched calories it rarely changes performance, and there was no dose-response.",
              value: 10, range: 6...12, unit: "sets per muscle group", grade: .B, sources: [henselmans],
              population: "Systematic review of 49 studies: acute intake 19, glycogen depletion 6, short-term 7, long-term 17. Carbohydrate helped in 6 of 19 acute studies (mostly vs fasted controls and over 10 sets per muscle group), 3 after depletion (mostly twice-a-day sessions, not with matched calories), none of 7 short-term; 15 of 17 long-term studies found no effect.",
              note: "Why the planner treats carb timing as a mild preference: it sizes carbs around a session by its volume, never at the cost of protein or the calorie target."),
        .init(id: "carbs.preWorkout.gPerKg", description: "Eat an easily digestible carbohydrate meal about 2 hours before training; the amount isn't specified in the research. We plan about 0.5–1 g/kg, lower in fat and fibre.",
              value: 0.75, range: 0.5...1.0, unit: "g/kg", grade: .D, sources: [roberts, mine],
              population: "—", note: "The timing is from a narrative review; the 0.5–1 g/kg amount is your choice (practitioner convention).", verified: false),
        .init(id: "timing.glycogen.hours", description: "Muscle glycogen is restored within 24 hours when the diet has at least 8 g of carbohydrate per kg; with under 4 hours between sessions, 1.2 g/kg/h of carbohydrate is advised.",
              value: 24, range: 4...24, unit: "hours", grade: .C, sources: [kerksick],
              population: "Position stand, mostly endurance research.",
              note: "On a cut 8 g/kg is out of reach, so the planner only leans the day's carbs toward the recovery window, and says so."),
        .init(id: "timing.recovery.within24h", description: "When the next session is less than about 24 hours away, put more of the day's carbs into the post-workout meal and the meals before the next session.",
              value: 24, range: 12...24, unit: "hours", grade: .D, sources: [kerksick, mine],
              population: "—", note: "Our rule, built on glycogen restoration; the share shifted is a setting. A preference within the calories, never above them.", verified: false),
        .init(id: "carbs.restDay.minGPerKg", description: "On rest days carbs can go as low as 1.0 g per kg, so more of the week's carbs can move to training days.",
              value: 1.0, range: 0.8...1.5, unit: "g/kg/day", grade: .D, sources: [mine],
              population: "—", note: "Your choice (17 Oct 2026). The day's calories and protein are unchanged; only the fat/carb split moves.", verified: false),
        .init(id: "carbs.dayShift.share", description: "On training days, carbs go up and fat toward its floor; on rest days fat goes up and carbs down; the week's calories stay the same.",
              value: 0.5, range: 0.25...1.0, unit: "share of the shift", grade: .D, sources: [mine],
              population: "—", note: "Practitioner convention. The size of the shift is a setting (default: 30% of rest-day carbs).", verified: false),
        .init(id: "carbs.intra.minMinutes", description: "Carbohydrate during a session (dates, banana, a sports drink) only for sessions longer than about 90 minutes, and only if you turn it on.",
              value: 90, range: 60...120, unit: "minutes", grade: .D, sources: [mine],
              population: "—", note: "Convention; the lifting research found no benefit in typical sessions.", verified: false),
        .init(id: "timing.fastedTraining", description: "Training fasted is fine if you prefer it: eating beforehand improved longer aerobic exercise but not shorter sessions.",
              value: 0, range: 0...0, unit: "—", grade: .C, sources: [aird],
              population: "Meta-analysis of 46 studies, mostly aerobic exercise.",
              note: "Resistance sessions weren't analysed in the part we could verify; a secondary summary puts the threshold at about an hour. Your choice in the planner."),
        // MARK: Weekly check-in questions (proposals only, never automatic changes)
        .init(id: "checkin.q.hunger.high", description: "Hunger of 4 or 5 (out of 5) at the weekly check-in counts as high hunger.",
              value: 4, range: 3...5, unit: "score 1–5", grade: .D, sources: [convention], population: "—",
              note: "A threshold for asking, not a validated cut-off; the 1–5 questions aren't a validated questionnaire.", verified: false),
        .init(id: "checkin.q.hungerTiming", description: "With high hunger, proposes putting more of the same daily calories at the time of day you're hungriest.",
              value: 0, range: 0...0, unit: "—", grade: .D, sources: [convention], population: "—",
              note: "Meal timing doesn't change fat loss when calories are equal (timing.totalFirst); this is only about comfort and adherence, and untested.", verified: false),
        .init(id: "checkin.q.highVolume", description: "With high hunger, proposes more high-volume, low-energy-density foods (vegetables, fruit). In a year-long trial, adding water-rich foods lowered energy density, and that group reported less hunger and lost somewhat more weight.",
              value: 0, range: 0...0, unit: "—", grade: .B, sources: [elloMartin],
              population: "97 obese women, 1 year (71 completers).",
              note: "A single trial in obese women, not lean lifters; the hunger finding is self-reported."),
        .init(id: "checkin.q.training.low", description: "Training quality of 2 or less (out of 5) during a cut counts as low.",
              value: 2, range: 1...3, unit: "score 1–5", grade: .D, sources: [convention], population: "—", verified: false),
        .init(id: "checkin.q.trainingCarbs", description: "Low training quality during a cut: proposes shifting carbs to training days (same weekly calories).",
              value: 0, range: 0...0, unit: "—", grade: .D, sources: [convention], population: "—",
              note: "Carbs help lifting mainly in longer, higher-volume sessions (carbs.performance.nuance, graded separately); low self-rated quality has many causes (sleep, stress), so this is a proposal only.", verified: false),
        .init(id: "checkin.q.dietBreak", description: "High hunger plus a plan that's hard to follow (your rating of 4–5, or under 60% of planned meals eaten as planned) for 2 weeks in a row during a cut: proposes a diet break or a maintenance phase.",
              value: 2, range: 2...4, unit: "weeks", grade: .D, sources: [convention, mine], population: "—",
              note: "The trigger is a convention (2 weeks: the user's choice, 17 Oct 2026). What breaks do is in dietBreak.benefit (graded B, mixed: less hunger in ICECAP, no fat-loss advantage in trained people).", verified: false),

        .init(id: "fibre.per1000kcal", description: "About 14 g of fibre per 1 000 kcal eaten.",
              value: 14, range: 10...16, unit: "g/1000 kcal", grade: .D, sources: [dga], population: "General adult population guidance.",
              note: "Only confirmed through secondary sources, so graded D until the primary document is checked.", verified: false),
        .init(id: "partialDay.rule", description: "A day with fewer than half your usual number of entries and under 60% of its target looks half-logged and waits for your confirmation.",
              value: 0.5, range: 0.3...0.7, unit: "share of usual entries", grade: .D, sources: [mine], population: "—"),
    ]
}
