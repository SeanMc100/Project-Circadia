import XCTest
@testable import Circadia

final class RecommendationEngineTests: XCTestCase {
    let cal = TestCal.calendar

    /// Tuesday 6 Oct 2026, woke 7:00, sunrise 7:05, sunset 18:30, targets 7:00 / 23:00.
    private func context(now: Date = TestCal.date(2026, 10, 6, 7, 20),
                         cloudCover: Double? = 0.5,
                         light: DaylightSummary = .empty,
                         hasDaylightData: Bool = true,
                         travel: TravelState? = nil) -> CircadianContext {
        let sun = SunTimes(sunrise: TestCal.date(2026, 10, 6, 7, 5), sunset: TestCal.date(2026, 10, 6, 18, 30),
                           solarNoon: TestCal.date(2026, 10, 6, 12, 47))
        let weather = cloudCover.map {
            WeatherSnapshot(cloudCover: $0, conditionText: "", symbolName: "cloud", uvIndex: 3, temperatureText: nil, isPrecipitating: false, hourly: [])
        }
        return CircadianContext(now: now, calendar: cal, wakeToday: TestCal.date(2026, 10, 6, 7, 0),
                                targetWakeMinutes: 420, targetBedMinutes: 1380, baselineMidpointMinutes: 180,
                                light: light, hasDaylightData: hasDaylightData,
                                sunWeather: SunWeatherSnapshot(sun: sun, weather: weather, source: cloudCover == nil ? .localSolar : .weatherKit, locationIsEstimated: false),
                                travel: travel)
    }

    private func kinds(_ ctx: CircadianContext) -> [RecommendationKind] {
        RecommendationEngine.recommendations(for: ctx).map(\.kind)
    }

    // MARK: Morning light

    func testMorningLightClearSkyIsShorter() throws {
        let rec = try XCTUnwrap(RecommendationEngine.recommendations(for: context(cloudCover: 0.1)).first { $0.kind == .morningLight })
        guard case .outdoorLight(let minutes, let window) = rec.successCriteria else { return XCTFail() }
        XCTAssertEqual(minutes, CircadianConfig.lightMinutesClear)
        XCTAssertEqual(rec.urgency, .now)
        XCTAssertTrue(rec.title.contains("10 minutes"))
        XCTAssertEqual(window.start, TestCal.date(2026, 10, 6, 7, 5), "window opens at sunrise when sunrise is after wake")
        XCTAssertEqual(window.end, TestCal.date(2026, 10, 6, 9, 0))
        XCTAssertEqual(rec.mechanismKey, .lightAndSCN)
    }

    func testMorningLightOvercastIsLongerAndExplainsWhy() throws {
        let rec = try XCTUnwrap(RecommendationEngine.recommendations(for: context(cloudCover: 0.9)).first { $0.kind == .morningLight })
        guard case .outdoorLight(let minutes, _) = rec.successCriteria else { return XCTFail() }
        XCTAssertEqual(minutes, CircadianConfig.lightMinutesOvercast)
        XCTAssertTrue(rec.body.contains("overcast"))
        XCTAssertFalse(rec.body.lowercased().contains("lux"), "must not claim exact lux values")
    }

    func testMorningLightUnknownSkyWhenOffline() throws {
        let rec = try XCTUnwrap(RecommendationEngine.recommendations(for: context(cloudCover: nil)).first { $0.kind == .morningLight })
        XCTAssertTrue(rec.body.contains("Cloud cover is unknown"))
    }

    func testMorningLightHiddenWhenTargetAlreadyMet() {
        let ctx = context(light: DaylightSummary(firstLightAfterWakeMinutes: 10, minutesBeforeNoon: 25, totalMinutes: 25))
        XCTAssertFalse(kinds(ctx).contains(.morningLight))
    }

    func testMorningLightReducedByLightAlreadyLogged() throws {
        let ctx = context(cloudCover: 0.9, light: DaylightSummary(firstLightAfterWakeMinutes: 5, minutesBeforeNoon: 10, totalMinutes: 10))
        let rec = try XCTUnwrap(RecommendationEngine.recommendations(for: ctx).first { $0.kind == .morningLight })
        // The card asks for what's left; success is judged on the whole overcast goal, so the
        // 10 minutes already logged aren't counted twice.
        XCTAssertTrue(rec.title.contains("15 minutes"), rec.title)
        guard case .outdoorLight(let minutes, _) = rec.successCriteria else { return XCTFail() }
        XCTAssertEqual(minutes, 25)
    }

