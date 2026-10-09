import Foundation

enum MechanismKey: String, CaseIterable, Identifiable, Hashable, Sendable {
    case lightAndSCN, phaseResponse, melatoninTiming, eveningLight, consistency, socialJetlag, caffeineAdenosine, travelDirection

    var id: String { rawValue }
}

struct MechanismEntry: Identifiable, Hashable {
    var id: MechanismKey { key }
    let key: MechanismKey
    let title: String
    let systemImage: String
    /// One sentence, shown inline on recommendation cards.
    let headline: String
    /// Two or three sentences of cause and effect.
    let why: String
    /// A longer paragraph for the Learn tab.
    let deeper: String
}

/// Short, general, accurate explanations. No invented study names; effect sizes are hedged
/// because they vary a lot between people.
enum MechanismLibrary {

    /// Reading order for the Learn tab.
    static let sequence: [MechanismKey] = [
        .lightAndSCN, .phaseResponse, .melatoninTiming, .eveningLight,
        .consistency, .socialJetlag, .caffeineAdenosine, .travelDirection,
    ]

    static var all: [MechanismEntry] { sequence.map(entry(for:)) }

    static func entry(for key: MechanismKey) -> MechanismEntry {
        switch key {
        case .lightAndSCN:
            MechanismEntry(
                key: key, title: "Light sets the clock", systemImage: "sun.max",
                headline: "Bright light reaching your eyes is the main signal that sets your body clock.",
                why: "Specialised cells in the retina (intrinsically photosensitive retinal ganglion cells, or ipRGCs) contain a pigment called melanopsin and respond most to bright, blue-rich light. They signal directly to the suprachiasmatic nucleus (SCN), the master clock in the brain, which then times melatonin, body temperature and alertness. Outdoor daylight, even on a cloudy day, is usually many times brighter than indoor lighting, so it sends a much stronger signal.",
                deeper: "Left alone, most people's internal clock runs a little longer than 24 hours, so it needs a daily nudge to stay in step with the day. Light is the strongest of these nudges. The ipRGC system integrates light over minutes rather than reacting to brief flashes, which is why a sustained stretch outdoors matters more than a glance out of the window. How strongly any one person responds varies with their recent light history, age and individual sensitivity, so the minute targets in this app are reasonable starting points rather than precise doses. Never look directly at the sun; normal outdoor time with your eyes open is enough."
            )
        case .phaseResponse:
            MechanismEntry(
                key: key, title: "Timing changes the direction", systemImage: "arrow.left.arrow.right",
                headline: "Light after your body's temperature low shifts your clock earlier; light before it shifts you later.",
                why: "Your clock's response to light depends on the clock's own time. Core body temperature reaches its daily low a couple of hours before your usual wake time; light after that point tends to move your rhythm earlier, and light in the late evening and night tends to move it later. Light in the middle of the day has a smaller shifting effect, so afternoon light is a weaker substitute for morning light.",
                deeper: "This relationship is called a phase response curve. The size of the shift depends on how bright the light is, how long it lasts and what light you have had recently, and it differs between people. This app does not measure your temperature low; it estimates your timing from your sleep, which is a reasonable proxy but not a measurement. That's why its suggestions use broad windows ('within two hours of waking') rather than exact minutes. Bright daytime light may also make you somewhat less sensitive to light later in the evening, which is one reason a brighter day can still help even when the timing isn't ideal."
            )
        case .melatoninTiming:
            MechanismEntry(
                key: key, title: "Melatonin follows the anchor", systemImage: "moon.stars",
                headline: "Melatonin tends to rise roughly 14 to 16 hours after your morning light anchor.",
                why: "When morning light resets your clock, the SCN schedules melatonin release for the evening, roughly 14 to 16 hours later for many people. Rising melatonin is part of what makes sleep easier to start. Consistent morning light keeps that evening rise steady, so sleepiness tends to arrive at a predictable time.",
                deeper: "The most reliable lab marker of circadian timing is dim-light melatonin onset (DLMO): the time melatonin starts rising in the evening when measured under dim light. Measuring it takes repeated saliva or blood samples, so this app cannot know yours. It uses sleep timing as a stand-in and treats the 14 to 16 hour figure as a rough range, not a rule. Bright evening light can delay and suppress this rise (see 'Evening light'), which is why morning anchoring and evening dimming work as a pair."
            )
        case .eveningLight:
            MechanismEntry(
                key: key, title: "Evening light", systemImage: "lightbulb.min",
                headline: "Bright evening light suppresses melatonin and nudges your clock later.",
                why: "The same light-sensing pathway that helps you in the morning works against you at night. In the evening, light falls on the 'shift later' part of the clock's response and also acutely suppresses melatonin. Dimmer, warmer light positioned below eye level sends a much weaker signal, which helps your melatonin rise on schedule.",
                deeper: "People differ a lot in how sensitive they are to evening light; some show large melatonin suppression at ordinary room brightness and others very little. Overhead room lighting is often a bigger contributor than a phone, but brightness and closeness add up, so lowering screen brightness still helps. Warm-tint 'night modes' reduce the blue component somewhat, but overall brightness matters more. Expert consensus guidance is to keep light dim from at least three hours before bed, which gives the evening melatonin rise room to happen."
            )
        case .consistency:
            MechanismEntry(
                key: key, title: "Consistency", systemImage: "metronome",
                headline: "Regular sleep timing can matter as much as total sleep.",
                why: "Your clock anticipates: it prepares melatonin, temperature and alertness changes for when it expects you to sleep and wake. When your timing is steady, those internal signals line up with your actual sleep. When it varies, you end up sleeping at different internal times, and sleep can be harder to start or feel less refreshing. Wake time is the strongest lever because it also sets when your morning light arrives.",
                deeper: "Studies of sleep regularity have linked steadier timing with better daytime functioning and wellbeing measures. These are mostly associations, and how much regularity matters varies between people. A practical approach is to hold your wake time within about an hour every day, including weekends, and let bedtime follow sleepiness. The consistency number in this app is the spread (standard deviation) of your sleep onset and wake times over the last week."
            )
        case .socialJetlag:
            MechanismEntry(
                key: key, title: "Social jetlag", systemImage: "calendar.badge.clock",
                headline: "Sleeping in on weekends is a bit like flying a time zone or two west every Friday.",
                why: "Later weekend sleep usually means later light exposure, and later light pushes your clock later. Monday then arrives with your body clock set later than your alarm, much like returning from a westward trip. The bigger the weekend shift, the longer the recovery into the week.",
                deeper: "'Social jetlag' is the gap between the middle of your sleep on free days and on work days. Gaps of an hour or more are common. You don't need to eliminate it; keeping weekend wake times within about an hour of weekdays, and getting outside early on weekend mornings, tends to keep the gap small. This app calculates it from your last four weeks of sleep midpoints."
            )
        case .caffeineAdenosine:
            MechanismEntry(
                key: key, title: "Caffeine and adenosine", systemImage: "cup.and.saucer",
                headline: "Caffeine blocks adenosine, the sleep-pressure signal that builds while you're awake.",
                why: "Adenosine accumulates the longer you're awake and is a major driver of sleepiness. Caffeine occupies adenosine's receptors, so you feel less sleepy without the pressure going away. Caffeine's half-life varies widely between people (roughly 3 to 7 hours is common, and longer for some), so an afternoon coffee may still be active at bedtime and can make sleep lighter even when you do fall asleep.",
                deeper: "How quickly you clear caffeine depends on genetics, pregnancy, some medications, smoking and other factors. A cutoff of about 8 to 10 hours before bed is a conservative default; some people can drink coffee later without issue and others are sensitive to a single morning cup. Remember tea, cola, energy drinks, pre-workout products and chocolate. Adjust the cutoff in Settings once you know how you respond."
            )
        case .travelDirection:
            MechanismEntry(
                key: key, title: "Travel direction", systemImage: "airplane",
                headline: "Flying east means shifting your clock earlier; flying west means shifting it later.",
                why: "After eastward travel, local time is ahead of your body, so you need to shift earlier: seek morning light and avoid bright evening light. After westward travel, local time is behind your body, so you need to shift later: seek late-afternoon and evening light and avoid bright early-morning light. Most people adapt at roughly an hour a day, often a little faster going west.",
                deeper: "For large eastward jumps (around eight time zones or more), very early local morning light can land before your body's temperature low, which is still the middle of your body's night, and push your clock the wrong way. Starting with late-morning light for the first couple of days avoids this. Short trips of a day or two may not be worth shifting for at all. Questions about melatonin supplements or sleep medication for travel are for a clinician or pharmacist; this app gives light-timing guidance only."
            )
        }
    }
}
