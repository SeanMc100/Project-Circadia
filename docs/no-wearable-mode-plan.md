# Plan: Circadia without a wearable

Status: **phases 1 and 2 implemented** (2026-10-08), with the log-last-night widget moved
up from phase 3. **Light Check is built** but has not passed its validation gate yet
(see `docs/light-check-validation.md`). The rest of phase 3 is not started. Decisions are
in §6.

### Light Check as built

It's built as designed in §4.4.

**Code**

- `LightMeter` turns exposure into a band and a verdict. It's pure and tested.
- `LightMeterCamera` runs the back camera with auto-exposure and polls its settings
  4 times a second. White balance is locked to daylight. The middle of each frame is
  averaged in memory to get the light's colour, then dropped. Nothing is saved.
- `LightCheckView` shows the screen.

**On screen**

- A camera preview to aim with.
- The band, with a ±2× lux range and the light's colour: warm, neutral or cool white,
  or red, amber, blue, purple and so on. The band is on melanopic EDI, so a bright red
  light scores far lower than an equally bright white one. A line explains how much the
  colour counts, e.g. "about 40% of its brightness".
- A "White-paper check" toggle. With paper filling the frame, the reading gets the
  light's own colour and the light falling on you, not light bouncing off the scene. In
  scene mode a strongly coloured reading suggests switching to it.
- A verdict for daytime or evening, picked from the clock and bedtime and switchable.
- A five-band scale.
- "Compare two places", which saves a reading and shows how many times brighter or
  dimmer the next place is.
- In debug builds only, a "What the camera sees" readout. It shows the colour name and
  swatch, RGB, chromaticity, CCT, melanopic ratio, lux, melanopic EDI and the exposure.

**Where it opens from**

- Learn → Tools.
- The morning-light, afternoon-light, travel and wind-down cards.
- The habit sheets for morning light, daytime light, evening dim and screens.

**What's left:** the camera permission is asked on first use. Nothing feeds the score.
Before release, run the validation and tune `CircadianConfig.lightMeterCalibration`.

### Phase 2 as built

Ordered by how much effort each item saves the user.

1. **Morning reminder.** "Log last night?" arrives 30 min after the guessed wake. If
   that lands in quiet hours, it moves to when quiet hours end.
   - "Looks right" saves the guessed night without opening the app.
   - It takes one of the 3 daily notification slots
     (`SleepLogReminderPlanner`, `NotificationPlanner(reservedPerDay:)`).
   - It can be turned off in Settings → Sleep tracking.
2. **Log-last-night widget.** The Focus widget leads with "Asleep 11:25 PM, up 6:30 AM?"
   from an hour before the guessed wake until 4 PM. Its ✓ confirms the night.
   - The widget writes the times to the shared file it already uses for check-offs.
     The app saves them on its next refresh.
   - The reminder and the widget share the id `sleepLog-yyyy-MM-dd`, so confirming in
     one place cancels the other.
3. **Missed night.** The night before last gets a "Missed: Tuesday night" card. It is
   never asked about for nights before the user switched to phone-only
   (`SleepLogPlanner`).
4. **"Your usual sleep."** This is an onboarding step, and is editable in Settings.
   - The answers stand in for missing baseline nights, so the score is "provisional"
     from the first logged night.
   - They also give the weekend-shift estimate (social jetlag) and the weekday/weekend
     pre-fill.
   - They never stand in for consistency, and they never enter the score history.
     Trends, the forecast and insights still use logged nights only.
5. **Light that counts.**
   - Done on a light card asks "About how long were you outside?" (10/20/30+).
   - Done from the widget or a notification records the card's suggested minutes.
   - The morning check-in asks "Got outside within 2 h of waking"; "no" counts as a
     known zero.
   - Days with no answer are unknown, not zero (`DayMetricsBuilder(lightKnownDays:)`).
   - A wearable sensor, when present, always replaces reports.
