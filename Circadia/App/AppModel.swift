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
    @ObservationIgnored private let healthKitProvider: HealthKitProvider
    @ObservationIgnored private let mockProvider: MockHealthDataProvider
    @ObservationIgnored private let sunWeatherService: SunWeatherService
    @ObservationIgnored private var daylightSamples: [DaylightSample] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    // MARK: Published state

    private(set) var isRefreshing = false
    private(set) var hasLoadedOnce = false
    private(set) var days: [DayMetrics] = []
    private(set) var nights: [NightRecord] = []
    private(set) var todayDaylight: [DaylightSample] = []
    private(set) var snapshot: CircadianSnapshot = .empty
    private(set) var sunWeather: SunWeatherSnapshot?
    private(set) var recommendations: [Recommendation] = []
    private(set) var insights: InsightsResult = .empty
    private(set) var lastRefresh: Date?
    private(set) var dataError: String?
    private(set) var healthAuthorization: HealthAuthorizationState = .notRequested
    private(set) var notificationsAuthorized = false
    private(set) var scheduledNudgeCount = 0
    var payoff: PayoffEvent?

    var calendar: Calendar { .current }

    var health: HealthDataProviding {
        settings.useMockData ? mockProvider : healthKitProvider
    }

    var hasDaylightData: Bool { days.contains(where: \.hasLightData) }

    var activeDay: Date {
        calendar.startOfDay(for: Date().addingTimeInterval(-Double(CircadianConfig.dayRolloverHour) * 3600))
    }

    init(settings: AppSettings, modelContext: ModelContext, location: LocationService? = nil,
         notifications: NotificationService? = nil,
         sunWeatherService: SunWeatherService = FallbackSunWeatherService(primary: WeatherKitProvider())) {
        self.settings = settings
        self.location = location ?? LocationService()
        self.notifications = notifications ?? NotificationService()
        self.store = RecommendationStore(context: modelContext)
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
            if let id { self.store.mark(id: id, status: .followed, detection: .manual, at: Date()) }
            if kind.isLightKind { self.payoff = PayoffEvent(kind: kind, completedAt: Date(), detectedAutomatically: false) }
            self.requestRefresh()
        }
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

    /// Coalesces refresh requests.
    func requestRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            await self?.refresh()
            self?.refreshTask = nil
        }
    }

    /// Full pipeline: health → nights/days → model → sun/weather → travel → recommendations →
    /// persistence → insights → notifications.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let now = Date()
        let cal = calendar

        await loadHealthData(now: now)
        applyBaselineTargetsIfNeeded()
        await loadSunWeather(now: now)
        updateTravel(now: now)

        let day = activeDay
        var context = makeContext(now: now, day: day)
        var plan = RecommendationEngine.dailyPlan(for: context)
        let newlyFollowed = store.sync(plan, day: day, daylight: daylightSamples, hasDaylightData: hasDaylightData, now: now)
        if let light = newlyFollowed.first(where: { $0.kind?.isLightKind == true }), let kind = light.kind {
            payoff = PayoffEvent(kind: kind, completedAt: light.completedAt ?? now, detectedAutomatically: true)
            context.completedKinds = store.resolvedKinds(on: day)
            plan = RecommendationEngine.dailyPlan(for: context)
        }
        recommendations = RecommendationEngine.recommendations(for: context)
        store.fillOutcomes(nights: nights, calendar: cal)
        insights = InsightsEngine.compute(days: days, outcomes: store.outcomes(), targetWakeMinutes: settings.targetWakeMinutes, calendar: cal)

        await rescheduleNotifications(todayPlan: plan, now: now)
        BackgroundRefreshScheduler.scheduleNext(after: now)
        lastRefresh = now
        hasLoadedOnce = true
    }

    private func loadHealthData(now: Date) async {
        let cal = calendar
        let health = self.health
        healthAuthorization = await health.authorizationState()
        let start = cal.date(byAdding: .day, value: -CircadianConfig.healthLookbackDays, to: cal.startOfDay(for: now)) ?? now
        do {
            let sleep = try await health.sleepSamples(from: start, to: now)
            daylightSamples = try await health.daylightSamples(from: start, to: now)
            var secondary: [SecondaryMetric: [MetricSample]] = [:]
            for metric in SecondaryMetric.allCases {
                secondary[metric] = (try? await health.secondarySamples(metric, from: start, to: now)) ?? []
            }
            nights = SleepSessionBuilder.buildNights(from: sleep, calendar: cal)
            let firstDay = nights.first?.wakeDay ?? cal.startOfDay(for: now)
            days = DayMetricsBuilder.build(nights: nights, daylight: daylightSamples, secondary: secondary,
                                           from: max(firstDay, start), through: now, calendar: cal)
            todayDaylight = daylightSamples.filter { cal.isDate($0.start, inSameDayAs: now) }.sorted { $0.start < $1.start }
            snapshot = CircadianModel.snapshot(days: days, now: now, calendar: cal, weights: settings.weights)
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
        let light = DaylightAnalyzer.summary(samples: daylightSamples, day: day, wake: wake, calendar: cal)
        let todayDrift = (metrics?.night != nil) ? snapshot.drift : nil
        return CircadianContext(
            now: now, calendar: cal, wakeToday: wake,
            targetWakeMinutes: settings.targetWakeMinutes, targetBedMinutes: settings.targetBedMinutes,
            baselineMidpointMinutes: snapshot.baselineMidpoint,
            light: light, hasDaylightData: hasDaylightData, sunWeather: sunWeather,
            travel: settings.travelState, socialJetlagMinutes: snapshot.socialJetlag,
            todayDriftMinutes: todayDrift, alignmentScore: snapshot.score?.value, streakDays: snapshot.streakDays,
            caffeineCutoffHours: settings.caffeineCutoffHours,
            completedKinds: store.resolvedKinds(on: day))
    }

    // MARK: - Notifications

    private func rescheduleNotifications(todayPlan: [Recommendation], now: Date) async {
        notificationsAuthorized = await notifications.isAuthorized()
        guard notificationsAuthorized else { return }
        let cal = calendar
        // Tomorrow's plan, so the morning nudge exists even if the app isn't opened overnight.
        var tomorrowPlan: [Recommendation] = []
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: activeDay) {
            var ctx = makeContext(now: now, day: tomorrow)
            ctx.now = tomorrow.addingTimeInterval(Double(CircadianConfig.dayRolloverHour) * 3600)
            ctx.wakeToday = nil
            ctx.light = .empty
            ctx.completedKinds = []
            ctx.todayDriftMinutes = nil
            if let sw = sunWeather {
                ctx.sunWeather = SunWeatherSnapshot(sun: sw.sun.shifted(byDays: 1), weather: nil, source: sw.source, locationIsEstimated: sw.locationIsEstimated)
            }
            tomorrowPlan = RecommendationEngine.dailyPlan(for: ctx)
        }
        let preferences = NotificationPreferences(enabledKinds: settings.enabledNudgeKinds,
                                                  quietStartMinutes: settings.quietStartMinutes,
                                                  quietEndMinutes: settings.quietEndMinutes)
        let plan = NotificationPlanner.plan(recommendations: todayPlan + tomorrowPlan, now: now, calendar: cal,
                                            preferences: preferences, consecutiveDismissals: settings.consecutiveDismissals)
        await notifications.schedule(plan.nudges, calendar: cal)
        scheduledNudgeCount = plan.nudges.count
    }

    func requestNotificationPermission() async {
        _ = await notifications.requestAuthorization()
        notificationsAuthorized = await notifications.isAuthorized()
        requestRefresh()
    }

    func refreshNotificationStatus() async {
        notificationsAuthorized = await notifications.isAuthorized()
    }

    // MARK: - User actions

    func markDone(_ rec: Recommendation) {
        let now = Date()
        store.sync([rec], day: activeDay, daylight: daylightSamples, hasDaylightData: hasDaylightData, now: now)
        store.mark(id: rec.id, status: .followed, detection: .manual, at: now)
        settings.resetDismissals(rec.kind)
        if rec.kind.isLightKind {
            payoff = PayoffEvent(kind: rec.kind, completedAt: now, detectedAutomatically: false)
        }
        recommendations.removeAll { $0.id == rec.id }
        requestRefresh()
    }

    func skip(_ rec: Recommendation) {
        let now = Date()
        store.sync([rec], day: activeDay, daylight: daylightSamples, hasDaylightData: hasDaylightData, now: now)
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
        await notifications.cancelAll()
        location.clearCache()
        settings.resetAll()
        days = []
        nights = []
        recommendations = []
        snapshot = .empty
        insights = .empty
        scheduledNudgeCount = 0
    }
}
