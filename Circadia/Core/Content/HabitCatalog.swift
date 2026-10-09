import Foundation

enum HabitTier: Int, CaseIterable, Identifiable, Comparable, Sendable {
    case core, supportive, niche

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .core: "Core"
        case .supportive: "Supportive"
        case .niche: "Extras"
        }
    }

    var subtitle: String {
        switch self {
        case .core: "Strongest evidence and the biggest effect on your body clock."
        case .supportive: "Good evidence, smaller or more indirect effect."
        case .niche: "Helpful for some people."
        }
    }

    static func < (lhs: HabitTier, rhs: HabitTier) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum HabitStatus: String, Codable, CaseIterable, Sendable {
    /// Already part of the routine: cards still show, but no nudges or check-in questions.
    case alreadyDo
    /// Active focus: cards, nudges and the morning check-in.
    case wantToStart
    /// Hidden.
    case notForMe

    var label: String {
        switch self {
        case .alreadyDo: "I do this"
        case .wantToStart: "Start"
        case .notForMe: "Skip"
        }
    }

    var isActive: Bool { self != .notForMe }
}

/// The user's clock targets, used to personalise every habit's times.
struct HabitTiming: Equatable, Sendable {
    var wakeMinutes: Double
    var bedMinutes: Double
    var caffeineCutoffHours: Double = CircadianConfig.defaultCaffeineCutoffHours

    func beforeBed(_ minutes: Double) -> String { ClockMath.clockString(bedMinutes - minutes) }
    func afterWake(_ minutes: Double) -> String { ClockMath.clockString(wakeMinutes + minutes) }
    var wake: String { ClockMath.clockString(wakeMinutes) }
    var bed: String { ClockMath.clockString(bedMinutes) }
    var caffeineCutoff: String { beforeBed(caffeineCutoffHours * 60) }
    var dimFrom: String { beforeBed(CircadianConfig.windDownLeadMinutes) }
}

enum HabitKey: String, CaseIterable, Identifiable, Codable, Sendable {
    case consistentWake, morningLight, eveningDim, caffeineCutoff, darkBedroom
    case daytimeLight, sleepOpportunity, alcoholCutoff, screensDown, lastMeal, napTiming, exerciseTiming
    case coolBedroom

    var id: String { rawValue }

    var tier: HabitTier {
        switch self {
        case .consistentWake, .morningLight, .eveningDim, .caffeineCutoff, .darkBedroom: .core
        case .daytimeLight, .sleepOpportunity, .alcoholCutoff, .screensDown, .lastMeal, .napTiming, .exerciseTiming: .supportive
        case .coolBedroom: .niche
        }
    }

    var title: String {
        switch self {
        case .consistentWake: "Consistent wake time"
        case .morningLight: "Morning outdoor light"
        case .eveningDim: "Dim, warm evening light"
        case .caffeineCutoff: "Caffeine cutoff"
        case .darkBedroom: "Dark bedroom"
        case .daytimeLight: "Bright daytime light"
        case .sleepOpportunity: "Enough time in bed"
        case .alcoholCutoff: "No alcohol close to bed"
        case .screensDown: "Screens down before bed"
        case .lastMeal: "Earlier last meal"
        case .napTiming: "Short, early naps"
        case .exerciseTiming: "Hard workouts earlier"
        case .coolBedroom: "Cool bedroom"
        }
    }

    var systemImage: String {
        switch self {
        case .consistentWake: "alarm.fill"
        case .morningLight: "sunrise.fill"
        case .eveningDim: "lamp.desk.fill"
        case .caffeineCutoff: "cup.and.saucer.fill"
        case .darkBedroom: "moon.zzz.fill"
        case .daytimeLight: "sun.max.fill"
        case .sleepOpportunity: "bed.double.fill"
        case .alcoholCutoff: "wineglass.fill"
        case .screensDown: "iphone.slash"
        case .lastMeal: "fork.knife"
        case .napTiming: "powersleep"
        case .exerciseTiming: "figure.run"
        case .coolBedroom: "thermometer.snowflake"
        }
    }

