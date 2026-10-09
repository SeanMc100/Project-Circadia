import SwiftUI

/// Data for the 24-hour ring: the user's *ideal* day, built from their wake and bed targets.
/// All times are minutes after local midnight (0..<1440).
struct RingModel: Equatable {
    /// A habit marked on the ring at the time it applies.
    struct Pin: Equatable, Identifiable {
        var id: HabitKey { habit }
        let habit: HabitKey
        let minutes: Double
        /// Short time phrase, e.g. "by 8:45 AM".
        let timeText: String
        /// Where the pin is drawn. Matches `minutes` unless it had to be nudged away from a neighbour.
        var displayMinutes: Double

        init(habit: HabitKey, minutes: Double, timeText: String) {
            self.habit = habit
            self.minutes = minutes
            self.timeText = timeText
            displayMinutes = minutes
        }

        /// Compact clock label for the dial, e.g. "7a" or "2:15p".
        var clockLabel: String {
            let m = Int(minutes.rounded()) % 1440
            let hour = m / 60, minute = m % 60
            let h12 = hour % 12 == 0 ? 12 : hour % 12
            let suffix = hour < 12 ? "a" : "p"
            return minute == 0 ? "\(h12)\(suffix)" : String(format: "%d:%02d%@", h12, minute, suffix)
        }
    }

    /// Pins closer than this (in clock minutes) are spread apart so icons and labels don't collide.
    static let minimumPinGap: Double = 75

    var wakeMinutes: Double
    var bedMinutes: Double
    var pins: [Pin]
    var nowMinutes: Double
    var centerValue: String
    var centerCaption: String
    var centerBand: String?

    /// The ideal rhythm for these targets, with the core timed habits pinned on it.
    init(timing: HabitTiming, nowMinutes: Double, centerValue: String = "–",
         centerCaption: String = "alignment estimate", centerBand: String? = nil) {
        wakeMinutes = ClockMath.wrapPositive(timing.wakeMinutes)
        bedMinutes = ClockMath.wrapPositive(timing.bedMinutes)
        self.nowMinutes = nowMinutes
        self.centerValue = centerValue
        self.centerCaption = centerCaption
        self.centerBand = centerBand
        let lightEnd = ClockMath.wrapPositive(timing.wakeMinutes + CircadianConfig.morningLightWindowMinutes)
        let caffeine = timing.bedMinutes - timing.caffeineCutoffHours * 60
        let dim = timing.bedMinutes - CircadianConfig.windDownLeadMinutes
        pins = [
            Pin(habit: .consistentWake, minutes: wakeMinutes, timeText: "at \(timing.wake)"),
            Pin(habit: .morningLight, minutes: lightEnd, timeText: "by \(ClockMath.clockString(lightEnd))"),
            Pin(habit: .caffeineCutoff, minutes: ClockMath.wrapPositive(caffeine), timeText: "by \(timing.caffeineCutoff)"),
            Pin(habit: .eveningDim, minutes: ClockMath.wrapPositive(dim), timeText: "from \(timing.dimFrom)"),
            Pin(habit: .sleepOpportunity, minutes: bedMinutes, timeText: "by \(timing.bed)"),
        ]
        spreadPins()
    }

    /// Nudges neighbouring pins apart (in day order from wake) until each pair is at least
    /// `minimumPinGap` apart. Labels still show the true time.
    private mutating func spreadPins() {
        let wake = wakeMinutes
        var offsets = pins.map { ClockMath.wrapPositive($0.minutes - wake) }
        for _ in 0..<8 {
            var moved = false
            for i in 0..<offsets.count - 1 {
                let gap = offsets[i + 1] - offsets[i]
                if gap < Self.minimumPinGap {
                    let push = (Self.minimumPinGap - gap) / 2
                    offsets[i] -= push
                    offsets[i + 1] += push
                    moved = true
                }
            }
            if !moved { break }
        }
        for i in pins.indices { pins[i].displayMinutes = ClockMath.wrapPositive(offsets[i] + wake) }
    }

