import SwiftUI

/// Data for the 24-hour ring. All times are minutes after local midnight (0..<1440).
struct RingModel: Equatable {
    struct Arc: Equatable {
        var start: Double
        var end: Double
    }

    var sleep: Arc?
    var light: [Arc] = []
    var daylight: Arc?
    var lightWindow: Arc?
    var nowMinutes: Double
    var centerValue: String
    var centerCaption: String

    var accessibilitySummary: String {
        var parts: [String] = []
        if let sleep { parts.append("Last sleep from \(ClockMath.clockString(sleep.start)) to \(ClockMath.clockString(sleep.end)).") }
        if let daylight { parts.append("Daylight from \(ClockMath.clockString(daylight.start)) to \(ClockMath.clockString(daylight.end)).") }
        let lightMinutes = light.reduce(0) { $0 + ClockMath.wrapPositive($1.end - $1.start) }
        parts.append("\(Int(lightMinutes.rounded())) minutes of outdoor light logged today.")
        if let w = lightWindow { parts.append("Recommended light window \(ClockMath.clockString(w.start)) to \(ClockMath.clockString(w.end)).") }
        return parts.joined(separator: " ")
    }
}

/// The app's signature visual: a 24-hour dial with midnight at the bottom and noon at the top.
/// Inner arc: last night's sleep. Outer track: daylight (faint), the recommended light window
/// (dashed) and actual outdoor light (solid). A dot marks the current time.
struct CircadianRing: View {
    let model: RingModel
    @Environment(\.skyPhase) private var phase
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 52

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let outer = size / 2 - 22
            let inner = outer - 22
            ZStack {
                RingArc(start: 0, end: 1440, radius: outer).stroke(Palette.track, lineWidth: 12)
                RingArc(start: 0, end: 1440, radius: inner).stroke(Palette.track, lineWidth: 12)

                if let d = model.daylight {
                    RingArc(start: d.start, end: d.end, radius: outer)
                        .stroke(Palette.daylightBand.opacity(0.28), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                }
                if let w = model.lightWindow {
                    RingArc(start: w.start, end: w.end, radius: outer + 11)
                        .stroke(phase.palette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 5]))
                }
                ForEach(Array(model.light.enumerated()), id: \.offset) { _, arc in
                    RingArc(start: arc.start, end: max(arc.end, arc.start + 4), radius: outer)
                        .stroke(Palette.light, style: StrokeStyle(lineWidth: 12, lineCap: .butt))
                }
                if let s = model.sleep {
                    RingArc(start: s.start, end: s.end, radius: inner)
                        .stroke(Palette.sleep, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                }

                ForEach([0.0, 360, 720, 1080], id: \.self) { m in
                    Text(label(for: m))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .position(point(minutes: m, radius: outer + 26, in: geo.size))
                }

                Circle()
                    .fill(phase.palette.accent)
                    .overlay(Circle().stroke(.background, lineWidth: 2))
                    .frame(width: 14, height: 14)
                    .position(point(minutes: model.nowMinutes, radius: outer, in: geo.size))

                VStack(spacing: 2) {
                    Text(model.centerValue)
                        .font(.system(size: valueSize, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(model.centerCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(width: inner * 1.3)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("24-hour rhythm ring. \(model.centerCaption) \(model.centerValue).")
        .accessibilityValue(model.accessibilitySummary)
    }

    private func label(for minutes: Double) -> String {
        switch minutes {
        case 0: "12a"
        case 360: "6a"
        case 720: "12p"
        default: "6p"
        }
    }

    private func point(minutes: Double, radius: CGFloat, in size: CGSize) -> CGPoint {
        let angle = RingArc.angle(for: minutes).radians
        return CGPoint(x: size.width / 2 + radius * CGFloat(cos(angle)), y: size.height / 2 + radius * CGFloat(sin(angle)))
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
    CircadianRing(model: RingModel(sleep: .init(start: 1395, end: 420), light: [.init(start: 460, end: 480), .init(start: 760, end: 775)],
                                   daylight: .init(start: 410, end: 1110), lightWindow: .init(start: 420, end: 540),
                                   nowMinutes: 600, centerValue: "78", centerCaption: "alignment estimate"))
        .padding()
}