    /// The personalised rule, e.g. "Last caffeine by 2:00 PM".
    func rule(_ t: HabitTiming) -> String {
        switch self {
        case .consistentWake: "Up within an hour of \(t.wake), weekends included"
        case .morningLight: "10–25 min outside within 2 h of waking (by \(t.afterWake(CircadianConfig.morningLightWindowMinutes)))"
        case .eveningDim: "Overhead lights off, warm low lamps from \(t.dimFrom)"
        case .caffeineCutoff: "Last caffeine by \(t.caffeineCutoff)"
        case .darkBedroom: "Blackout curtains or an eye mask, no lights on while you sleep"
        case .daytimeLight: "Time outdoors or near a bright window during the day"
        case .sleepOpportunity: "In bed by \(t.bed), leaving room for 7–9 h of sleep"
        case .alcoholCutoff: "Last drink by \(t.beforeBed(CircadianConfig.alcoholCutoffMinutes))"
        case .screensDown: "Brightness low in the evening, screens away by \(t.beforeBed(CircadianConfig.screensDownMinutes))"
        case .lastMeal: "Last big meal by \(t.beforeBed(CircadianConfig.lastMealMinutes))"
        case .napTiming: "If you nap, keep it under \(Int(CircadianConfig.napMaxMinutes)) min and before \(t.beforeBed(CircadianConfig.napLatestBeforeBedMinutes))"
        case .exerciseTiming: "Exercise regularly; finish hard workouts by \(t.beforeBed(CircadianConfig.hardExerciseCutoffMinutes))"
        case .coolBedroom: "A cool, comfortable room; many people sleep best around 16–19 °C (60–67 °F)"
        }
    }

    /// Plain-language evidence summary. Hedged; effects vary between people.
    var why: String {
        switch self {
        case .consistentWake:
            "Wake time sets when your morning light arrives, which anchors the rest of the day's timing. Big weekend shifts act like a small time-zone change every week and are linked with poorer sleep and daytime functioning."
        case .morningLight:
            "Light soon after waking is the strongest everyday signal for keeping your clock early and stable. Outdoors is usually many times brighter than indoors, even when it's cloudy. If you're up before sunrise, bright indoor light first and outside once it's light still helps."
        case .eveningDim:
            "Bright evening light delays your clock and suppresses melatonin. Expert consensus guidance is to keep evening light dim from at least 3 hours before bed. How sensitive people are varies a lot, so some benefit much more than others."
        case .caffeineCutoff:
            "Caffeine blocks adenosine, the sleep-pressure signal, and can stay active for many hours. A recent meta-analysis suggests a typical cup of coffee should be finished roughly 9 hours before bed to avoid cutting into sleep; stronger drinks need longer."
        case .darkBedroom:
            "Light can reach the clock through closed eyelids. Consensus guidance is to keep the sleep environment as dark as possible, and a lab study found that sleeping with a dim overhead light raised heart rate and next-morning insulin resistance."
        case .daytimeLight:
            "Brighter days strengthen the daily signal to your clock and may make you less sensitive to light in the evening."
        case .sleepOpportunity:
            "Adults generally need at least 7 hours of sleep. A bedtime that leaves room for it protects the sleep that your wake time and morning light anchor."
        case .alcoholCutoff:
            "Alcohol can make you drowsy, but it tends to fragment sleep and reduce REM sleep in the second half of the night, more so in larger amounts."
        case .screensDown:
            "A bright screen held close adds to evening light, and engaging content can push bedtime later. The light effect is usually smaller than room lighting, and warm-tint modes on their own have shown little benefit, so brightness and timing matter more."
        case .lastMeal:
            "Meal timing is a signal for the clocks in your body's organs. Eating late can put them out of step with the brain's light-set clock, and a big meal close to bed can make sleep less comfortable."
        case .napTiming:
            "Short naps can boost alertness, but long or late naps use up the sleep pressure that helps you fall asleep at night."
        case .exerciseTiming:
            "Regular exercise supports sleep. Evening exercise is generally fine, but vigorous exercise within about an hour of bed may make it harder to fall asleep."
        case .coolBedroom:
            "Body temperature drops as you fall asleep, and a room that's too warm tends to make sleep lighter and more broken."
        }
    }

