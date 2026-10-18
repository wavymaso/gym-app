# On-device checks (things the simulator can't judge)

Tick these on the iPhone after installing. Note anything that feels off and tell me.

## Feel
- [ ] Switching tabs: the new tab fades in from its side (~0.4 s), the pill glides, one light tick. Not sluggish?
- [ ] Haptics feel distinct: tick (tabs, days, chart scrub) · tap (add to cart, log a set, save a weigh-in) · success (log the cart, finish workout, check-in) · PR double tap · warning (AI failed)
- [ ] Scrubbing a 1-year chart: ticks per point aren't a buzz. If they are, tell me and I'll thin them out.
- [ ] Scrolling the dashboard and food log stays smooth at 120 Hz (no stutter when numbers roll)
- [ ] Settings → Accessibility → Motion → Reduce Motion on: nothing slides or scales, things just fade

## Logging
- [ ] Logger reopens on the tab you last used (but never straight into the camera)
- [ ] Tapping ＋ on a food: chip drops into the cart, cart bumps, count rolls
- [ ] Long-press ＋ on a recent food logs it at once and closes the logger
- [ ] Search nonsense ("zzqx"): the "No … anywhere" card; each of its 3 buttons opens the right thing
- [ ] AI with no internet (airplane mode): the problem card with Try again / Describe it instead
- [ ] Remove a food from the timeline → "Removed · Undo" toast → Undo brings it back at the same time
- [ ] Undo after removing several selected foods brings all of them back

## Training
- [ ] Tap a set's weight: keyboard bar shows −2,5 / +2,5 (or your equipment's step) and "Log set"
- [ ] "Log set" from the keyboard checks the set and starts the rest timer
- [ ] A PR: trophy bounces in and the double-tap haptic plays
- [ ] Delete a set → Undo restores it
- [ ] Rest timer digits roll; Live Activity / Dynamic Island still counts down on the lock screen

## Weigh-ins and photos
- [ ] Long-press the Weight Trend or Scale Weight card → Weigh in
- [ ] −0,1 / +0,1 start from your last weight; Save taps and closes
- [ ] Delete a progress photo → Undo restores the photo

## Text size
- [ ] Settings → Display → Text Size at the largest, and Accessibility Larger Text at XL: calories left, rings and set fields still readable and not cut off
- [ ] Light appearance (any finish): problem/empty cards and the undo toast readable

## Added 15 Oct (evening)
- [ ] Food log: select a food → Copy → bar shows To Now / To Today / To Tomorrow / To Date & Time; every hour shows a paste button; swipe to another day and paste there; Undo works
- [ ] Same for Move
- [ ] Strategy → Program style / Check-in day / Training open their own page (no pop-up menu)
- [ ] Settings pickers (units, sex, activity) open a page of choices
- [ ] Nothing scrolls bare under the clock on any tab
- [ ] More → Privacy & security → Lock with Face ID: asks on open and after a minute away; theme change doesn't lock you
- [ ] More → Diagnostics shows real numbers; "Export diagnostics" shares a text file
- [ ] Dashboard banner appears two days before the signature runs out (next: Monday 19 Oct)
- [ ] More → Day start set to 03:00: a snack at 01:00 lands on the previous day
- [ ] Travel: change the time zone in Settings → General → Date & Time with the app open; "Today" follows
- [ ] Gemini key still works after the move to the Keychain (Photo logging shows the key; analyse a photo)
- [ ] Insight charts (Weight Trend, Expenditure, Calories & Macros…): pinch to zoom around your fingers; the strip shows the dates, ‹ › slide, ✕ back to presets; pinching all the way out returns to "All"; touch-and-hold still shows values

## Coaching engine (shadow mode, 16 Oct)
- [ ] Check-in shows "New coaching engine (preview)" with what it would do; Why? opens inputs, rules and evidence (source links open)
- [ ] After finishing a check-in, Strategy → Why these targets? lists it (marked shadow); it reaches the Mac after sync
- [ ] Strategy → Evidence lists the registry by grade
- [ ] Dashboard asks about half-logged days ("Complete" / "Partly")
- [ ] Coaching note on Strategy contains no numbers except the "Today: … kcal left · … g protein to go" line

## AI coach (phase 4)
- [ ] Strategy → Coach card: a morning brief after 05:00; at most the number of messages set in More → Coach
- [ ] With the Mac on and synced, messages say "Written by <your Mac>, checked against your numbers"; with it off, "From the app's rules" (Gemini only if allowed in More → Coach)
- [ ] Every number in a coach message matches one shown elsewhere in the app; the coach never suggests new targets
- [ ] On check-in day the coach explains the engine's decision; "See why" opens the check-in
- [ ] After a workout: a short post-workout note

## Polish pass and one trend (18 Oct, Part A)
- [ ] **One trend:** the trend on the Dashboard, Weight page and Strategy matches More → Diagnostics → Developer (Engine selected), and the same number shows on the Mac after sync
- [ ] **Expenditure:** after the first launch, expenditure moves from the joint model (~2680) to the engine's (~2780); the next check-in applies only part of the change (no jump in targets until then)
- [ ] More → Diagnostics → Developer: the trend and expenditure pickers are there; More and Strategy no longer list "Weight trend"; Expenditure shows only the starting estimate and modifiers
- [ ] **Titles:** every tab has a plain large title (Dashboard, Food log, Strategy, Training, More) that tucks into the bar as you scroll; toolbar buttons sit top right and do what the old round buttons did
- [ ] **Bottom:** no "Search for a food" pill; the last item of every tab (Dashboard → Customize dashboard, Strategy → Goal history, Training, More, Food log, Plan) scrolls fully clear of the tab bar and ＋; search is the magnifier in the Food log bar and in ＋
- [ ] **Food log:** the full hourly timeline, like before; ⋯ → Show empty hours off gives the compact view (logged hours, a dashed "Next planned" row that opens the Plan, thin "＋ Add" gap rows that open the logger at that time)
- [ ] **Charts:** weigh-ins are faint dots, not a line (Weight page and Insights → Weight Trend)
- [ ] **VoiceOver on:** the calorie ring reads "Calories, x of y, z left"; a day pill reads its date and calories; a set row reads "Set 1, weight…, reps…, reps in reserve…, Mark set 1 done"; a plan food reads name, amount, calories and protein; the swap sheet's portion is adjustable by swiping up and down; a chart reads its summary
- [ ] **Largest text (Accessibility XL):** Today, Food log, Plan, Workout and Weight readable with nothing cut off; the tab bar stays its size and long-pressing a tab shows its name big
- [ ] **Profile:** with no name set, More shows a person symbol and "Add your name"; adding one shows your initials
- [ ] What's new appears once (this update, then "Earlier")
- [ ] **Entries to check:** the Dashboard shows one line ("1 entry to check" today: the 1662 kcal potatoes meal); it opens a list with Confirm and Fix per entry; Fix opens the entry; tapping a food in the list opens it too; after Confirm the line disappears