6. **Gap fill.** After two nights with no wearable sleep, the card asks "No sleep from
   your watch lately".

**Not built:** the Lock Screen widget shows the sleep question, but confirming needs the
Home Screen widget or the notification. Sleep quality and awakenings are still not
asked.

### Phase 1 as built (differences from the original plan)

- **No `CompositeHealthProvider` class.** `AppModel.loadHealthData` merges the logs
  using the pure `SleepLogMerger` in `Core/Engines/SleepLog.swift`. The effect is the
  same (Health wins, engines unchanged), with less code and easier tests.
- **`SleepLogStore` is its own class.** It lives in `Core/Services/SleepLogStore.swift`
  rather than inside `RecommendationStore`.
- **The sleep question is its own card.** `SleepLogCard` (in
  `Features/Today/SleepLogCard.swift`) sits right under the ring, separate from
  `CheckInCard`. The check-in card is hidden whenever a recap exists, but the sleep
  question must always show.
- **Quality and awakenings fields are deferred** to phase 2.
- **The no-wearable demo** is `MockHealthDataProvider.includesWearableData = false`. It
  gives rounded log-style nights with last night left blank to log, and no light
  or heart data.

## 1. What happens today without a wearable

Circadia's whole pipeline starts from HealthKit sleep samples:

```
HealthDataProviding → SleepSessionBuilder → DayMetricsBuilder → CircadianModel (score)
                                                              → ScoreForecaster / ScoreRecapBuilder
                                                              → InsightsEngine / Trends
```