    func testMorningLightUsesStoredGoalAndRoundsWatchMinutes() {
        // Clear-sky goal of 10; the Watch saw 8 minutes, which rounds to 10, so the goal is met.
        var ctx = context(cloudCover: 0.9, light: DaylightSummary(firstLightAfterWakeMinutes: 5, minutesBeforeNoon: 8, totalMinutes: 8))
        ctx.morningGoal = MorningLightGoal(sky: .clear)
        XCTAssertFalse(kinds(ctx).contains(.morningLight))
    }

    func testCompletedKindIsNotRepeated() {
        var ctx = context()
        ctx.completedKinds = [.morningLight]
        XCTAssertFalse(kinds(ctx).contains(.morningLight))
    }

    // MARK: Missed light → afternoon substitute

    func testMissedMorningLightSuggestsWeakerAfternoonLight() throws {
        let ctx = context(now: TestCal.date(2026, 10, 6, 14, 0),
                          light: DaylightSummary(firstLightAfterWakeMinutes: nil, minutesBeforeNoon: 2, totalMinutes: 2))
        let recs = RecommendationEngine.recommendations(for: ctx)
        XCTAssertFalse(recs.contains { $0.kind == .morningLight }, "morning window has closed")
        let late = try XCTUnwrap(recs.first { $0.kind == .lateDayLight })
        XCTAssertTrue(late.body.contains("weaker"), "must be honest that it's a weaker substitute")
        XCTAssertEqual(late.window?.end, TestCal.date(2026, 10, 6, 17, 30), "ends an hour before sunset")
        XCTAssertEqual(late.mechanismKey, .phaseResponse)
    }

    func testNoAfternoonLightWhenMorningWasGood() {
        let ctx = context(now: TestCal.date(2026, 10, 6, 14, 0),
                          light: DaylightSummary(firstLightAfterWakeMinutes: 20, minutesBeforeNoon: 25, totalMinutes: 30))
        XCTAssertFalse(kinds(ctx).contains(.lateDayLight))
    }

    // MARK: Travel

    func testEastwardTravelSeeksMorningLight() throws {
        let travel = TravelState(shiftHours: 6, detectedAt: TestCal.date(2026, 10, 6, 6, 0))
        let ctx = context(now: TestCal.date(2026, 10, 6, 8, 30), travel: travel)
        let recs = RecommendationEngine.recommendations(for: ctx)
        let plan = try XCTUnwrap(recs.first { $0.kind == .travelShift })
        XCTAssertEqual(recs.first?.kind, .travelShift, "travel plan ranks first among equally urgent cards")
        XCTAssertEqual(plan.trackingWindow?.start, TestCal.date(2026, 10, 6, 8, 0))
        XCTAssertEqual(plan.trackingWindow?.end, TestCal.date(2026, 10, 6, 11, 0))
        XCTAssertTrue(plan.title.contains("earlier"))
        XCTAssertTrue(plan.body.contains("keep evenings dim"))
        XCTAssertEqual(plan.steps.count, 6)
        XCTAssertTrue(recs.contains { $0.kind == .morningLight }, "morning light still helps eastward")
        // The evening half of the plan stays visible after the light window closes.
        XCTAssertTrue(kinds(context(now: TestCal.date(2026, 10, 6, 20, 30), travel: travel)).contains(.travelShift))
    }

    func testWestwardTravelSeeksEveningLightAndAvoidsMorningLight() throws {
        let travel = TravelState(shiftHours: -3, detectedAt: TestCal.date(2026, 10, 6, 6, 0))
        let ctx = context(travel: travel)
        let plan = try XCTUnwrap(RecommendationEngine.dailyPlan(for: ctx).first { $0.kind == .travelShift })
        XCTAssertEqual(plan.trackingWindow?.start, TestCal.date(2026, 10, 6, 16, 0))
        XCTAssertEqual(plan.trackingWindow?.end, TestCal.date(2026, 10, 6, 20, 0))
        XCTAssertTrue(plan.title.contains("later"))
        XCTAssertTrue(plan.body.contains("avoid bright light before"))
        XCTAssertFalse(kinds(ctx).contains(.morningLight), "westward plan avoids early light")
    }

