import Foundation

/// A completed light recommendation, shown as a brief "here's what just happened" moment.
struct PayoffEvent: Identifiable, Equatable {
    let id = UUID()
    let kind: RecommendationKind
    let completedAt: Date
    let detectedAutomatically: Bool
}

struct PayoffContent {
    let title: String
    let whatHappened: String
    let tonight: String
    let mechanismKey: MechanismKey

    /// Hedged, mechanism-first explanation of what the light just did.
    static func make(for event: PayoffEvent, calendar: Calendar = .current) -> PayoffContent {
        let start = event.completedAt.addingTimeInterval(14 * 3600)
        let end = event.completedAt.addingTimeInterval(16 * 3600)
        let range = "\(ClockMath.timeString(start)) and \(ClockMath.timeString(end))"
        let source = event.detectedAutomatically ? "Your watch logged the time outside. " : ""

        switch event.kind {
        case .lateDayLight:
            return PayoffContent(
                title: "Afternoon light logged",
                whatHappened: source + "Outdoor light reached the light-sensing cells in your eyes and told your master clock it's daytime. In the afternoon this shifts your clock less than morning light would, but it adds a clear daytime signal.",
                tonight: "Expect a modest effect. Brighter days tend to make you a little less sensitive to light in the evening, so dimming the lights later should work better tonight. Tomorrow, morning light is still the stronger move.",
                mechanismKey: .phaseResponse)
        case .travelShift:
            return PayoffContent(
                title: "Shift step done",
                whatHappened: source + "Light at this time of day pushes your clock in the direction of your new time zone. Each well-timed dose tends to move it by up to about an hour.",
                tonight: "Follow the evening part of today's plan too. The light you avoid matters as much as the light you get.",
                mechanismKey: .travelDirection)
        default:
            return PayoffContent(
                title: "Clock anchored",
                whatHappened: source + "Bright outdoor light just reached the ipRGCs in your eyes, which signal your master clock (the SCN) that the day has started. Because it came after your body's temperature low, it tends to nudge your rhythm slightly earlier.",
                tonight: "Melatonin tends to start rising roughly 14 to 16 hours after a morning anchor, so for you somewhere between \(range). Keeping the evening dim should help sleepiness arrive on time.",
                mechanismKey: .lightAndSCN)
        }
    }
}
