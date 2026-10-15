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
Text: `.screenTitle` (custom page titles keep `pageTitle`), `.sectionTitle`, `.cardTitle`, `.bodyText`,
`.secondaryText`, `.label`, `.fine`.
Numbers (rounded, scale with Dynamic Type): `.numberHero`, `.numberLarge`, `.numberMedium`, `.numberSmall`.
Any number that changes gets `.liveNumber(value)`: tabular digits that roll to the new value.
Units sit next to values in the same size, lighter: `.unitStyle()`.

## Spacing (4/8 pt grid) and corners
`Space.xxs 2 · xs 4 · s 8 · m 12 · l 16 · xl 24 · xxl 32`
`Radius.s 8 (chips) · m 12 (buttons, inputs, tiles) · l 18 (cards, rows) · xl 24 (big cards)`

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
