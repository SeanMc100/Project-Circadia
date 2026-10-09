import Foundation

/// Turns the model's state into the widgets' snapshot. Pure, so it's unit-testable.
///
/// The Focus widget's whole day is computed up front: the engine is evaluated at every moment its
/// output could change, and each change becomes a timeline entry. WidgetKit then swaps entries on
/// schedule without waking the widget or the app.
enum WidgetSnapshotBuilder {
    /// Recommendations kept per entry; extras let the widget show the next one after a check-off.
    static let maxItems = 3
    /// Sampling step between the engine's own boundaries (catches urgency changes such as "soon").
    static let gridMinutes = 15.0

    /// - Parameter sleepPrompts: unlogged "When did you sleep?" questions (phone-only mode). Each
    ///   leads the Focus widget on its wake day, from shortly before the guessed wake until the
    ///   check-in closes, so it can be confirmed with one tap.
    static func make(snapshot: CircadianSnapshot, contexts: [CircadianContext], now: Date,
                     sleepPrompts: [SleepLogPrompt] = []) -> WidgetSnapshot {
        var focus: [WidgetSnapshot.FocusEntry] = []
        for context in contexts {
            let prompt = sleepPrompts.first { !$0.isLogged && context.calendar.isDate($0.wakeDay, inSameDayAs: context.activeDay) }
            for entry in focusEntries(for: context, sleepPrompt: prompt) where entry.items != focus.last?.items {
                focus.append(entry)
            }
        }
        return WidgetSnapshot(
            generatedAt: now,
            alignment: snapshot.score.map(alignment),
            statusText: statusText(snapshot),
            focus: focus,
            validUntil: contexts.last.map { dayRange($0).end } ?? now)
    }

    /// The active day as a wall-clock range: rollover hour to rollover hour.
    static func dayRange(_ ctx: CircadianContext) -> DateInterval {
        let cal = ctx.calendar
        let start = cal.date(byAdding: .hour, value: CircadianConfig.dayRolloverHour, to: ctx.activeDay) ?? ctx.activeDay
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    /// One entry per change in what's on screen during `ctx`'s active day.
    static func focusEntries(for ctx: CircadianContext, sleepPrompt: SleepLogPrompt? = nil) -> [WidgetSnapshot.FocusEntry] {
        let range = dayRange(ctx)
        var times = Set<Date>()
        let sleepWindow = sleepPrompt.map { prompt -> DateInterval in
            let start = max(range.start, prompt.wake.adding(minutes: -CircadianConfig.sleepLogWidgetLeadMinutes))
            let closes = ClockMath.date(on: ctx.activeDay, minutes: Double(CircadianConfig.checkInVisibleUntilHour * 60), calendar: ctx.calendar)
            return DateInterval(start: start, end: max(start, closes))
        }
        if let sleepWindow {
            times.insert(sleepWindow.start)
            if sleepWindow.end < range.end { times.insert(sleepWindow.end) }
        }
        var t = range.start
        while t < range.end {
            times.insert(t)
            t = t.adding(minutes: gridMinutes)
        }
        var probe = ctx
        probe.now = range.start
        for rec in RecommendationEngine.candidates(for: probe) {
            let boundaries = [rec.visibleFrom, rec.window?.start, rec.window?.end, rec.nudgeDate,
                              rec.trackingWindow?.start, rec.trackingWindow?.end]
            for date in boundaries.compactMap({ $0 }) where date >= range.start && date < range.end {
                times.insert(date)
            }
        }

        var entries: [WidgetSnapshot.FocusEntry] = []
        for time in times.sorted() {
            var c = ctx
            c.now = time
            var items = RecommendationEngine.recommendations(for: c).prefix(maxItems).map(item)
            if let sleepPrompt, let sleepWindow, time >= sleepWindow.start, time < sleepWindow.end {
                items = Array(([sleepItem(sleepPrompt, calendar: ctx.calendar)] + items).prefix(maxItems))
            }
            if entries.last?.items != items {
                entries.append(.init(start: time, items: items))
            }
        }
        return entries
    }

    static func item(_ rec: Recommendation) -> WidgetSnapshot.FocusItem {
        WidgetSnapshot.FocusItem(
            id: rec.id, kind: rec.kind.rawValue, label: rec.kind.title, title: rec.title,
            detail: detail(rec), systemImage: rec.kind.systemImage, isLight: rec.kind.isLightKind,
            canComplete: rec.kind != .maintenance)
    }

    static func sleepItem(_ prompt: SleepLogPrompt, calendar: Calendar) -> WidgetSnapshot.FocusItem {
        WidgetSnapshot.FocusItem(
            id: prompt.id(calendar: calendar), kind: SleepLogPrompt.kind, label: "Last night",
            title: "Asleep \(ClockMath.timeString(prompt.onset)), up \(ClockMath.timeString(prompt.wake))?",
            detail: "Tap ✓ if that's about right", systemImage: "bed.double.fill", isLight: false,
            canComplete: true, sleepOnset: prompt.onset, sleepWake: prompt.wake)
    }

    /// A short second line; the full explanation stays in the app.
    private static func detail(_ rec: Recommendation) -> String? {
        switch rec.kind {
        case .morningLight, .lateDayLight:
            rec.trackingWindow.map { "Until \(ClockMath.timeString($0.end))" }
        case .windDown:
            rec.window.map { "Bedtime \(ClockMath.timeString($0.end))" }
        case .anchorWake:
            rec.window.map { "Up by \(ClockMath.timeString($0.end)) tomorrow" }
        case .travelShift:
            rec.body
        case .maintenance:
            "Keep your wake time and morning light steady"
        case .caffeineCutoff:
            nil
        }
    }

    private static func alignment(_ score: AlignmentScore) -> WidgetSnapshot.Alignment {
        WidgetSnapshot.Alignment(
            value: score.value, band: score.bandTitle,
            components: score.components.map { .init(kind: $0.kind.rawValue, title: $0.kind.title, value: $0.value) })
    }

    private static func statusText(_ snapshot: CircadianSnapshot) -> String? {
        switch snapshot.status {
        case .noData: "Waiting for sleep data"
        case .calibrating(let have, let need): "Calibrating · \(have) of \(need) nights"
        case .provisional: nil
        case .ready: snapshot.score == nil ? "Needs a few more nights" : nil
        }
    }
}