    /// Key references behind `why`.
    var sources: [String] {
        switch self {
        case .consistentWake:
            ["Wittmann M et al. (2006). Social jetlag. Chronobiology International.",
             "Phillips AJK et al. (2017). Irregular sleep/wake patterns. Scientific Reports."]
        case .morningLight:
            ["Khalsa SBS et al. (2003). A phase response curve to single bright light pulses in human subjects. Journal of Physiology.",
             "Brown TM et al. (2022). Recommendations for daytime, evening, and nighttime indoor light exposure. PLoS Biology."]
        case .eveningDim:
            ["Brown TM et al. (2022). Recommendations for daytime, evening, and nighttime indoor light exposure. PLoS Biology.",
             "Gooley JJ et al. (2011). Exposure to room light before bedtime suppresses melatonin onset. Journal of Clinical Endocrinology & Metabolism.",
             "Phillips AJK et al. (2019). High sensitivity and interindividual variability in the response of the human circadian system to evening light. PNAS."]
        case .caffeineCutoff:
            ["Gardiner C et al. (2023). The effect of caffeine on subsequent sleep: a systematic review and meta-analysis. Sleep Medicine Reviews.",
             "Drake C et al. (2013). Caffeine effects on sleep taken 0, 3, or 6 hours before going to bed. Journal of Clinical Sleep Medicine."]
        case .darkBedroom:
            ["Brown TM et al. (2022). Recommendations for daytime, evening, and nighttime indoor light exposure. PLoS Biology.",
             "Mason IC et al. (2022). Light exposure during sleep impairs cardiometabolic function. PNAS."]
        case .daytimeLight:
            ["Brown TM et al. (2022). Recommendations for daytime, evening, and nighttime indoor light exposure. PLoS Biology.",
             "Hébert M et al. (2002). The effects of prior light history on the suppression of melatonin by light in humans. Journal of Pineal Research."]
        case .sleepOpportunity:
            ["Watson NF et al. (2015). Recommended amount of sleep for a healthy adult (AASM/SRS consensus). Sleep."]
        case .alcoholCutoff:
            ["Ebrahim IO et al. (2013). Alcohol and sleep I: effects on normal sleep. Alcoholism: Clinical and Experimental Research."]
        case .screensDown:
            ["Chang AM et al. (2015). Evening use of light-emitting eReaders. PNAS.",
             "Duraccio KM et al. (2021). Does iPhone night shift mode better regulate melatonin and sleep? Sleep Health."]
        case .lastMeal:
            ["Wehrens SMT et al. (2017). Meal timing regulates the human circadian system. Current Biology."]
        case .napTiming:
            ["Milner CE, Cote KA (2009). Benefits of napping in healthy adults. Journal of Sleep Research."]
        case .exerciseTiming:
            ["Stutz J et al. (2019). Effects of evening exercise on sleep in healthy participants: a systematic review and meta-analysis. Sports Medicine."]
        case .coolBedroom:
            ["Okamoto-Mizuno K, Mizuno K (2012). Effects of thermal environment on sleep and circadian rhythm. Journal of Physiological Anthropology."]
        }
    }

    /// Question for the next-morning check-in, or nil when the habit is tracked from Health data.
    /// Without a light sensor, morning light is asked about too.
    func checkInPrompt(_ t: HabitTiming, canSenseLight: Bool = true) -> String? {
        switch self {
        case .morningLight: canSenseLight ? nil : "Got outside within 2 h of waking"
        case .consistentWake, .sleepOpportunity: nil
        case .eveningDim: "Lights dimmed from \(t.dimFrom)"
        case .caffeineCutoff: "No caffeine after \(t.caffeineCutoff)"
        case .darkBedroom: "Slept in a dark room"
        case .daytimeLight: "Got outdoor or window light during the day"
        case .alcoholCutoff: "No alcohol after \(t.beforeBed(CircadianConfig.alcoholCutoffMinutes))"
        case .screensDown: "Screens away by \(t.beforeBed(CircadianConfig.screensDownMinutes))"
        case .lastMeal: "Last big meal by \(t.beforeBed(CircadianConfig.lastMealMinutes))"
        case .napTiming: "No long naps, and none after \(t.beforeBed(CircadianConfig.napLatestBeforeBedMinutes))"
        case .exerciseTiming: "No hard workout after \(t.beforeBed(CircadianConfig.hardExerciseCutoffMinutes))"
        case .coolBedroom: "Bedroom was cool"
        }
    }

