import Foundation
import Observation
import SwiftData

/// Central coordinator: pulls data from the services, runs the engines, persists recommendations,
/// and schedules nudges. Feature view models read from here.
@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let location: LocationService
    @ObservationIgnored let notifications: NotificationService
    @ObservationIgnored let store: RecommendationStore
    @ObservationIgnored let selfReports: SelfReportStore
    @ObservationIgnored private let healthKitProvider: HealthKitProvider
    @ObservationIgnored private let mockProvider: MockHealthDataProvider
    @ObservationIgnored private let sunWeatherService: SunWeatherService
    /// Outdoor light from a sensor (Apple Watch). Never includes self-reports.
    @ObservationIgnored private var daylightSamples: [DaylightSample] = []
    /// Wake days Health has a night for (logged nights excluded).
    @ObservationIgnored private var healthNightDays: Set<Date> = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// A refresh was requested while one was running.
    @ObservationIgnored private var refreshPending = false

    // MARK: Published state

    private(set) var isRefreshing = false
    private(set) var hasLoadedOnce = false
    private(set) var days: [DayMetrics] = []
    private(set) var nights: [NightRecord] = []
    private(set) var todayDaylight: [DaylightSample] = []
    private(set) var snapshot: CircadianSnapshot = .empty
    /// The alignment estimate for each past day, oldest first.
    private(set) var scoreHistory: [ScorePoint] = []
    private(set) var sunWeather: SunWeatherSnapshot?
    /// Why Apple Weather last failed, if it did (shown in Settings).
    private(set) var weatherError: String?
    private(set) var recommendations: [Recommendation] = []
    private(set) var insights: InsightsResult = .empty
    private(set) var lastRefresh: Date?
    private(set) var dataError: String?
    private(set) var healthAuthorization: HealthAuthorizationState = .notRequested
    private(set) var notificationsAuthorized = false
    private(set) var scheduledNudgeCount = 0
    /// Morning check-in about last night's habits; answered ones stay with their answer.
    /// Empty when not due or skipped.
    private(set) var checkIn: [CheckInItem] = []
    private(set) var checkInDay: Date?
    /// Recommendations checked off today. They stay on Today, marked done.
    private(set) var completedToday: [CompletedRecommendation] = []
    /// What tomorrow's score could be if today and tonight go to plan.
    private(set) var forecast: ScoreForecast?
    /// This morning's score and what moved it. Nil until last night's sleep is in.
    private(set) var recap: ScoreRecap?
    /// "When did you sleep?" for last night (phone-only mode, or a wearable gap). Nil when not needed.
    private(set) var sleepLogPrompt: SleepLogPrompt?
    /// The night before last, when it was missed (phone-only mode).
    private(set) var missedSleepLog: SleepLogPrompt?
    /// Wearable mode: the last night Health has, when the watch has gone quiet for two nights.
    private(set) var sleepLogGapSince: Date?
    /// Whether outdoor light comes from a sensor. Without one, light is self-reported.
    private(set) var canSenseLight = false
    /// Wake days whose night came from the sleep log rather than Health.
    private(set) var loggedDays: Set<Date> = []
    var showRecap = false
    var payoff: PayoffEvent?

    var checkInPending: Bool { checkIn.contains { $0.followed == nil } }

    var calendar: Calendar { .current }

    var health: HealthDataProviding {
        settings.useMockData ? mockProvider : healthKitProvider
    }

    var activeDay: Date {
        ClockMath.activeDay(for: Date(), calendar: calendar)
    }

    init(settings: AppSettings, modelContext: ModelContext, location: LocationService? = nil,
         notifications: NotificationService? = nil,
         sunWeatherService: SunWeatherService = FallbackSunWeatherService(primary: WeatherKitProvider())) {
        self.settings = settings
        self.location = location ?? LocationService()
        self.notifications = notifications ?? NotificationService()
        self.store = RecommendationStore(context: modelContext)
        self.selfReports = SelfReportStore(context: modelContext)
        self.healthKitProvider = HealthKitProvider()
        self.mockProvider = MockHealthDataProvider()
        self.sunWeatherService = sunWeatherService
        wireCallbacks()
    }

    private func wireCallbacks() {
        location.onUpdate = { [weak self] in self?.requestRefresh() }
        notifications.onDismiss = { [weak self] kind in
            self?.settings.recordDismissal(kind)
            self?.requestRefresh()
        }
        notifications.onOpen = { [weak self] kind in self?.settings.resetDismissals(kind) }
        notifications.onDone = { [weak self] kind, id in
            guard let self else { return }
            self.settings.resetDismissals(kind)
            if let id {
                self.store.mark(id: id, status: .followed, detection: .manual, at: Date())
                self.reportDoneLight(recommendationID: id, kind: kind, minutes: nil, at: Date())
            }
            if kind.isLightKind { self.payoff = PayoffEvent(kind: kind, completedAt: Date(), detectedAutomatically: false) }
            self.requestRefresh()
        }
        notifications.onSleepLogConfirm = { [weak self] log in self?.confirmSleepLog(log) }
    }

    // MARK: - Lifecycle

    func start() {
        if location.isAuthorized { location.refresh() }
        healthKitProvider.startObserving { [weak self] in
            guard let self, !self.settings.useMockData else { return }
            self.requestRefresh()
        }
        requestRefresh()
    }

    /// Coalesces refresh requests. One made while a refresh is running queues a single follow-up
    /// pass, so a change saved after the running pass read its data still gets picked up.
    func requestRefresh() {
        guard refreshTask == nil else {
            refreshPending = true
            return
        }
        refreshTask = Task { [weak self] in
            while let self {
                self.refreshPending = false
                await self.performRefresh()
                guard self.refreshPending else { break }
            }
            self?.refreshTask = nil
        }
    }

    /// Refreshes and waits until done, including a pass queued behind one already running.
    func refresh() async {
        requestRefresh()
        await refreshTask?.value
    }

    /// Full pipeline: health → nights/days → model → sun/weather → travel → recommendations →
    /// persistence → insights → notifications.
    private func performRefresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let now = Date()
        let cal = calendar

        applyWidgetSleepLogs()
        // Weather first: it sets the morning light goal the score is measured against.
        await loadSunWeather(now: now)
        updateMorningLightGoals(now: now)
        await loadHealthData(now: now)
        applyBaselineTargetsIfNeeded()
        updateSleepLogPrompt(now: now)
        updateTravel(now: now)

        let day = activeDay
        var context = makeContext(now: now, day: day)
        var plan = RecommendationEngine.dailyPlan(for: context)
        let newlyFollowed = store.sync(plan, day: day, daylight: daylightSamples, hasDaylightData: canSenseLight, now: now)
        let appliedWidgetChecks = applyWidgetCompletions(context: context, now: now)
        let lightFollowed = newlyFollowed.first(where: { $0.kind?.isLightKind == true })
        if let light = lightFollowed, let kind = light.kind {
            payoff = PayoffEvent(kind: kind, completedAt: light.completedAt ?? now, detectedAutomatically: true)
        }
        if appliedWidgetChecks || lightFollowed != nil {
            context.completedKinds = store.resolvedKinds(on: day)
            plan = RecommendationEngine.dailyPlan(for: context)
        }
        recommendations = RecommendationEngine.recommendations(for: context)
        completedToday = store.completed(on: day)
        updateCheckIn(context: context)
        updateForecastAndRecap(now: now)
        store.fillOutcomes(nights: nights, calendar: cal)
        insights = InsightsEngine.compute(days: days, outcomes: store.outcomes(), targetWakeMinutes: settings.targetWakeMinutes, calendar: cal)

        await rescheduleNotifications(todayPlan: plan, now: now)
        publishWidgets(context: context, now: now)
        BackgroundRefreshScheduler.scheduleNext(after: now)
        lastRefresh = now
        hasLoadedOnce = true
    }

    private func loadHealthData(now: Date) async {
        let cal = calendar
        let health = self.health
        mockProvider.includesWearableData = settings.trackingMode == .wearable
        healthAuthorization = await health.authorizationState()
        let start = cal.date(byAdding: .day, value: -CircadianConfig.healthLookbackDays, to: cal.startOfDay(for: now)) ?? now
        do {
            // Phone-only users may never have connected Health, so a read error isn't fatal for them.
            let healthSleep = settings.trackingMode == .phoneOnly
                ? ((try? await health.sleepSamples(from: start, to: now)) ?? [])
                : try await health.sleepSamples(from: start, to: now)
            let logs = SleepLogMerger.unrecorded(selfReports.all().filter { $0.wake > start }, health: healthSleep)
            loggedDays = Set(logs.map(\.wakeDay))
            let sleep = healthSleep + logs.map(SleepLogMerger.sample)
            daylightSamples = settings.trackingMode == .phoneOnly
                ? ((try? await health.daylightSamples(from: start, to: now)) ?? [])
                : try await health.daylightSamples(from: start, to: now)
            canSenseLight = !daylightSamples.isEmpty
            // No sensor: use what the user reported, and only on the days they answered. With one,
            // a report tops up what the Watch saw (it misses time under a sleeve or in a pocket).
            let reports = selfReports.lightReports().filter { $0.end > start }
            let lightKnownDays: Set<Date>? = canSenseLight ? nil : Set(reports.map { cal.startOfDay(for: $0.day) })
            var secondary: [SecondaryMetric: [MetricSample]] = [:]
            for metric in SecondaryMetric.allCases {
                secondary[metric] = (try? await health.secondarySamples(metric, from: start, to: now)) ?? []
            }
            nights = SleepSessionBuilder.buildNights(from: sleep, calendar: cal)
            healthNightDays = Set(nights.map(\.wakeDay)).subtracting(loggedDays)
            let firstDay = nights.first?.wakeDay ?? cal.startOfDay(for: now)
            let settings = self.settings
            days = DayMetricsBuilder.build(nights: nights, daylight: canSenseLight ? daylightSamples : reports.map(\.sample),
                                           reportedLight: canSenseLight ? reports.map(\.sample) : [],
                                           secondary: secondary, from: max(firstDay, start), through: now,
                                           lightKnownDays: lightKnownDays,
                                           lightGoals: { settings.morningLightGoal(for: $0, calendar: cal) ?? .unknown },
                                           calendar: cal)
            todayDaylight = daylightSamples.filter { cal.isDate($0.start, inSameDayAs: now) }.sorted { $0.start < $1.start }
            snapshot = CircadianModel.snapshot(days: days, now: now, calendar: cal, weights: settings.weights,
                                               usual: settings.usualSleep)
            scoreHistory = CircadianModel.scoreHistory(days: days, now: now, calendar: cal, weights: settings.weights,
                                                       usual: settings.usualSleep)
            dataError = nil
        } catch {
            dataError = "Couldn't read Health data: \(error.localizedDescription)"
        }
    }

    /// Until the user picks targets, follow the detected baseline (rounded to 15 minutes).
    private func applyBaselineTargetsIfNeeded() {
        guard !settings.targetsAreCustom,
              let wake = snapshot.baselineWake, let onset = snapshot.baselineOnset else { return }
        settings.targetWakeMinutes = ClockMath.wrapPositive(ClockMath.rounded(wake, to: 15))
        settings.targetBedMinutes = ClockMath.wrapPositive(ClockMath.rounded(onset, to: 15))
    }

    // MARK: - Sleep log

    /// Asks about last night (and a missed night before it) in phone-only mode, or about last
    /// night when a wearable has gone quiet. Once logged, a night stays on the card to edit.
    private func updateSleepLogPrompt(now: Date) {
        let cal = calendar
        let day = activeDay
        guard settings.hasCompletedOnboarding else {
            sleepLogPrompt = nil
            missedSleepLog = nil
            sleepLogGapSince = nil
            return
        }
        let stored = Set(selfReports.all().map { cal.startOfDay(for: $0.wakeDay) })
        let asks = SleepLogPlanner.asks(mode: settings.trackingMode, activeDay: day, phoneOnlySince: settings.phoneOnlySince,
                                        healthNightDays: healthNightDays, loggedDays: stored,
                                        isSkipped: { self.settings.isSleepLogSkipped($0, calendar: cal) }, calendar: cal)
        sleepLogGapSince = asks.gapSince
        sleepLogPrompt = asks.today ? sleepLogGuess(for: day, now: now) : nil
        let yesterday = cal.date(byAdding: .day, value: -1, to: day)
        missedSleepLog = asks.yesterday ? yesterday.map { sleepLogGuess(for: $0, now: now) } : nil
    }

    private func sleepLogGuess(for wakeDay: Date, now: Date) -> SleepLogPrompt {
        SleepLogGuess.make(wakeDay: wakeDay, logged: selfReports.log(wakeDay: wakeDay, calendar: calendar), days: days,
                           usual: settings.usualSleep, targetBedMinutes: settings.targetBedMinutes,
                           targetWakeMinutes: settings.targetWakeMinutes, now: now, calendar: calendar)
    }

    /// Questions the reminder and the widget can confirm with one tap: today's if still open,
    /// and (phone-only) tomorrow's best guess so tomorrow morning works without opening the app.
    private func confirmableSleepPrompts() -> [SleepLogPrompt] {
        var prompts = [sleepLogPrompt].compactMap { $0 }.filter { !$0.isLogged }
        if settings.trackingMode == .phoneOnly, let tomorrow = calendar.date(byAdding: .day, value: 1, to: activeDay) {
            prompts.append(SleepLogGuess.make(wakeDay: tomorrow, logged: nil, days: days, usual: settings.usualSleep,
                                              targetBedMinutes: settings.targetBedMinutes,
                                              targetWakeMinutes: settings.targetWakeMinutes, now: .distantFuture,
                                              calendar: calendar))
        }
        return prompts
    }

    /// "Looks right" from the reminder or the widget. Never overwrites a night already logged.
    private func confirmSleepLog(_ log: SleepLog) {
        guard selfReports.log(wakeDay: log.wakeDay, calendar: calendar) == nil else { return }
        selfReports.save(log, at: Date(), calendar: calendar)
        requestRefresh()
    }

    /// Sleep-log questions confirmed from the Focus widget since the last refresh.
    private func applyWidgetSleepLogs() {
        let confirmed = WidgetShared.loadCompletions().filter { $0.kind == SleepLogPrompt.kind }
        guard !confirmed.isEmpty else { return }
        for completion in confirmed {
            guard let onset = completion.sleepOnset, let wake = completion.sleepWake else { continue }
            let log = SleepLog(wakeDay: calendar.startOfDay(for: wake), onset: onset, wake: wake)
            if selfReports.log(wakeDay: log.wakeDay, calendar: calendar) == nil {
                selfReports.save(log, at: completion.completedAt, calendar: calendar)
            }
        }
        WidgetShared.removeCompletions(ids: Set(confirmed.map(\.id)))
    }

    func logSleep(_ log: SleepLog) {
        selfReports.save(log, at: Date(), calendar: calendar)
        let logged = SleepLogPrompt(wakeDay: log.wakeDay, onset: log.onset, wake: log.wake, isLogged: true)
        if missedSleepLog.map({ calendar.isDate($0.wakeDay, inSameDayAs: log.wakeDay) }) == true {
            missedSleepLog = nil
        } else {
            sleepLogPrompt = logged
        }
        requestRefresh()
    }

    func deleteSleepLog(wakeDay: Date) {
        selfReports.delete(wakeDay: wakeDay, calendar: calendar)
        requestRefresh()
    }

    /// "Not sure": stop asking about this night.
    func skipSleepLog(wakeDay: Date) {
        settings.skipSleepLog(wakeDay, calendar: calendar)
        if sleepLogPrompt.map({ calendar.isDate($0.wakeDay, inSameDayAs: wakeDay) }) == true { sleepLogPrompt = nil }
        if missedSleepLog.map({ calendar.isDate($0.wakeDay, inSameDayAs: wakeDay) }) == true { missedSleepLog = nil }
        requestRefresh()
    }

    func setTrackingMode(_ mode: TrackingMode) {
        guard settings.trackingMode != mode else { return }
        settings.trackingMode = mode
        settings.phoneOnlySince = mode == .phoneOnly ? Date() : nil
        requestRefresh()
    }

    // MARK: - Self-reported light

    /// A light card checked off: record the time outside so the score can use it.
    /// `minutes` nil means the card's suggested amount (widget and notification check-offs).
    /// With a Watch too: the report tops up what the Watch saw, never lowers it.
    private func reportDoneLight(recommendationID: String, kind: RecommendationKind?, minutes: Double?, at date: Date) {
        guard kind?.isLightKind == true else { return }
        let record = store.record(id: recommendationID)
        guard let minutes = minutes ?? record?.requiredMinutes else { return }
        let day = ClockMath.activeDay(for: date, calendar: calendar)
        let window = record.flatMap { r in
            r.windowStart.flatMap { start in r.windowEnd.map { DateInterval(start: start, end: max(start, $0)) } }
        }
        selfReports.saveLight(.done(day: day, minutes: minutes, at: date, window: window),
                              id: ReportedLight.doneID(recommendationID), at: date)
    }

    /// Whether the most recent night in the score came from the sleep log.
    var latestNightIsLogged: Bool {
        guard let night = snapshot.latestNight else { return false }
        return loggedDays.contains(night.wakeDay) || (settings.useMockData && settings.trackingMode == .phoneOnly)
    }

    private func loadSunWeather(now: Date) async {
        let coordinate = location.coordinate
        let estimated = coordinate == nil
        let coord = coordinate ?? LocationService.estimatedCoordinate(for: .current, at: now)
        var result: SunWeatherSnapshot
        do {
            result = try await sunWeatherService.snapshot(for: coord, date: now, timeZone: .current, locationIsEstimated: estimated)
        } catch {
            result = LocalSolarProvider().makeSnapshot(for: coord, date: now, timeZone: .current, locationIsEstimated: estimated)
        }
        if settings.useMockData { result = DemoWeather.decorate(result, date: now) }
        sunWeather = result
        weatherError = await (sunWeatherService as? FallbackSunWeatherService)?.lastPrimaryError
    }

    // MARK: - Morning light goal

    /// Sets today's and tomorrow's light goal from the forecast cloud cover over the morning window.
    /// A day's goal is fixed once that morning starts, so the wake notification, the card and the
    /// score agree. A known sky is never replaced by an unknown one.
    private func updateMorningLightGoals(now: Date) {
        let cal = calendar
        let today = activeDay
        for day in [today, cal.date(byAdding: .day, value: 1, to: today)].compactMap({ $0 }) {
            let stored = settings.morningLightGoal(for: day, calendar: cal)
            let wake = nights.first { cal.isDate($0.wakeDay, inSameDayAs: day) }?.primary.wake
                ?? ClockMath.date(on: day, minutes: settings.targetWakeMinutes, calendar: cal)
            if stored != nil && now >= wake { continue }
            var start = wake
            if let sunrise = sunTimes(for: day, now: now)?.sunrise, sunrise > start {
                start = sunrise
            }
            let window = DateInterval(start: start, end: max(start, wake.adding(minutes: CircadianConfig.morningLightWindowMinutes)))
            let sky = MorningLightGoal.sky(over: window, weather: sunWeather?.weather, now: now)
            if sky == .unknown, stored != nil { continue }
            settings.setMorningLightGoal(MorningLightGoal(sky: sky), for: day, calendar: cal)
        }
    }

    /// Sun times for `day`. The loaded ones are for the calendar date of `now`, which before the
    /// rollover hour is the day after `activeDay`.
    private func sunTimes(for day: Date, now: Date) -> SunTimes? {
        guard let sun = sunWeather?.sun else { return nil }
        let cal = calendar
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: day)).day ?? 0
        return sun.shifted(byDays: days)
    }

    private func updateTravel(now: Date) {
        let current = TimeZone.current
        guard let homeID = settings.homeTimeZoneID, let home = TimeZone(identifier: homeID) else {
            settings.homeTimeZoneID = current.identifier
            settings.homeLongitude = location.coordinate?.longitude
            return
        }
        if settings.homeLongitude == nil { settings.homeLongitude = location.coordinate?.longitude }
        var state = TravelDetector.evaluate(homeTimeZone: home, homeLongitude: settings.homeLongitude,
                                            currentTimeZone: current, currentLongitude: location.coordinate?.longitude,
                                            now: now, existing: settings.travelState)
        // Plan finished: treat the new place as home.
        if let s = state, s.remainingHours(on: activeDay, calendar: calendar) <= 0 {
            state = nil
            settings.homeTimeZoneID = current.identifier
            settings.homeLongitude = location.coordinate?.longitude
        }
        if state != settings.travelState { settings.travelState = state }
    }

    func makeContext(now: Date, day: Date) -> CircadianContext {
        let cal = calendar
        let metrics = days.first { cal.isDate($0.day, inSameDayAs: day) }
        let wake = metrics?.night?.primary.wake
        // With a sensor, the day's light includes anything the user reported on top.
        let light = if canSenseLight, let metrics { metrics.light }
            else { DaylightAnalyzer.summary(samples: daylightSamples, day: day, wake: wake, calendar: cal) }
        let todayDrift = (metrics?.night != nil) ? snapshot.drift : nil
        return CircadianContext(
            now: now, calendar: cal, wakeToday: wake,
            targetWakeMinutes: settings.targetWakeMinutes, targetBedMinutes: settings.targetBedMinutes,
            baselineMidpointMinutes: snapshot.baselineMidpoint,
            light: light, hasDaylightData: canSenseLight, sunWeather: sunWeather,
            morningGoal: settings.morningLightGoal(for: day, calendar: cal),
            travel: settings.travelState, socialJetlagMinutes: snapshot.socialJetlag,
            todayDriftMinutes: todayDrift, alignmentScore: snapshot.score?.value, streakDays: snapshot.streakDays,
            caffeineCutoffHours: settings.caffeineCutoffHours,
            completedKinds: store.resolvedKinds(on: day),
            habits: settings.habitStatuses)
    }

    // MARK: - Forecast and morning recap

    private func updateForecastAndRecap(now: Date) {
        let cal = calendar
        forecast = ScoreForecaster.make(days: days, now: now, targetBedMinutes: settings.targetBedMinutes,
                                        targetWakeMinutes: settings.targetWakeMinutes, calendar: cal, weights: settings.weights,
                                        usual: settings.usualSleep)
        recap = ScoreRecapBuilder.make(snapshot: snapshot, history: scoreHistory, now: now, calendar: cal, weights: settings.weights)
        // Opens by itself on the first visit after last night's sleep is in.
        if let recap, settings.hasCompletedOnboarding, payoff == nil,
           settings.lastRecapDay.map({ !cal.isDate($0, inSameDayAs: recap.day) }) ?? true {
            settings.lastRecapDay = recap.day
            showRecap = true
        }
    }

    func presentRecap() {
        guard recap != nil else { return }
        showRecap = true
    }

    // MARK: - Habit check-in

    /// Card-backed habits whose card already records the answer.
    private static let checkInCardKinds: [HabitKey: RecommendationKind] = [
        .eveningDim: .windDown, .caffeineCutoff: .caffeineCutoff, .morningLight: .morningLight,
    ]

    private func updateCheckIn(context: CircadianContext) {
        let cal = calendar
        guard let day = HabitCatalog.checkInDay(now: context.now, activeDay: context.activeDay, wakeToday: context.wakeToday,
                                                timing: settings.timing, habitsChosenAt: settings.habitsChosenAt, calendar: cal) else {
            checkIn = []
            checkInDay = nil
            return
        }
        let answers = Dictionary(store.checkIns(on: day).compactMap { c in c.habit.map { ($0, c.followed) } },
                                 uniquingKeysWith: { a, _ in a })
        let records = store.records(on: day)
        checkIn = HabitCatalog.checkInHabits(for: settings.habitStatuses, timing: settings.timing,
                                             canSenseLight: canSenseLight).compactMap { habit in
            if let answer = answers[habit] {
                // Skipped questions go away; answered ones stay with their answer.
                return answer.map { CheckInItem(habit: habit, followed: $0) }
            }
            // Already answered on the card itself.
            if let kind = Self.checkInCardKinds[habit], let record = records.first(where: { $0.kind == kind }) {
                if record.status == .skipped { return nil }
                if record.status == .followed { return CheckInItem(habit: habit, followed: true) }
            }
            return CheckInItem(habit: habit, followed: nil)
        }
        if checkIn.allSatisfy({ $0.followed == true }) && checkIn.allSatisfy({ answers[$0.habit] == nil }) {
            // Everything was confirmed by the cards; nothing to ask.
            checkIn = []
        }
        checkInDay = day
    }

    /// Records a check-in answer (nil = skipped) and updates the matching card's record.
    func answerCheckIn(_ habit: HabitKey, followed: Bool?) {
        guard let day = checkInDay else { return }
        let cal = calendar
        let now = Date()
        store.recordCheckIn(habit: habit, day: day, followed: followed, at: now, calendar: cal)
        if let followed, let kind = Self.checkInCardKinds[habit] {
            let id = RecommendationEngine.id(kind, day: day, calendar: cal)
            if let record = store.record(id: id), record.status != .skipped,
               !(habit == .eveningDim && record.criteriaRaw != "lightsDimmed") {
                store.mark(id: id, status: followed ? .followed : .expired, detection: .manual, at: now)
            }
        }
        if habit == .morningLight, !canSenseLight, let followed {
            reportCheckInLight(day: day, followed: followed, at: now)
        }
        if let followed, let index = checkIn.firstIndex(where: { $0.habit == habit }) {
            checkIn[index].followed = followed
        } else {
            checkIn.removeAll { $0.habit == habit }
        }
    }

    /// "Got outside within 2 h of waking": yes records the morning target, no records a known zero.
    /// A Done on the card already counts, so a yes adds nothing then; a no withdraws it.
    private func reportCheckInLight(day: Date, followed: Bool, at date: Date) {
        let cal = calendar
        let id = ReportedLight.checkInID(day: day, calendar: cal)
        let cardID = ReportedLight.doneID(RecommendationEngine.id(.morningLight, day: day, calendar: cal))
        if followed && selfReports.lightReport(id: cardID) != nil {
            selfReports.deleteLight(id: id)
            return
        }
        if !followed { selfReports.deleteLight(id: cardID) }
        let wake = nights.first { cal.isDate($0.wakeDay, inSameDayAs: day) }?.primary.wake
            ?? ClockMath.date(on: day, minutes: settings.targetWakeMinutes, calendar: cal)
        let goal = settings.morningLightGoal(for: day, calendar: cal) ?? .unknown
        selfReports.saveLight(followed ? .checkInYes(day: day, wake: wake, minutes: goal.minutes) : .none(day: day, at: date),
                              id: id, at: date)
    }

    /// Skips the questions not yet answered.
    func skipCheckIn() {
        for item in checkIn where item.followed == nil { answerCheckIn(item.habit, followed: nil) }
    }

    // MARK: - Habit choices

    func setHabit(_ habit: HabitKey, _ status: HabitStatus?) {
        settings.habitStatuses[habit] = status
        if settings.habitsChosenAt == nil { settings.habitsChosenAt = Date() }
    }

    // MARK: - Notifications

    private func rescheduleNotifications(todayPlan: [Recommendation], now: Date) async {
        notificationsAuthorized = await notifications.isAuthorized()
        guard notificationsAuthorized else { return }
        let cal = calendar
        // Tomorrow's plan, so the morning nudge exists even if the app isn't opened overnight.
        let tomorrowPlan = tomorrowContext(now: now).map { RecommendationEngine.dailyPlan(for: $0) } ?? []
        let preferences = NotificationPreferences(enabledKinds: settings.enabledNudgeKinds.intersection(HabitCatalog.nudgeKinds(for: settings.habitStatuses)),
                                                  quietStartMinutes: settings.quietStartMinutes,
                                                  quietEndMinutes: settings.quietEndMinutes)
        let reminders = settings.trackingMode == .phoneOnly && settings.sleepLogReminderEnabled
            ? SleepLogReminderPlanner.plan(confirmableSleepPrompts(), now: now, preferences: preferences, calendar: cal) : []
        let reserved = Dictionary(grouping: reminders) { cal.startOfDay(for: $0.fireDate) }.mapValues(\.count)
        let plan = NotificationPlanner.plan(recommendations: todayPlan + tomorrowPlan, now: now, calendar: cal,
                                            preferences: preferences, consecutiveDismissals: settings.consecutiveDismissals,
                                            reservedPerDay: reserved)
        await notifications.schedule(plan.nudges, sleepReminders: reminders, calendar: cal)
        scheduledNudgeCount = plan.nudges.count + reminders.count
    }

    /// Tomorrow as it will look first thing: no wake, outdoor light or completions recorded yet.
    private func tomorrowContext(now: Date) -> CircadianContext? {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: activeDay) else { return nil }
        var ctx = makeContext(now: now, day: tomorrow)
        ctx.now = tomorrow.addingTimeInterval(Double(CircadianConfig.dayRolloverHour) * 3600)
        ctx.wakeToday = nil
        ctx.light = .empty
        ctx.completedKinds = []
        ctx.todayDriftMinutes = nil
        if let sw = sunWeather, let sun = sunTimes(for: tomorrow, now: now) {
            ctx.sunWeather = SunWeatherSnapshot(sun: sun, weather: nil, source: sw.source, locationIsEstimated: sw.locationIsEstimated)
        }
        return ctx
    }

    func requestNotificationPermission() async {
        _ = await notifications.requestAuthorization()
        notificationsAuthorized = await notifications.isAuthorized()
        requestRefresh()
    }

    func refreshNotificationStatus() async {
        notificationsAuthorized = await notifications.isAuthorized()
    }

    // MARK: - Widgets

    /// Re-publishes from current state without a full refresh (e.g. settings changed, then the app
    /// went to the background).
    func publishWidgets() {
        guard hasLoadedOnce else { return }
        let now = Date()
        publishWidgets(context: makeContext(now: now, day: activeDay), now: now)
    }

    /// Hands today's and tomorrow's plan to the widgets. Only reloads them when something changed.
    private func publishWidgets(context: CircadianContext, now: Date) {
        let contexts = [context] + [tomorrowContext(now: now)].compactMap { $0 }
        WidgetBridge.publish(WidgetSnapshotBuilder.make(snapshot: snapshot, contexts: contexts, now: now,
                                                        sleepPrompts: confirmableSleepPrompts()))
    }

    /// Records recommendations checked off from the Focus widget since the last refresh.
    /// - Returns: whether any were applied.
    private func applyWidgetCompletions(context: CircadianContext, now: Date) -> Bool {
        let pending = WidgetShared.loadCompletions()
        guard !pending.isEmpty else { return false }
        var applied = false
        for completion in pending {
            // The card may never have been stored if its window closed before the app ran.
            if store.record(id: completion.id) == nil,
               let rec = RecommendationEngine.candidates(for: context).first(where: { $0.id == completion.id }) {
                store.sync([rec], day: context.activeDay, daylight: daylightSamples, hasDaylightData: canSenseLight, now: now)
            }
            guard let record = store.record(id: completion.id),
                  record.status != .followed, record.status != .skipped else { continue }
            store.mark(id: completion.id, status: .followed, detection: .manual, at: completion.completedAt)
            reportDoneLight(recommendationID: completion.id, kind: record.kind, minutes: nil, at: completion.completedAt)
            if let kind = record.kind { settings.resetDismissals(kind) }
            applied = true
        }
        WidgetShared.removeCompletions(ids: Set(pending.map(\.id)))
        return applied
    }

    // MARK: - User actions

    /// - Parameter minutes: for a light card without a sensor, how long the user says they were out.
    func markDone(_ rec: Recommendation, minutes: Double? = nil) {
        let now = Date()
        store.sync([rec], day: activeDay, daylight: daylightSamples, hasDaylightData: canSenseLight, now: now)
        store.mark(id: rec.id, status: .followed, detection: .manual, at: now)
        reportDoneLight(recommendationID: rec.id, kind: rec.kind, minutes: minutes, at: now)
        settings.resetDismissals(rec.kind)
        if rec.kind.isLightKind {
            payoff = PayoffEvent(kind: rec.kind, completedAt: now, detectedAutomatically: false)
        }
        recommendations.removeAll { $0.id == rec.id }
        completedToday.append(CompletedRecommendation(id: rec.id, kind: rec.kind, completedAt: now, detectedAutomatically: false))
        requestRefresh()
    }

    /// Un-checks a recommendation marked done by mistake.
    func undoDone(_ item: CompletedRecommendation) {
        store.reopen(id: item.id)
        selfReports.deleteLight(id: ReportedLight.doneID(item.id))
        completedToday.removeAll { $0.id == item.id }
        requestRefresh()
    }

    func skip(_ rec: Recommendation) {
        let now = Date()
        store.sync([rec], day: activeDay, daylight: daylightSamples, hasDaylightData: canSenseLight, now: now)
        store.mark(id: rec.id, status: .skipped, detection: .manual, at: now)
        recommendations.removeAll { $0.id == rec.id }
        requestRefresh()
    }

    func connectHealth() async {
        do {
            try await healthKitProvider.requestAuthorization()
        } catch {
            dataError = "Health authorization failed: \(error.localizedDescription)"
        }
        await refresh()
    }

    func requestLocation() async {
        await location.requestPermission()
        await refresh()
    }

    func setMockData(_ enabled: Bool) {
        settings.useMockData = enabled
        requestRefresh()
    }

    func markTravelAdapted() {
        settings.travelState = nil
        settings.homeTimeZoneID = TimeZone.current.identifier
        settings.homeLongitude = location.coordinate?.longitude
        requestRefresh()
    }

    func simulateTravel(hours: Double?) {
        settings.travelState = hours.map { TravelState(shiftHours: $0, detectedAt: Date(), isSimulated: true) }
        requestRefresh()
    }

    func deleteAllData() async {
        store.deleteAll()
        selfReports.deleteAll()
        await notifications.cancelAll()
        location.clearCache()
        settings.resetAll()
        days = []
        nights = []
        recommendations = []
        snapshot = .empty
        scoreHistory = []
        insights = .empty
        checkIn = []
        checkInDay = nil
        completedToday = []
        forecast = nil
        recap = nil
        sleepLogPrompt = nil
        missedSleepLog = nil
        sleepLogGapSince = nil
        loggedDays = []
        healthNightDays = []
        canSenseLight = false
        scheduledNudgeCount = 0
        WidgetBridge.publish(.empty)
    }
}
