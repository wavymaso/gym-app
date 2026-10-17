# Gym design system

Everything lives in `Gym/Design.swift` (motion, haptics, spacing, corners, type, undo) and
`Gym/Theme.swift` (colours: each theme's `Palette`). Screens use these, never raw values.

## Motion: three springs
| Token | Use | Spring |
|---|---|---|
| `Motion.snappy` | taps, toggles, selection, numbers | response 0.28, damping 0.86 |
| `Motion.smooth` | things that move or resize: tabs, cards, toasts | response 0.42, damping 0.90 |
| `Motion.bouncy` | small celebrations (PR trophy, ring closing) | response 0.38, damping 0.62 |

Use `animate(Motion.x) { … }` instead of `withAnimation`. With Reduce Motion on, every animation
becomes a 0.15 s fade and nothing travels or scales. Time-based progress (the rest timer ring) stays linear.

## Haptics: the whole vocabulary
| Call | When |
|---|---|
| `Haptics.tick()` | pickers, steppers, the day strip, switching tab, scrubbing a chart (one per day crossed) |
| `Haptics.tap()` | add to cart, log a set, save a weigh-in, undo offered |
| `Haptics.press()` | long-press actions (log straight away) |
| `Haptics.success()` | log the cart, finish a workout, complete a check-in |
| `Haptics.warning()` | the AI failed, a scan found nothing |
| `Haptics.record()` | a personal record (rising double tap, used for nothing else) |

Never on scrolling or on a tap that didn't change anything.

## Type
Text roles, largest first (all scale with Dynamic Type):

| Role | Base | Use |
|---|---|---|
| `.screenTitle` | largeTitle bold | a page's large title, sentence case ("Food log"); collapses inline on scroll |
| `.sectionTitle` | title2 bold | a group of cards on a page |
| `.subsectionTitle` | title3 semibold | a heading inside a page or sheet |
| `.cardTitle` | headline | a card's or row's title |
| `.bodyText` / `.bodyEmphasis` | body / semibold | running text / a row's main text |
| `.secondaryText` / `.secondaryEmphasis` | subheadline / semibold | details / buttons and values in cards |
| `.note` / `.label` | caption / semibold | small print / small labels and chips |
| `.fine` / `.fineLabel` | caption2 / semibold | axis labels and footnotes / the smallest labels |
| `.sectionLabel` | caption semibold | UPPERCASE tracked section labels, only via `.sectionLabelStyle()` |

No raw `.font(.title…)`, `.font(.caption…)`, `.system(size:)` or `.number(size)` outside Design.swift
and Tokens.swift: `tools/lint-design.sh` (part of `tools/check.sh`) fails on new ones. Justified exceptions
(drawn art at a fixed size, numbers inside a fixed-size ring) go in `tools/design-allowlist.txt` with a
reason.
Numbers (rounded, scale with Dynamic Type): `.numberHero`, `.numberLarge`, `.numberMedium`, `.numberSmall`.
Any number that changes gets `.liveNumber(value)`: tabular digits that roll to the new value.
Units sit next to values in the same size, lighter: `.unitStyle()`.

## Spacing (4/8 pt grid) and corners
`Space.hairline 1 · xxs 2 · xs 4 · s 8 · m 12 · l 16 · xl 24 · xxl 32 · xxxl 48`; `Space.tabBarClearance`
under the last item of a phone scroll view.
`Radius.xs 4 (bars, tracks) · s 8 (chips) · m 12 (buttons, inputs, tiles) · l 18 (cards, rows) · xl 24 (big cards)`.
Nested shapes are concentric: `Radius.inner(outer, inset: padding)`.
Only tokens for padding, stack spacing and corner radii (0 is fine). Negative paddings and alignment
offsets (a column lined up with the time column) are allowlisted.

## Colour
Only from `palette` (accent, calories, protein, fat, carbs, good, warn, background, card, raised).
Macro colours are the same everywhere: rings, bars, charts, the food detail, history.
The accent marks the one thing to do on a screen; it isn't decoration.

## Patterns
- Reversible actions (remove a food, set, weigh-in, photo) happen at once with `UndoCenter.shared.offer("Removed", undo:)`.
  Confirmation dialogs only for things that can't be undone (restore a backup, discard a workout).
- Buttons that are cards get `.pressable()`: they sink slightly while held.
- No spinners for local data; spinners only for the network (AI, sync, a recipe link).
- Empty lists get a designed empty state with one action.