    func testLargeEastwardJumpStartsWithLateMorningLight() throws {
        let travel = TravelState(shiftHours: 9, detectedAt: TestCal.date(2026, 10, 6, 6, 0))
        let plan = try XCTUnwrap(RecommendationEngine.dailyPlan(for: context(travel: travel)).first { $0.kind == .travelShift })
        XCTAssertEqual(plan.trackingWindow?.start, TestCal.date(2026, 10, 6, 10, 0))
    }

    func testTravelPlanEndsAfterShiftIsComplete() {
        let travel = TravelState(shiftHours: 2, detectedAt: TestCal.date(2026, 10, 3, 6, 0)) // day 4 of a 2-day plan
        XCTAssertFalse(kinds(context(travel: travel)).contains(.travelShift))
    }

    func testTravelDetectorDirectionAndDST() {
        let ny = TimeZone(identifier: "America/New_York")!
        let paris = TimeZone(identifier: "Europe/Paris")!
        let la = TimeZone(identifier: "America/Los_Angeles")!
        let now = TestCal.date(2026, 10, 6, 12)
        XCTAssertEqual(TravelDetector.evaluate(homeTimeZone: ny, homeLongitude: -74, currentTimeZone: paris, currentLongitude: 2.35, now: now, existing: nil)?.direction, .east)
        XCTAssertEqual(TravelDetector.evaluate(homeTimeZone: ny, homeLongitude: -74, currentTimeZone: la, currentLongitude: -118, now: now, existing: nil)?.shiftHours, -3)
        // Same zone across a DST change is not travel.
        let winter = TestCal.date(2026, 12, 6, 12)
        XCTAssertNil(TravelDetector.evaluate(homeTimeZone: ny, homeLongitude: -74, currentTimeZone: ny, currentLongitude: -74, now: winter, existing: nil))
    }

    // MARK: Other kinds

    func testWindDownTimedFromBedtime() throws {
        let soon = try XCTUnwrap(RecommendationEngine.recommendations(for: context(now: TestCal.date(2026, 10, 6, 19, 30))).first { $0.kind == .windDown })
        XCTAssertEqual(soon.window?.start, TestCal.date(2026, 10, 6, 20, 0), "3 h before an 11 PM bedtime")
        XCTAssertEqual(soon.urgency, .soon)
        let now = try XCTUnwrap(RecommendationEngine.recommendations(for: context(now: TestCal.date(2026, 10, 6, 20, 30))).first { $0.kind == .windDown })
        XCTAssertEqual(now.urgency, .now)
        XCTAssertFalse(kinds(context(now: TestCal.date(2026, 10, 6, 12, 0))).contains(.windDown))
    }

    func testCaffeineCutoff() throws {
        var ctx = context(now: TestCal.date(2026, 10, 6, 10, 0))
        let rec = try XCTUnwrap(RecommendationEngine.recommendations(for: ctx).first { $0.kind == .caffeineCutoff })
        XCTAssertEqual(rec.window?.end, TestCal.date(2026, 10, 6, 14, 0))
        XCTAssertEqual(rec.nudgeDate, TestCal.date(2026, 10, 6, 13, 30))
        ctx.caffeineCutoffHours = 10
        XCTAssertEqual(RecommendationEngine.recommendations(for: ctx).first { $0.kind == .caffeineCutoff }?.window?.end, TestCal.date(2026, 10, 6, 13, 0))
        XCTAssertFalse(kinds(context(now: TestCal.date(2026, 10, 6, 15, 0))).contains(.caffeineCutoff))
    }

    func testAnchorWakeBeforeWeekendWhenSocialJetlagHigh() throws {
        var ctx = context(now: TestCal.date(2026, 10, 9, 18, 0)) // Friday
        ctx.wakeToday = TestCal.date(2026, 10, 9, 7, 0)
        ctx.socialJetlagMinutes = 95
        let rec = try XCTUnwrap(RecommendationEngine.recommendations(for: ctx).first { $0.kind == .anchorWake })
        XCTAssertEqual(rec.urgency, .soon)
        XCTAssertEqual(rec.mechanismKey, .socialJetlag)
        ctx.socialJetlagMinutes = 20
        XCTAssertFalse(kinds(ctx).contains(.anchorWake))
    }

