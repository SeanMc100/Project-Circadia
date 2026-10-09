import SwiftUI

/// Where the sun actually is right now. Drives the background and accent.
enum SkyPhase: String, CaseIterable {
    case preDawn, morning, midday, goldenHour, night

    static func current(at date: Date, sun: SunTimes?, calendar: Calendar = .current) -> SkyPhase {
        if let sunrise = sun?.sunrise, let sunset = sun?.sunset {
            if date < sunrise.adding(minutes: -75) || date > sunset.adding(minutes: 45) { return .night }
            if date < sunrise { return .preDawn }
            if date < sunrise.adding(minutes: 180) { return .morning }
            if date >= sunset.adding(minutes: -90) { return .goldenHour }
            return .midday
        }
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5: return .preDawn
        case 6..<10: return .morning
        case 10..<17: return .midday
        case 17..<20: return .goldenHour
        default: return .night
        }
    }

    var greeting: String {
        switch self {
        case .preDawn: "Before sunrise"
        case .morning: "Good morning"
        case .midday: "Midday"
        case .goldenHour: "Golden hour"
        case .night: "Evening"
        }
    }

    var palette: ThemePalette {
        switch self {
        case .preDawn:
            ThemePalette(top: Color(light: 0xE4E2F3, dark: 0x16172E), bottom: Color(light: 0xF7F3EF, dark: 0x0D0E1B),
                         accent: Color(light: 0x4F4FA6, dark: 0xA9ABF2))
        case .morning:
            ThemePalette(top: Color(light: 0xFDEBD3, dark: 0x2B2017), bottom: Color(light: 0xFAF7F2, dark: 0x13100D),
                         accent: Color(light: 0xA85612, dark: 0xF2AE6B))
        case .midday:
            ThemePalette(top: Color(light: 0xDDEDF9, dark: 0x10202C), bottom: Color(light: 0xF7FAFC, dark: 0x0A1218),
                         accent: Color(light: 0x1C6496, dark: 0x82C0EC))
        case .goldenHour:
            ThemePalette(top: Color(light: 0xFADFCB, dark: 0x2C1B15), bottom: Color(light: 0xFBF5EE, dark: 0x130D0B),
                         accent: Color(light: 0xA6461F, dark: 0xF3A27A))
        case .night:
            ThemePalette(top: Color(light: 0xE1E4EF, dark: 0x0C0F1D), bottom: Color(light: 0xF3F4F8, dark: 0x06070E),
                         accent: Color(light: 0x41508A, dark: 0xA2B0E0))
        }
    }
}

struct ThemePalette {
    let top: Color
    let bottom: Color
    let accent: Color
}

/// Fixed semantic colours used across phases.
enum Palette {
    static let sleep = Color(light: 0x4A4EA6, dark: 0x8F93EA)
    static let light = Color(light: 0xC77A12, dark: 0xF4B860)
    static let daylightBand = Color(light: 0xF2C14E, dark: 0xF2C14E)
    static let track = Color.primary.opacity(0.08)
    static let favorable = Color(light: 0x2E7D4F, dark: 0x7BD1A0)
    static let unfavorable = Color(light: 0xA6461F, dark: 0xF3A27A)
}

private struct SkyPhaseKey: EnvironmentKey {
    static let defaultValue: SkyPhase = .midday
}

extension EnvironmentValues {
    var skyPhase: SkyPhase {
        get { self[SkyPhaseKey.self] }
        set { self[SkyPhaseKey.self] = newValue }
    }
}

/// Full-screen background that follows the sun.
struct SkyBackground: View {
    @Environment(\.skyPhase) private var phase

    var body: some View {
        LinearGradient(colors: [phase.palette.top, phase.palette.bottom], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 1.2), value: phase)
    }
}