    var accessibilitySummary: String {
        pins.map { "\($0.habit.title) \($0.timeText)." }.joined(separator: " ")
    }
}

/// The app's signature visual: your ideal day as a 24-hour sky, midnight at the bottom and noon
/// at the top. The band runs night → dawn → day → dusk around your own wake and bed targets,
/// the core habits sit on it as tappable pins, and a small hand marks the current time.
struct CircadianRing: View {
    let model: RingModel
    var onSelect: (HabitKey) -> Void = { _ in }
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 60
    @State private var appeared = false

    private let band: CGFloat = 30
    private let pinSize: CGFloat = 36

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2 - pinSize / 2 - 4
            let gradient = skyGradient

            ZStack {
                // Soft glow of the same sky behind the band.
                RingArc(start: 0, end: 1440, radius: radius)
                    .stroke(gradient, lineWidth: band)
                    .blur(radius: 18)
                    .opacity(0.45)

                RingArc(start: 0, end: 1440, radius: radius)
                    .stroke(gradient, lineWidth: band)
                // Hairline edges lift the band off the background, mainly the night in dark mode.
                ForEach([radius - band / 2, radius + band / 2], id: \.self) { r in
                    RingArc(start: 0, end: 1440, radius: r)
                        .stroke(Sky.edge, lineWidth: 1)
                }

                hourTicks(radius: radius - band / 2 - 8, in: geo.size)
                pinLabels(radius: radius - band / 2 - 24, in: geo.size)

                nowHand(radius: radius, in: geo.size)

                ForEach(model.pins) { pin in
                    pinButton(pin)
                        .position(point(minutes: pin.displayMinutes, radius: radius, in: geo.size))
                }

                center
                    .frame(width: max(0, (radius - band) * 1.5))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(appeared ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { withAnimation(.spring(duration: 0.7, bounce: 0.2)) { appeared = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your ideal day. \(model.centerCaption) \(model.centerValue)\(model.centerBand.map { ", \($0)" } ?? "").")
    }

    // MARK: - Pieces

    private var center: some View {
        VStack(spacing: 0) {
            Text(model.centerValue)
                .font(.system(size: valueSize, weight: .light, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
            if let bandText = model.centerBand {
                Text(bandText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.sleep)
            }
            Text(model.centerCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
    }

    private func pinButton(_ pin: RingModel.Pin) -> some View {
        Button { onSelect(pin.habit) } label: {
            Image(systemName: pin.habit.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(pin.habit.isSleepAnchor ? Palette.sleep : Palette.light)
                .frame(width: pinSize, height: pinSize)
                .background(Circle().fill(Color(light: 0xFFFFFF, dark: 0x1E1F2A)))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                .contentShape(Circle().inset(by: -6))
        }
        .buttonStyle(PinButtonStyle())
        .accessibilityLabel("\(pin.habit.title), \(pin.timeText)")
        .accessibilityHint("Shows timing and why it matters")
    }

    private func nowHand(radius: CGFloat, in size: CGSize) -> some View {
        let p = point(minutes: model.nowMinutes, radius: radius, in: size)
        return Capsule()
            .fill(Color(light: 0xFFFFFF, dark: 0xFFFFFF))
            .frame(width: 4, height: band + 10)
            .shadow(color: .black.opacity(0.25), radius: 2)
            .rotationEffect(RingArc.angle(for: model.nowMinutes) + .degrees(90))
            .position(p)
            .accessibilityHidden(true)
    }

    private func hourTicks(radius: CGFloat, in size: CGSize) -> some View {
        ZStack {
            ForEach(0..<24, id: \.self) { h in
                let major = h % 6 == 0
                Capsule()
                    .fill(Color.primary.opacity(major ? 0.25 : 0.12))
                    .frame(width: major ? 2 : 1, height: major ? 6 : 4)
                    .rotationEffect(RingArc.angle(for: Double(h * 60)) + .degrees(90))
                    .position(point(minutes: Double(h * 60), radius: radius, in: size))
            }
        }
        .accessibilityHidden(true)
    }

    /// Each habit's time, just inside the band next to its pin.
    private func pinLabels(radius: CGFloat, in size: CGSize) -> some View {
        ForEach(model.pins) { pin in
            Text(pin.clockLabel)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
                .position(point(minutes: pin.displayMinutes, radius: radius, in: size))
        }
        .accessibilityHidden(true)
    }

    // MARK: - Sky

    /// Night → dawn → day → dusk, laid out relative to wake so it never has to wrap midnight.
    private var skyGradient: AngularGradient {
        let awake = ClockMath.wrapPositive(model.bedMinutes - model.wakeMinutes)
        let dim = max(awake - CircadianConfig.windDownLeadMinutes, 120)
        let nightEnd = 1440.0 - 60
        let stops: [(Double, Color)] = [
            (0, Sky.dawn),
            (90, Sky.morning),
            ((90 + dim) / 2, Sky.day),
            (dim - 45, Sky.afternoon),
            (dim, Sky.dusk),
            (awake - 45, Sky.twilight),
            (awake + 30, Sky.night),
            (nightEnd - 30, Sky.night),
            (nightEnd, Sky.predawn),
            (1440, Sky.dawn),
        ]
        let sorted = stops
            .map { (min(max($0.0, 0), 1440), $0.1) }
            .sorted { $0.0 < $1.0 }
            .map { Gradient.Stop(color: $0.1, location: $0.0 / 1440) }
        let start = RingArc.angle(for: model.wakeMinutes)
        return AngularGradient(gradient: Gradient(stops: sorted), center: .center,
                               startAngle: start, endAngle: start + .degrees(360))
    }

    // MARK: - Geometry

    private func point(minutes: Double, radius: CGFloat, in size: CGSize) -> CGPoint {
        let angle = RingArc.angle(for: minutes).radians
        return CGPoint(x: size.width / 2 + radius * CGFloat(cos(angle)), y: size.height / 2 + radius * CGFloat(sin(angle)))
    }
}

/// Sky colours for the ring, from deep night through dawn, day and dusk.
private enum Sky {
    static let night = Color(light: 0x2B2F6B, dark: 0x343A88)
    static let predawn = Color(light: 0x7363AE, dark: 0x6758A3)
    static let dawn = Color(light: 0xEE9A74, dark: 0xE08C68)
    static let morning = Color(light: 0xF5B94F, dark: 0xF0B04A)
    static let day = Color(light: 0xF8DC92, dark: 0xF2D184)
    static let afternoon = Color(light: 0xF4C677, dark: 0xEDBB6A)
    static let dusk = Color(light: 0xE6854D, dark: 0xDD7A44)
    static let twilight = Color(light: 0x9C5F8C, dark: 0x8E5582)
    /// Barely there on light backgrounds; a clear hairline in dark mode.
    static let edge = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.32) : UIColor(white: 0, alpha: 0.06)
    })
}

private extension HabitKey {
    /// Wake and bed bracket the night, so their pins take the sleep colour.
    var isSleepAnchor: Bool { self == .consistentWake || self == .sleepOpportunity }
}

private struct PinButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// An arc of the 24-hour dial. Midnight is at the bottom; time runs clockwise.
struct RingArc: Shape {
    var start: Double
    var end: Double
    var radius: CGFloat

    static func angle(for minutes: Double) -> Angle {
        .degrees(90 + minutes / 1440 * 360)
    }

    func path(in rect: CGRect) -> Path {
        var e = end
        if e <= start { e += 1440 }
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                    startAngle: Self.angle(for: start), endAngle: Self.angle(for: min(e, start + 1440)), clockwise: false)
        return path
    }
}

#Preview {
    CircadianRing(model: RingModel(timing: HabitTiming(wakeMinutes: 405, bedMinutes: 1365), nowMinutes: 585,
                                   centerValue: "62", centerBand: "Fair"))
        .padding()
}