    func testMaintenanceWhenAlignedRanksLast() {
        var ctx = context(now: TestCal.date(2026, 10, 6, 12, 0))
        ctx.alignmentScore = 85
        ctx.streakDays = 5
        let recs = RecommendationEngine.recommendations(for: ctx)
        XCTAssertEqual(recs.last?.kind, .maintenance)
        XCTAssertEqual(recs.last?.title, "5 nights in rhythm")
        ctx.alignmentScore = 60
        XCTAssertFalse(kinds(ctx).contains(.maintenance))
    }

    // MARK: Before sunrise

    func testWakingBeforeSunriseSuggestsBrightIndoorLightFirst() throws {
        var ctx = context(now: TestCal.date(2026, 10, 6, 6, 10), cloudCover: 0.1)
        ctx.wakeToday = TestCal.date(2026, 10, 6, 6, 0) // sunrise 7:05
        let rec = try XCTUnwrap(RecommendationEngine.recommendations(for: ctx).first { $0.kind == .morningLight })
        XCTAssertEqual(rec.urgency, .now)
        XCTAssertTrue(rec.title.contains("before sunrise"))
        XCTAssertTrue(rec.body.contains("light box"))
        XCTAssertTrue(rec.body.contains("check with a doctor"), "light box safety caveat")
        XCTAssertEqual(rec.trackingWindow?.start, TestCal.date(2026, 10, 6, 7, 5), "outdoor credit still starts at sunrise")
        XCTAssertEqual(rec.nudgeDate, TestCal.date(2026, 10, 6, 6, 0))
        // Once the sun is up, the normal "go outside now" card takes over.
        ctx.now = TestCal.date(2026, 10, 6, 7, 10)
        let after = try XCTUnwrap(RecommendationEngine.recommendations(for: ctx).first { $0.kind == .morningLight })
        XCTAssertTrue(after.title.hasPrefix("Go outside now"))
    }

    func testWakingJustBeforeSunriseUsesNormalCard() throws {
        // Default context wakes at 7:00 with sunrise at 7:05: too close to bother with indoor light.
        let rec = try XCTUnwrap(RecommendationEngine.dailyPlan(for: context(now: TestCal.date(2026, 10, 6, 6, 50))).first { $0.kind == .morningLight })
        XCTAssertFalse(rec.title.contains("before sunrise"))
    }

    // MARK: Habits

    func testHabitsSetToNotForMeProduceNoCards() {
        var ctx = context(now: TestCal.date(2026, 10, 6, 10, 0))
        ctx.habits = [.morningLight: .notForMe, .caffeineCutoff: .notForMe, .eveningDim: .notForMe]
        let plan = RecommendationEngine.dailyPlan(for: ctx).map(\.kind)
        XCTAssertFalse(plan.contains(.morningLight))
        XCTAssertFalse(plan.contains(.caffeineCutoff))
        XCTAssertFalse(plan.contains(.windDown))
        ctx.now = TestCal.date(2026, 10, 6, 14, 0)
        XCTAssertFalse(kinds(ctx).contains(.lateDayLight), "afternoon light belongs to the morning light habit")
    }

    func testAlreadyDoHabitsStillShowCards() {
        var ctx = context()
        ctx.habits = [.morningLight: .alreadyDo]
        XCTAssertTrue(kinds(ctx).contains(.morningLight))
    }

    func testEveningPlanListsActiveEveningHabits() throws {
        var ctx = context(now: TestCal.date(2026, 10, 6, 20, 15))
        ctx.habits = [.eveningDim: .wantToStart, .alcoholCutoff: .wantToStart, .screensDown: .alreadyDo]
        let rec = try XCTUnwrap(RecommendationEngine.recommendations(for: ctx).first { $0.kind == .windDown })
        XCTAssertEqual(rec.title, "Start dimming the lights")
        XCTAssertEqual(rec.steps.count, 2)
        XCTAssertTrue(rec.steps[0].hasPrefix("Last drink by"))
        XCTAssertTrue(rec.steps[1].hasPrefix("Screens away by"))

        ctx.habits = [.alcoholCutoff: .wantToStart]
        let noDim = try XCTUnwrap(RecommendationEngine.recommendations(for: ctx).first { $0.kind == .windDown })
        XCTAssertEqual(noDim.title, "Tonight's wind-down")
        XCTAssertEqual(noDim.successCriteria.codeName, "eveningPlan")
    }