**The key research finding:** since iOS 18, iPhone no longer records any sleep
data. Apple removed the "Track Time in Bed with iPhone" option and stopped writing
`inBed` samples ([Apple dev forums](https://developer.apple.com/forums/thread/761477),
[thread 766977](https://developer.apple.com/forums/thread/766977)). So a user with no
wearable and no third-party sleep app has **zero sleep samples**. The README and the
in-app copy assume an iPhone-only night is possible
(`SleepSessionBuilder` rule 1). For current iOS, that assumption is out of date.

Each part of the app on a phone with no wearable:

| Area | Without a wearable | Where |
|---|---|---|
| Alignment score, calibration, streak | **Never appears.** `snapshot.status == .noData` forever | `CircadianModel.snapshot` |
| Today | "No sleep data yet… ideally from an Apple Watch. Turn on demo data" (a dead end) | `TodayView.swift:26-29` |
| Morning recap, forecast card | Never shown (both need a score) | `ScoreRecap.swift`, `ScoreForecast.swift` |
| Trends | Empty charts | `TrendsViewModel.series` |
| Insights | Stuck on "not enough data" (needs 14 nights) | `InsightsEngine.compute` |
| Targets | Stay at 7:00 / 23:00 defaults unless set by hand (no baseline to follow) | `AppModel.applyBaselineTargetsIfNeeded` |
| `anchorWake` card | Never fires (needs social jetlag or drift) | `RecommendationEngine.anchorWake` |
| `wakeNear` outcomes | Never judged; stays pending | `RecommendationStore.fillOutcomes` |
| Light cards | Work, with manual Done | `RecommendationEngine.morningLight` |
| Late-day light fallback | Works (keys off the missing Done) | `lateDayLight` |
| Wind-down, caffeine, habit check-in | Work fully | |
| Sun/weather, travel plan, nudges, ring | Work fully | |
| Learn / Explainer | Works | |

**Summary:** the coaching half of the app (prescribe and explain) already works
without data. The feedback half (score, recap, forecast, trends, insights) is
completely dark. The feedback half is what makes the app sticky, so it is what this
mode needs to rebuild.

A second group is already in a half-mode: **Oura, Whoop, Fitbit and Garmin users**
write sleep to HealthKit, but they never write `timeInDaylight` (Apple Watch only).
They get a score without its light component. The design below helps them too.

## 2. Design principles

1. **Feed the existing pipeline. Don't fork it.** Turn self-reports into the same
   `SleepSample` and `DaylightSample` values the engines already use. The score,
   forecast, recap, trends and insights then work with almost no engine changes.
2. **Model each signal separately.** Track the source of sleep and of light
   independently. Behind that, show one simple toggle in the UI. This covers
   no-wearable users, non-Apple-wearable users, and Watch users who forgot to wear it.
3. **One tap a day at most.** Pre-fill every question with a best guess, so the
   common answer is "Yes, about right".
4. **Be honest about the data source.** Label anything self-reported ("from your
   sleep log"). Keep the "estimate, not measurement" framing the app already uses.
5. **Wearable data always wins.** Use a diary entry only for a night with no
   HealthKit sleep.

## 3. The toggle

### Setting

```swift
enum TrackingMode: String, Codable { case wearable, phoneOnly }
// AppSettings.trackingMode, default .wearable for existing installs
```

Internally, derive two capabilities each refresh:

- `sleepSource`: `.health` if HealthKit sleep exists for recent nights, else `.diary`
  when `trackingMode == .phoneOnly` (or when filling a gap, see below).
- `lightSource`: `.sensor` if any `timeInDaylight` exists, else `.selfReport`.

### Where users set it

- **Onboarding**, at the start of the `.health` step: "Do you wear something to bed
  that tracks sleep?" The choices are *Apple Watch* / *Another tracker (Oura, Whoop,
  Fitbit…)* / *No*.
  - Apple Watch or another tracker leads to the current "Connect Apple Health" flow.
  - **No** sets `.phoneOnly`. It skips (or makes optional) the Health prompt and adds
    a new **"Your usual sleep"** step (§4.3).
- **Settings → Data & permissions**: a picker named "Sleep & light data" with the
  options *From a wearable* and *I'll log it*. A footer explains the difference.
- **Auto-suggest** (non-blocking banner on Today):
  - In wearable mode, after 3 or more days with no HealthKit sleep: "No sleep data
    from your watch lately. Log last night yourself?" The user can fill the gap
    with the diary without switching modes.
  - In phone-only mode, when HealthKit sleep starts appearing: "We found sleep data
    from <source>. Use it instead?"

## 4. Feature work

### 4.1 Sleep log (core, replaces wearable sleep)

**Model.** Add a new SwiftData `@Model SleepLogEntry` with these fields:
`id` ("sleeplog-yyyy-MM-dd"), `wakeDay`, `onset`, `wake`, `quality` (optional 1–5),
`awakenings` (optional), `loggedAt` and `source` (`.manual` / `.confirmedGuess` /
`.backfill`). Store it alongside `RecommendationRecord` in `PersistentModels.swift`.
Delete it from `RecommendationStore.deleteAll()`.

**Provider.** Add `CompositeHealthProvider: HealthDataProviding`. It wraps the
HealthKit (or mock) provider and the sleep log:

- `sleepSamples` returns the HealthKit samples, plus one
  `SleepSample(stage: .asleepUnspecified, sourceName: "Circadia sleep log",
  isFromWatch: false)` per log entry. **It drops any log entry that overlaps a
  HealthKit asleep sample**, so wearable data wins.
- This has to happen in the provider, not in `SleepSessionBuilder`. The builder
  *unions* overlapping non-Watch sources, which would inflate a night.
- `AppModel.health` returns the composite. Engines don't change.

**Logging UI.** Add a "Last night" row at the top of `CheckInCard`. The existing
card already appears after wake and stays until 4 PM, which is exactly the right
moment.

> **Last night:** asleep ~**11:15 PM**, up **6:50 AM** [Adjust] [Yes ✓]

- Pre-fill priority:
  1. Passive phone hint (§4.5, later phase)
  2. Same weekday last week, or yesterday's entry
  3. Targets
- "Adjust" opens a compact sheet with two wheel pickers, plus optional quality
  and awakenings. The quality and awakenings fields follow the Consensus Sleep
  Diary.
- Allow logging **yesterday's** night until the next check-in, so one missed morning
  doesn't break the run. Allow edits from Trends (tap a night).
- Store the actual minutes chosen. Don't snap to quarter hours: rounding hides
  real variation from the consistency SD.

**Morning reminder.** Add a "Log last night" nudge at target wake + 30 min. It uses
an actionable notification with a "Yes, about right" action, so logging takes zero
taps inside the app. This needs a new notification category in
`NotificationService`, and it counts toward the 3-a-day cap.

**What this unlocks without engine changes:** baseline and calibration (5 nights),
consistency, drift, the score, the streak, recap, forecast, the trends midpoint and
sleep-bar charts, social jetlag, the `anchorWake` card, `wakeNear` outcome judging,
`applyBaselineTargetsIfNeeded`, and the insights wake-anchor and followed-nudge
comparisons.

### 4.2 Self-reported light

At present, Done on a light card marks it followed but records no light. In
phone-only mode, the morning-light score component is left out of the score.

- **Done becomes "How long were you out?"** with chips: *~10 min* / *~20 min* /
  *30+ min*, pre-selected from the card's suggested minutes. It saves a
  `SelfReportedLight` record (SwiftData). The composite provider turns each record
  into a `DaylightSample` ending at the tap time. This applies to light kinds only;
  other kinds keep a single tap.
- **Morning check-in backstop:** in phone-only mode, `HabitKey.morningLight`
  returns a check-in prompt ("Got outside within 2 h of waking"). Today it returns
  nil because Health tracks it. A "Yes" with no earlier Done records a default
  sample at the target minutes, timed mid-window.
- **Split the meaning of `hasDaylightData`.** It means two things today:
  - **(a)** We can auto-detect light. That one gates `RecommendationStore.sync`
    auto-follow and `morningLight` hiding itself once the target is met.
  - **(b)** Zero minutes means zero. That one is per-day in `DayMetrics.hasLightData`.

  With self-reports, (a) must stay **false** (no sensor). (b) must be **per day**:
  true only on days the user answered (Done, check-in yes/no). On an unanswered day
  the light is unknown, not 0. Otherwise one missed tap would sink the score.
  Concretely:
  - Add `CircadianContext.canSenseLight` and `DayMetrics.lightKnown`.
  - Have `CircadianModel.morningLightAssessment` and `InsightsEngine` use
    `lightKnown`.
- Label the component "Morning light (self-reported)" in `HowCalculatedView` and
  in the recap text.

### 4.3 Instant baseline from a chronotype questionnaire

Calibration needs 5 logged nights. That's a week before a no-wearable user sees a
number, and the early drop-off risk is highest then.

- Add an onboarding step, **"Your usual sleep"**. It asks four times: usual
  sleep and wake on **workdays**, and on **free days**. This is the core of the
  Munich ChronoType Questionnaire (MCTQ), a validated self-report instrument. It
  gives mid-sleep on work and free days, the chronotype estimate (MSFsc), and
  social jetlag (MSf − MSw) on day one
  ([MCTQ reference implementation](https://docs.ropensci.org/mctq/reference/msf_sc.html)).
- Store the answers as a `UsualSleep` setting. Use them as:
  - the default targets (workday times) when the user hasn't set any
  - a **provisional baseline**: `CircadianModel.snapshot` uses the MCTQ midpoint
    when there are fewer than `baselineMinimumNights` real nights. The status
    becomes `.provisional` instead of `.calibrating`, so drift is available from
    night 1.
  - provisional social jetlag, so the `anchorWake` weekend card works in week one
  - pre-fill for the sleep log (workday vs free-day answers)
- **Don't write questionnaire answers into history as fake nights.** Trends and
  insights should only show logged nights.
- Show it on Today as "Estimate based on your answers, sharpening as you log
  (2/5 nights)". The calibrating ring caption gets the same treatment.
- Worth offering to wearable users too ("skip if you've worn your watch for a
  week").
- Optional extra in the same step: "Log the last 3 nights". Short-term recall is
  reasonable, and it makes the first score reflect real nights sooner.

### 4.4 Light Check: camera light meter (both modes, separate track)

A tool for every user, wearable or not. An Apple Watch records how long you're
outside but not how bright your room is. So this is useful to Watch users in the
evening, and to everyone for the "is a bright window enough?" question.

#### Is it valid?

**Yes, as a band classifier. No, as a precise lux reading.** The evidence:

- **Precision.** Phone camera light meters typically read within about ±1 EV of
  a dedicated meter, a factor of about 2
  ([film-photography user comparison](https://www.photrio.com/forum/threads/phone-light-meter-app.139379/post-1820647)).
  The thresholds Circadia cares about are about 10× apart:
  - ≤10 lux for the evening
  - ≥250 lux by day
  - ≥1,000 lux outdoors

  So a factor-of-2 error rarely moves a reading into the wrong band, except right
  at a boundary.
- **Lab results.** A Signify study estimated illuminance (150–3,250 lux) from
  iPhone camera parameters. It also estimated the melanopic daylight efficacy
  ratio (how strongly a light affects the body clock relative to daylight) with
  under 3% error. That study used RAW capture and reference colour samples, a
  controlled setup that is more accurate than what we'd ship
  ([Smartphone-based measurement of the melanopic DER](https://library.imaging.org/admin/apis/public/api/ist/website/downloadArticle/cic/27/1/art00062)).
- **Limits.** Smartphone illuminance is generally considered unreliable where
  precision matters, but adequate for tracking large differences
  ([Brighter Time, PMC9589962](https://pmc.ncbi.nlm.nih.gov/articles/PMC9589962/)).
  The biggest error source is the scene itself. A camera measures **reflected**
  light, so a dark wall reads darker than a white one under the same lamp. Expect
  roughly 2–4× from that alone.

**Conclusion:** valid for the question the app actually asks ("dim enough for
the evening?", "is this window bright enough, or should I go outside?"). It is
not valid as a number to log or score. We prove it with our own validation gate
before shipping (below).

#### How it works

- **Exposure → brightness.** Run `AVCaptureSession` on the back wide camera with
  continuous auto-exposure. Read `iso`, `exposureDuration` and `lensAperture`,
  and correct by `exposureTargetOffset`. Then:
  - Compute `EV100 = log2(N²/t) − log2(ISO/100)`.
  - Estimate illuminance as `E ≈ C · 2^EV100`, with C ≈ 2.5 for an average
    (18% grey) scene.
  - Tune C per device class during validation and keep it in `CircadianConfig`.
  - Frame mean luma flags readings that are clipped or have not settled.
- **Colour → melanopic.** Read `deviceWhiteBalanceGains`, then
  `temperatureAndTintValues(for:)` to get colour temperature (CCT). Map CCT to an
  approximate melanopic daylight efficacy ratio (warm 2,700 K about 0.45, neutral
  4,000 K about 0.65, daylight about 1.0). Melanopic EDI is roughly lux × that
  ratio. This shows *why* warm lamps are better in the evening.
- **How to hold it.** "Hold your phone at eye level and point it where you'd
  normally look." This approximates the light reaching your eyes. An optional
  "steadier reading" mode puts a sheet of white paper over the lens as a diffuser.
  That turns it into an incident reading and removes most of the wall-colour error.
  It needs its own calibration constant.
- **Range.** The camera floor is about 1–5 lux, depending on the exposure limits
  of `activeFormat`. So it can say "below about 5 lux" but cannot confirm a sleep
  level of ≤1 lux. A bedroom check would only say "dark enough to read as near-black".
- **Privacy.** Frames are processed in memory and never saved. Needs
  `NSCameraUsageDescription`. Ask for permission on first use, not in onboarding.

#### What the user sees

A **band and a verdict for the time of day**, with an approximate range. Never
show a precise number.

| Band | Approx. melanopic EDI | Morning verdict | Evening verdict |
|---|---|---|---|
| Very dim | <10 | Too dim to signal your clock | ✓ Good for the 3 h before bed |
| Indoor | 10–250 | Typical room; outside is far brighter | Dim it further: lamps low, overhead off |
| Bright indoor | 250–1,000 | Meets the daytime minimum | Too bright for the evening |
| Outdoor shade / overcast | 1,000–10,000 | ✓ Strong signal | Too bright |
| Sunlit | >10,000 | ✓ Strongest signal; less time needed | — |

Thresholds come from Brown et al. 2022, already cited in `HabitCatalog`:
- ≥250 melanopic EDI by day
- ≤10 in the 3 h before bed

#### Where it appears

- **Learn → Tools**: a standalone "Light Check".
- **Morning-light card**: a "Check your light" link. A comparison mode measures
  inside, then outside, and shows "Outside was ~40× brighter". That's the
  teachable moment.
- **Wind-down card** and the **eveningDim** habit detail sheet: "Is your room dim
  enough?"
- **Never feeds the score or marks a card done.** A single snapshot says nothing
  about duration. In phone-only mode, the light card's minute chips stay the
  self-report.

#### Validation gate (before shipping)

- **Setup:** a reference lux meter, ideally one that also reports CCT, and 3
  iPhone models (oldest supported, mid-range, current Pro).
- **Scenes:** about 40, covering dim lamp-lit evenings, offices, windows,
  overcast and sun, and dark and light walls.
- **Ship when:**
  - at least 90% of readings land in the same band as the reference
  - none is off by 2 bands
  - the evening "≤10 lux" verdict has no false "✓" above 30 lux
- **Record the per-device constants and the results** in a short doc next to
  `CircadianConfig`.
- **If the gate fails:** fall back to the diffuser mode only, or drop the band
  that fails.

### 4.5 Passive hints from the phone (phase 3, optional)

These only ever **pre-fill or suggest**. They never auto-log.

- **Wake guess:** the first sustained motion after the night's longest
  stationary stretch, from `CMMotionActivityManager` (7-day history, no wearable).
  iPhone step samples in HealthKit can corroborate it. This pre-fills the "up at"
  time in the sleep log.
  - Caveat: it detects when the phone was picked up, not when the user woke.
    Label it "first phone activity".
- **Outdoor-walk hint:** a walk of 8 minutes or more, with steps or activity,
  inside the morning window after sunrise. The card asks: "Looks like you were
  walking 8:05–8:20. Count it as outdoor light?"
- Needs `NSMotionUsageDescription` and HealthKit step read. Both are optional
  permissions with a clear "why" screen, matching the existing onboarding style.

### 4.6 Copy and empty states

| Where | Change |
|---|---|
| `TodayView.swift:26-29` | Replace the dead-end empty state. In phone-only mode, show the sleep-log prompt. In wearable mode with no data, offer "Don't wear a tracker? Log your sleep instead". |
| `OnboardingView` `.welcome` / `.health` | Mention logging as an equal option ("Sense: from your watch, or a 5-second morning log"). |
| `CircadianModel.swift:135` | Change "No outdoor-light data (needs Apple Watch)" to mode-aware text. |
| `ForecastCard.swift:95`, `PayoffContent.swift:22` | "seen by Apple Watch" should only appear when sensed. |
| `TrendsView.swift:215` | In phone-only mode, show self-reported light bars and hide the "needs an Apple Watch" note. Hide the HRV/RHR/wrist-temp toggle when there's no data. |
| `LearnView.swift` | Add a "Sleep log" row explaining that sleep diaries are the standard self-report method, plus caveats (recall, rounding). |
| README step 5 | Correct it for iOS 18+ (iPhone no longer records time in bed). |
| Widgets | Phase 3: an interactive "Log last night" widget button (AppIntent, like the existing Focus widget completions via `WidgetShared`). |

### 4.7 Demo data

Add a demo variant, "Demo data (no wearable)", to `MockHealthDataProvider`. It
generates log entries and self-reported light instead of Watch samples, so the
mode can be exercised in the Simulator and in tests.

## 5. Phasing

**Phase 1: make the app work (core).** After this phase, no-wearable users get
the full app after 5 logged nights.

1. `TrackingMode` setting + onboarding question + Settings picker
2. `SleepLogEntry` model + `CompositeHealthProvider` (with "Health wins" de-dup)
3. "Last night" row in `CheckInCard` with pre-fill + adjust sheet
4. Copy and empty-state fixes (§4.6, the rows not marked phase 3)
5. No-wearable demo variant + tests:
   - composite de-dup
   - diary → score
   - `wakeNear` judged from the diary
   - the check-in shows the sleep row only in phone-only mode or gap fill

**Phase 2: make it good from day one.**

6. MCTQ "Your usual sleep" step + provisional baseline (`.provisional` status)
7. Self-reported light: Done with minutes, morning-light check-in backstop,
   `canSenseLight` / `lightKnown` split
8. "Log last night" actionable notification
9. Gap-fill banner for wearable users

**Phase 3: delight.**

10. Motion- and step-based pre-fill and walk hints
11. Log-last-night widget

**Separate track: Light Check (both modes).** It doesn't depend on tracking mode,
so it can start in parallel with phase 1:

- **Spike:** build the exposure-to-band conversion and run the validation gate on
  one device.
- **If the spike passes:** full validation, then the UI and the entry points (§4.4).

## 6. Decisions (resolved 2026-10-08)

1. **Writing sleep logs to Apple Health:** no. Circadia stays read-only.
2. **Score parity:** a phone-only score is the same "Alignment estimate", with a
   "from your sleep log" source line.
3. **Light Check:** in scope as a tool for **both** modes, shipped only if it passes
   the validation gate in §4.4.
4. **Camera and Motion permissions:** ask on first use only, never in onboarding.

## 7. Files touched (phases 1–2)

- `Core/Models/AppSettings.swift`: `trackingMode`, `usualSleep`
- `Core/Models/PersistentModels.swift`: `SleepLogEntry`, `SelfReportedLight`
- `Core/Services/CompositeHealthProvider.swift` (new)
- `Core/Services/HealthDataProviding.swift`: add a `.diary` source kind and an
  auth-state label
- `Core/Services/RecommendationStore.swift`: log CRUD, `deleteAll`
- `App/AppModel.swift`: use the composite, mode-aware refresh, `logSleep(...)`,
  gap detection
- `Core/Engines/CircadianModel.swift`: provisional baseline, `lightKnown`
- `Core/Engines/DayMetricsBuilder.swift`: per-day `lightKnown`
- `Core/Engines/RecommendationEngine.swift`: `canSenseLight`
- `Core/Content/HabitCatalog.swift`: mode-aware `checkInPrompt`
- `Features/Today/CheckInCard.swift`, new `SleepLogSheet.swift`, `TodayView.swift`,
  `RecommendationCard.swift` (Done with minutes)
- `Features/Onboarding/OnboardingView.swift`: tracker question + usual-sleep step
- `Features/Settings/SettingsView.swift`, `Features/Trends/TrendsView.swift`,
  `Features/Learn/LearnView.swift`
- `Core/Services/NotificationService.swift`, `Core/Engines/NotificationPlanner.swift`:
  log reminder
- `Core/Services/MockHealthDataProvider.swift`: no-wearable variant
- Tests: `CompositeProviderTests`, `SleepLogTests`, `ProvisionalBaselineTests`,
  plus updates to `CircadianModelTests` and `RecommendationEngineTests`
