# Production-readiness gap audit (2026-10-15)

Status per checklist item: **Done**, **Partial**, **Missing**. Then the ranked plan.

## 1. Data safety
| Item | Status | Where / notes |
|---|---|---|
| Versioned schema + tested migrations | Partial | No `VersionedSchema`/`MigrationPlan`; SwiftData lightweight migration only. `Tests/migration` opens a copy of the real store with the current model and checks totals. No automatic pre-migration copy. |
| Automatic backups off the Mac, rotation, restore in app | Partial | `Backup.swift`: daily JSON at launch, 14 kept in-app, 30 in a chosen folder (iCloud Drive works). Restore in Settings (tested, `Tests/backup`). No weekly tier. |
| Full export, open formats, round-trip | Partial | `Export.swift`: CSV per table. The backup JSON is a full archive, but there's no "Export everything" button and no explicit round-trip test of the archive. |
| Soft delete / tombstones | Done | `Tombstone` in `Sync.swift`, every syncable type; undo restores (`Undo.swift`, `Tests/undo`). |
| Integrity check on launch | Missing | No duplicate/orphan check. |

## 2. Sync
| Item | Status | Notes |
|---|---|---|
| Stable UUID, created/modified, device ID | Partial | `syncID` + `modifiedAt` on every record; `createdAt` on some; no device ID. |
| Per-type conflict resolution | Partial | Newest edit wins per record. Food entries and sets are separate records, so they merge naturally; edits to the same record are last-write-wins. |
| Offline-first, visible status | Partial | Phone has its own store and works offline; Sync page shows last sync and errors, no pending count. |
| Idempotent, tested | Partial | Upsert by `syncID` (retries can't duplicate). `Tests/activity-sync` covers some; no clock-skew test. |
| Sync behind a protocol | Missing | `SyncClient`/`SyncServer` are concrete. |

## 3. Time, dates, units
| Item | Status | Notes |
|---|---|---|
| UTC timestamps, log day in local zone at logging | Done | `Date` is absolute; each entry stores its `day` key when logged, so travel can't move it. |
| Day boundary, Ramadan mode | Missing | |
| DST tests | Missing | |
| Metric canonical, display conversion | Done | kg/cm stored; `WeightUnit` converts. |
| Locale parsing (decimal comma) | Done | `parseNumber`, `parseImportNumber`. |

## 4. Correct-numbers safeguards
| Item | Status | Notes |
|---|---|---|
| Scale tags + offsets | Done | `Phases.swift` (scaleOffsets), `ScalesSheet`. |
| Health weight de-duplication | Done | `PhoneOnly.swift` skips days you already weighed in. |
| Food Atwater validation, verified flag | Missing | AI items are corrected (`AIItem.init`); custom foods aren't checked. |
| Refuse broken check-in inputs | Done | `CheckInSummary.needsConfirmation` (big expenditure swings need confirming). |
| Check-in inputs/outputs stored, replayable | Partial | `TargetSet` stores targets, expenditure, reason; shadow mode replays (`replayCheckIns`). Inputs (trend, intake) not stored. |

## 5. Errors and resilience
| Item | Status | Notes |
|---|---|---|
| No `try!`/force unwraps in production paths | Partial | 1 `try!`, ~40 `!` unwraps (mostly safe, e.g. after `isEmpty` checks). |
| Timeouts, retry with backoff, fallback | Partial | Timeouts on all network calls; retry/fallback only for Gemini. |
| Rate-limit messages | Partial | Gemini 429 falls to the next model; USDA 429 shows a raw error. |
| AI failure lands in manual search with the text | Partial | "Describe it instead" / "Try again"; no jump to search. |

## 6. Security and privacy
| Item | Status | Notes |
|---|---|---|
| No keys in repo/history | Done | Verified earlier; keys live in app preferences. |
| Keys in Keychain | Missing | Gemini/USDA keys are in UserDefaults. |
| Face ID lock | Missing | |
| Progress photos never to AI, excluded from exports | Done | Photos never leave the device except your own backups. |
| Food photos: Gemini vs local only | Done | Photo logging → engine (Mac only / Gemini / auto). |

## 7. Settings
| Item | Status | Notes |
|---|---|---|
| One settings model, synced, reset per section | Partial | Profile (synced) + AppStorage (per device). No reset per section. |
| Validation with reasons | Partial | Calorie floor and protein clamps exist in logic; editors don't explain. |
| Feature flags | Missing | |

## 8. Observability
| Item | Status | Notes |
|---|---|---|
| os.Logger categories, no print | Partial | No prints, but no logging either. |
| Diagnostics screen | Missing | |
| MetricKit | Missing | |

## 9. Performance
| Item | Status | Notes |
|---|---|---|
| Search <100 ms, accents, Arabic | Done | FTS5 + folding (`LocalFoods.swift`, `Tests/localfoods`). |
| Launch <1 s | Unmeasured | Needs the phone (Instruments). |
| Virtualised lists, no main-thread DB | Partial | Lazy stacks in most lists; SwiftData reads are on the main actor (fast, cached). |
| Images resized, thumbnails | Partial | Photos resized on save; no separate thumbnails. |

## 10. Accessibility and localisation
| Item | Status | Notes |
|---|---|---|
| VoiceOver labels | Missing | 2 explicit labels; rings/charts unlabeled. |
| Dynamic Type | Partial | Text styles scale; big numbers scale (capped). Unverified at AX sizes. |
| Contrast | Unverified | |
| String Catalog | Missing | |

## 11. Platform
| Item | Status | Notes |
|---|---|---|
| Widgets/intents/Live Activity robustness | Partial | Unverified when the app is killed. |
| Notifications in context, quiet hours, skip if logged | Done | Asked when starting a workout / turning reminders on; reminders skip what's logged. |
| BGTaskScheduler backups | Missing | Backups run at launch only. |
| Signing-expiry warning | Missing | |

## 12. Code health
| Item | Status | Notes |
|---|---|---|
| Logic in a Swift package + backtest CLI | Partial | `Tests/backtest` runs the algorithms on exported data; not a package. |
| Algorithm unit tests on real fixtures | Partial | 19 suites incl. real-data backtest; no snapshot tests. |
| One command to build + test, as a gate | Missing | Ad-hoc script outside the repo. |
| Dead code, files >600 lines | Partial | 8 files over 600 lines. |
| ARCHITECTURE.md | Missing | |

## Ranked plan (risk first), effort
1. **Data loss:** pre-migration snapshot of the store (S); weekly backup tier for 3 months (S); "Export everything" JSON + round-trip test (S); integrity check with safe repair (M).
2. **Wrong numbers:** day-boundary setting, default unchanged (M); DST and travel tests (S); Atwater check on custom foods with a verified flag (S).
3. **Silent failure:** signing-expiry warning (S); keys to Keychain (S); retry/backoff + rate-limit messages for USDA/OFF (S); AI failure → search with your text (S); remove `try!` (S).
4. **Observability:** os.Logger categories, diagnostics screen with export, MetricKit (M).
5. **Platform:** BGTaskScheduler backup (S, device-check); Face ID lock (S, device-check).
6. **Code health:** `tools/check.sh` gate (S); ARCHITECTURE.md (S).
7. **Later / large:** logic Swift package (L), snapshot tests (L), String Catalog + RTL (L), sync protocol + device IDs (M), VoiceOver pass (M), Ramadan mode (M), file splits (M).

## Progress (same day)
Done since the audit, each with tests where it can be tested off-device:
- Pre-model-change database copy; recovery screen instead of a crash (no `try!` left on the real store path).
- Integrity check at launch with safe repairs (`Tests/integrity`).
- Backups: 14 daily + weekly for 3 months; full JSON archive export (photos opt-in); lossless round trip proven on real data.
- Day follows your time zone immediately; optional day start; DST and travel tests (`Tests/time`). Backtest outputs identical.
- Atwater check in the custom food editor; "verified" flag on foods (synced).
- Keys in the Keychain; optional Face ID lock; Privacy & security page.
- Food databases retry with backoff; clear outage/rate-limit messages; AI failure → "Search instead" with your text.
- os.Logger categories, Diagnostics page, MetricKit crash/hang summaries.
- Signing-expiry banner two days before.
- `tools/check.sh` gate; ARCHITECTURE.md.
- VoiceOver labels on the number pad, rings, insight cards, logged foods.

Still open (bigger, or needs a decision): logic Swift package + CLI, snapshot tests, String Catalog/RTL,
sync behind a protocol + device IDs, Ramadan mode, splitting the 8 files over 600 lines, BGTaskScheduler
(backups already run every time the app goes to the background), feature flags, per-section settings reset.