    func testOnlyHabitsBeingStartedNudge() {
        let kinds = HabitCatalog.nudgeKinds(for: [.morningLight: .wantToStart, .caffeineCutoff: .alreadyDo, .screensDown: .wantToStart])
        XCTAssertEqual(kinds, [.travelShift, .morningLight, .lateDayLight, .windDown])
    }

    func testHabitTimesArePersonalised() {
        let t = HabitTiming(wakeMinutes: 420, bedMinutes: 1380, caffeineCutoffHours: 9)
        XCTAssertEqual(HabitKey.caffeineCutoff.rule(t), "Last caffeine by \(ClockMath.clockString(14 * 60))")
        XCTAssertEqual(HabitKey.eveningDim.checkInPrompt(t), "Lights dimmed from \(ClockMath.clockString(20 * 60))")
        // Bedtime after midnight wraps correctly.
        let late = HabitTiming(wakeMinutes: 540, bedMinutes: 60)
        XCTAssertEqual(HabitKey.alcoholCutoff.eveningStep(late), "Last drink by \(ClockMath.clockString(22 * 60))")
    }

    func testEveryHabitHasEvidence() {
        XCTAssertEqual(HabitCatalog.ranked.first?.tier, .core)
        XCTAssertEqual(HabitCatalog.ranked.last?.tier, .niche)
        for habit in HabitKey.allCases {
            XCTAssertFalse(habit.why.isEmpty, habit.rawValue)
            XCTAssertFalse(habit.sources.isEmpty, habit.rawValue)
        }
    }

    func testCheckInDueAfterWakeAndOnlyForNightsAfterSetup() {
        let t = HabitTiming(wakeMinutes: 420, bedMinutes: 1380)
        let today = TestCal.day(2026, 10, 7)
        let chosen = TestCal.date(2026, 10, 1, 12)
        func due(_ now: Date, wake: Date? = nil, chosenAt: Date? = chosen) -> Date? {
            HabitCatalog.checkInDay(now: now, activeDay: today, wakeToday: wake, timing: t, habitsChosenAt: chosenAt, calendar: cal)
        }
        XCTAssertNil(due(TestCal.date(2026, 10, 7, 6, 30)), "not before wake")
        XCTAssertEqual(due(TestCal.date(2026, 10, 7, 6, 30), wake: TestCal.date(2026, 10, 7, 6, 15)), TestCal.day(2026, 10, 6))
        XCTAssertEqual(due(TestCal.date(2026, 10, 7, 9, 0)), TestCal.day(2026, 10, 6))
        XCTAssertNil(due(TestCal.date(2026, 10, 7, 17, 0)), "closes in the afternoon")
        XCTAssertNil(due(TestCal.date(2026, 10, 7, 9, 0), chosenAt: TestCal.date(2026, 10, 6, 21, 0)), "chosen after last night's wind-down")
        XCTAssertNil(due(TestCal.date(2026, 10, 7, 9, 0), chosenAt: nil))
    }

    func testCheckInAsksOnlyHabitsBeingStartedThatNeedAnswers() {
        let t = HabitTiming(wakeMinutes: 420, bedMinutes: 1380)
        let habits = HabitCatalog.checkInHabits(for: [.morningLight: .wantToStart, .eveningDim: .wantToStart,
                                                       .alcoholCutoff: .alreadyDo, .darkBedroom: .wantToStart], timing: t)
        XCTAssertEqual(habits, [.eveningDim, .darkBedroom], "morning light is auto-tracked; already-done habits aren't asked")
    }

    func testEveryRecommendationHasMechanismAndStableID() {
        let recs = RecommendationEngine.dailyPlan(for: context())
        XCTAssertFalse(recs.isEmpty)
        for rec in recs {
            XCTAssertFalse(MechanismLibrary.entry(for: rec.mechanismKey).headline.isEmpty)
            XCTAssertTrue(rec.id.hasSuffix("2026-10-06"), rec.id)
        }
    }
}