    /// Line on the evening wind-down card, for habits that belong to the evening routine.
    func eveningStep(_ t: HabitTiming) -> String? {
        switch self {
        case .alcoholCutoff: "Last drink by \(t.beforeBed(CircadianConfig.alcoholCutoffMinutes))"
        case .lastMeal: "Last big meal by \(t.beforeBed(CircadianConfig.lastMealMinutes))"
        case .screensDown: "Screens away by \(t.beforeBed(CircadianConfig.screensDownMinutes))"
        case .sleepOpportunity: "In bed by \(t.bed)"
        default: nil
        }
    }

    /// Recommendation cards this habit drives.
    var recommendationKinds: Set<RecommendationKind> {
        switch self {
        case .consistentWake: [.anchorWake]
        case .morningLight: [.morningLight, .lateDayLight]
        case .caffeineCutoff: [.caffeineCutoff]
        case .eveningDim, .alcoholCutoff, .lastMeal, .screensDown, .sleepOpportunity: [.windDown]
        case .darkBedroom, .daytimeLight, .napTiming, .exerciseTiming, .coolBedroom: []
        }
    }
}

enum HabitCatalog {
    /// Most important first.
    static let ranked: [HabitKey] = HabitKey.allCases.sorted { $0.tier < $1.tier }

    /// Habits that feed the evening wind-down card.
    static let eveningHabits: [HabitKey] = [.eveningDim, .lastMeal, .alcoholCutoff, .screensDown, .sleepOpportunity]

    /// What users who set up Circadia before habits existed had: the four core cards. The wake anchor
    /// never notified, so it counts as "already do" and the focus stays within the cap.
    static let legacyDefaults: [HabitKey: HabitStatus] = [
        .consistentWake: .alreadyDo, .morningLight: .wantToStart,
        .eveningDim: .wantToStart, .caffeineCutoff: .wantToStart,
    ]

    /// Kinds that may notify: only habits the user wants to start get nudges.
    static func nudgeKinds(for statuses: [HabitKey: HabitStatus]) -> Set<RecommendationKind> {
        var kinds: Set<RecommendationKind> = [.travelShift]
        for (habit, status) in statuses where status == .wantToStart {
            kinds.formUnion(habit.recommendationKinds)
        }
        return kinds
    }

    /// Habits to ask about in the morning check-in, most important first.
    static func checkInHabits(for statuses: [HabitKey: HabitStatus], timing: HabitTiming, canSenseLight: Bool = true) -> [HabitKey] {
        ranked.filter { statuses[$0] == .wantToStart && $0.checkInPrompt(timing, canSenseLight: canSenseLight) != nil }
    }

    /// The day the morning check-in asks about, if it's due now.
    /// Due after today's wake (actual or target) until `checkInVisibleUntilHour`, and only if habits
    /// were chosen before yesterday's wind-down began.
    static func checkInDay(now: Date, activeDay: Date, wakeToday: Date?, timing: HabitTiming,
                           habitsChosenAt: Date?, calendar: Calendar) -> Date? {
        guard let chosenAt = habitsChosenAt,
              let yesterday = calendar.date(byAdding: .day, value: -1, to: activeDay) else { return nil }
        let bed = ClockMath.bedtimeMinutes(timing.bedMinutes)
        let yesterdayWindDown = ClockMath.date(on: yesterday, minutes: bed - CircadianConfig.windDownLeadMinutes, calendar: calendar)
        guard chosenAt < yesterdayWindDown else { return nil }
        let wake = wakeToday ?? ClockMath.date(on: activeDay, minutes: timing.wakeMinutes, calendar: calendar)
        let closes = ClockMath.date(on: activeDay, minutes: Double(CircadianConfig.checkInVisibleUntilHour * 60), calendar: calendar)
        guard now >= wake, now < closes else { return nil }
        return yesterday
    }
}

/// One morning check-in question and, once given, its answer. Answers stay visible.
struct CheckInItem: Identifiable, Equatable, Sendable {
    var id: HabitKey { habit }
    let habit: HabitKey
    /// nil until answered.
    var followed: Bool?
}

/// A recommendation the user (or Health data) has checked off today. Stays on Today as done.
struct CompletedRecommendation: Identifiable, Equatable, Sendable {
    let id: String
    let kind: RecommendationKind
    let completedAt: Date
    let detectedAutomatically: Bool
}
