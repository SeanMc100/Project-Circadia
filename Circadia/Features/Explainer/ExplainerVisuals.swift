import SwiftUI

// The animated pictures at the top of each "How Circadia works" page.
// Each one is drawn from a single time value, so Reduce Motion can show a still frame instead.

// MARK: - Animation helpers

/// Seconds since the page became visible. Paused off-screen; frozen at `settled` with Reduce Motion.
struct StoryClock<Content: View>: View {
    let isActive: Bool
    /// The moment that best tells the story on its own, shown when motion is reduced.
    let settled: Double
    @ViewBuilder let content: (Double) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        if reduceMotion {
            content(settled)
        } else {
            TimelineView(.animation(paused: !isActive)) { context in
                content(max(0, context.date.timeIntervalSince(start)))
            }
            .onChange(of: isActive, initial: true) { _, active in
                if active { start = .now }
            }
        }
    }
}

enum Ease {
    /// 0 before `start`, 1 after `start + duration`, smooth in between.
    static func progress(_ t: Double, from start: Double, duration: Double) -> Double {
        let x = clamp((t - start) / duration)
        return x * x * (3 - 2 * x)
    }

    static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    /// Grows past full size and settles back, like a pop.
    static func pop(_ p: Double) -> Double { p + 0.25 * sin(p * .pi) }
}

/// Positions on a 24-hour dial laid out like the Today clock: midnight at the bottom, noon at the top.
enum StoryDial {
    static func offset(minutes: Double, radius: CGFloat) -> CGSize {
        let phi = minutes / 1440 * 2 * .pi
        return CGSize(width: -radius * sin(phi), height: radius * cos(phi))
    }

    /// 1 at noon, 0 at 6 AM and 6 PM, -1 at midnight.
    static func sunHeight(minutes: Double) -> Double {
        -cos(minutes / 1440 * 2 * .pi)
    }
}

// MARK: - 1. The clock inside you

/// The sun circles a 24-hour dial while the body in the middle switches between awake and sleepy.
struct BodyClockVisual: View {
    let isActive: Bool
    private let radius: CGFloat = 104

    var body: some View {
        StoryClock(isActive: isActive, settled: 2) { t in
            let minutes = (360 + t / 9 * 1440).truncatingRemainder(dividingBy: 1440)
            let height = StoryDial.sunHeight(minutes: minutes)
            let sunUp = Ease.clamp(height * 3 + 0.5)
            // A typical day: up around 7 AM, sleepy from around 10 PM.
            let awake = Ease.progress(minutes, from: 390, duration: 60) * (1 - Ease.progress(minutes, from: 1290, duration: 60))

            ZStack {
                Circle()
                    .fill(Palette.sleep.opacity(0.2))
                Circle()
                    .fill(Palette.daylightBand.opacity(0.35))
                    .opacity(Ease.clamp(height * 1.5 + 0.5))
                Circle()
                    .stroke(Palette.track, lineWidth: 2)

                ForEach(0..<24, id: \.self) { hour in
                    Capsule()
                        .fill(Color.secondary.opacity(hour % 6 == 0 ? 0.6 : 0.25))
                        .frame(width: 2, height: hour % 6 == 0 ? 10 : 5)
                        .offset(y: -radius + 10)
                        .rotationEffect(.degrees(Double(hour) * 15))
                }

                ZStack {
                    VStack(spacing: 6) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Palette.light)
                        Text("Awake").font(.headline)
                    }
                    .opacity(Ease.clamp(awake * 2 - 1))
                    .scaleEffect(0.9 + 0.1 * awake)
                    VStack(spacing: 6) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Palette.sleep)
                        Text("Sleepy").font(.headline)
                    }
                    .opacity(Ease.clamp(1 - awake * 2))
                    .scaleEffect(1 - 0.1 * awake)
                }

                // The sun by day, the moon by night, riding the rim.
                ZStack {
                    Circle()
                        .fill(Palette.daylightBand)
                        .frame(width: 30, height: 30)
                        .shadow(color: Palette.daylightBand.opacity(0.7), radius: 10)
                        .opacity(sunUp)
                    Circle()
                        .fill(Palette.sleep)
                        .frame(width: 26, height: 26)
                        .overlay(Image(systemName: "moon.fill").font(.caption).foregroundStyle(.white))
                        .opacity(1 - sunUp)
                }
                .offset(StoryDial.offset(minutes: minutes, radius: radius))

                Text("Noon").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .offset(y: -radius - 26)
                Text("Midnight").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .offset(y: radius + 26)
            }
            .frame(width: radius * 2, height: radius * 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A 24-hour clock. As the sun goes around, the body switches between awake in the day and sleepy at night.")
    }
}

// MARK: - 2. Your body runs on a longer day

/// Two runs of the same week. Without morning light, the body's morning slips 10 minutes later every
/// day until it is an hour behind. With morning light, each day starts to slip and gets nudged back.
struct DriftVisual: View {
    let isActive: Bool
    private let days = 7
    /// When the second run (with morning light) starts.
    private let lightRunStart = 6.2
    private let cycle = 13.0

    var body: some View {
        StoryClock(isActive: isActive, settled: 4.5) { raw in
            let t = raw.truncatingRemainder(dividingBy: cycle)
            let withLight = t >= lightRunStart
            let local = withLight ? t - lightRunStart : t
            let fadeStart = withLight ? cycle - lightRunStart - 0.7 : lightRunStart - 0.7
            let fade = 1 - Ease.progress(local, from: fadeStart, duration: 0.5)
            let modeIn = Ease.progress(local, from: 0, duration: 0.4)

            VStack(spacing: 14) {
                modePill(withLight: withLight)
                    .opacity(min(modeIn, fade))

                VStack(spacing: 9) {
                    ForEach(0..<days, id: \.self) { i in
                        let start = 0.4 + Double(i) * 0.5
                        let appear = Ease.progress(local, from: start, duration: 0.4)
                        let nudge = withLight ? Ease.progress(local, from: start + 0.4, duration: 0.3) : 0
                        row(i,
                            appear: appear,
                            steps: withLight ? appear * (1 - nudge) : Double(i) * appear,
                            glow: sin(nudge * .pi),
                            withLight: withLight,
                            onTime: nudge)
                    }
                }
                .opacity(fade)

                HStack(spacing: 18) {
                    Label {
                        Text("Sunrise")
                    } icon: {
                        Capsule().fill(Palette.light).frame(width: 3, height: 14)
                    }
                    Label {
                        Text("Your body's morning")
                    } icon: {
                        Circle().fill(Palette.sleep).frame(width: 12, height: 12)
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Without morning light, the body's morning drifts about 10 minutes later than sunrise each day, an hour behind after a week. With morning light, each day's small slip gets nudged back on time.")
    }

    private func modePill(withLight: Bool) -> some View {
        let tint = withLight ? Palette.light : Palette.sleep
        return Label(withLight ? "With morning light" : "Without morning light",
                     systemImage: withLight ? "sunrise.fill" : "moon.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule())
    }

    /// `steps` is how far the dot sits from sunrise, in 10-minute steps.
    private func row(_ i: Int, appear: Double, steps: Double, glow: Double, withLight: Bool, onTime: Double) -> some View {
        HStack(spacing: 10) {
            Text("Day \(i + 1)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            GeometryReader { geo in
                let sunriseX = geo.size.width * 0.28
                let x = sunriseX + steps * geo.size.width * 0.075
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.track).frame(height: 4)
                    Circle()
                        .fill(Palette.sleep)
                        .frame(width: 16, height: 16)
                        .offset(x: x - 8)
                    Capsule()
                        .fill(Palette.light)
                        .frame(width: 3, height: 18 + 8 * glow)
                        .shadow(color: Palette.daylightBand.opacity(glow), radius: 8)
                        .offset(x: sunriseX - 1.5)
                    if withLight {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Palette.favorable)
                            .offset(x: sunriseX + 16)
                            .opacity(onTime)
                    } else if i > 0 {
                        Text(i == days - 1 ? "+1 hour" : "+\(i * 10) min")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.sleep)
                            .fixedSize()
                            .offset(x: x + 14)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            }
            .frame(height: 20)
        }
        .opacity(appear)
    }
}

// MARK: - Sleep week chart (page 5)

/// A week of sleep as vertical bars, 10 PM at the top to 9:30 AM at the bottom.
/// A bar with no shift runs 11 PM to 7 AM.
struct SleepWeekChart: View {
    struct Bar {
        /// Hours later than 11 PM to 7 AM.
        var shift: Double
        var accent: Color = .clear
        var accentAmount: Double = 0
    }

    let bars: [Bar]

    private let days = ["M", "T", "W", "T", "F", "S", "S"]
    private let spanHours = 11.5

    var body: some View {
        GeometryReader { geo in
            let labelWidth: CGFloat = 46
            let plotWidth = geo.size.width - labelWidth
            let hour = (geo.size.height - 22) / spanHours
            let column = plotWidth / 7

            ZStack(alignment: .topLeading) {
                ForEach([(1.0, "11 PM"), (9.0, "7 AM")], id: \.0) { guide in
                    Text(guide.1)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .position(x: labelWidth / 2 - 4, y: guide.0 * hour)
                    Path { path in
                        path.move(to: CGPoint(x: labelWidth, y: guide.0 * hour))
                        path.addLine(to: CGPoint(x: geo.size.width, y: guide.0 * hour))
                    }
                    .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }

                ForEach(Array(bars.enumerated()), id: \.offset) { i, bar in
                    let x = labelWidth + column * (Double(i) + 0.5)
                    Capsule()
                        .fill(Palette.sleep.opacity(0.75))
                        .overlay(Capsule().fill(bar.accent).opacity(bar.accentAmount))
                        .frame(width: column * 0.5, height: 8 * hour)
                        .position(x: x, y: (5 + bar.shift) * hour)
                    Text(days[i])
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .position(x: x, y: geo.size.height - 8)
                }

            }
        }
    }
}

// MARK: - 3. Modern life skips the reset

/// What a weekend sleep-in costs. Thursday and Friday are on time, the weekend slides two hours
/// later, Sunday night you lie awake and Monday's alarm cuts sleep short, then it takes days to recover.
/// Times are hours after 10 PM.
struct SocialJetLagVisual: View {
    let isActive: Bool

    private let days = ["T", "F", "S", "S", "M", "T", "W"]
    private let spanHours = 11.5
    private let cycle = 11.0

    var body: some View {
        StoryClock(isActive: isActive, settled: 6.5) { raw in
            let t = raw.truncatingRemainder(dividingBy: cycle)
            let fade = 1 - Ease.progress(t, from: cycle - 1, duration: 0.5)

            VStack(spacing: 10) {
                legend
                chart(t)
                    .frame(height: 210)
                captions(t)
            }
            .opacity(fade)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Thursday and Friday you sleep 11 PM to 7 AM. On the weekend, sleep slides two hours later. Sunday night you lie awake until 1 AM, and Monday's 7 AM alarm cuts two hours of sleep. Tuesday and Wednesday you slowly recover, then the weekend hits again.")
    }

    private var legend: some View {
        HStack(spacing: 18) {
            Label {
                Text("Asleep")
            } icon: {
                Capsule().fill(Palette.sleep.opacity(0.75)).frame(width: 8, height: 14)
            }
            Label {
                Text("Lying awake")
            } icon: {
                Capsule()
                    .fill(Palette.unfavorable.opacity(0.15))
                    .overlay(Capsule().strokeBorder(Palette.unfavorable, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])))
                    .frame(width: 8, height: 14)
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }

    private func chart(_ t: Double) -> some View {
        let weekdayIn = Ease.progress(t, from: 0.2, duration: 0.5)
        let weekendIn = Ease.progress(t, from: 0.9, duration: 0.4)
        let slide = Ease.progress(t, from: 1.3, duration: 0.9)
        let mondayIn = Ease.progress(t, from: 2.8, duration: 0.3)
        let lyingAwake = Ease.progress(t, from: 3.0, duration: 0.8)
        let mondaySleep = Ease.progress(t, from: 3.8, duration: 0.6)
        let alarm = Ease.progress(t, from: 4.4, duration: 0.35)
        let recoverIn = Ease.progress(t, from: 5.8, duration: 0.6)

        return GeometryReader { geo in
            let labelWidth: CGFloat = 46
            let hour = (geo.size.height - 22) / spanHours
            let column = (geo.size.width - labelWidth) / 7
            let barWidth = column * 0.5
            let x = { (i: Int) in labelWidth + column * (Double(i) + 0.5) }

            ZStack(alignment: .topLeading) {
                ForEach([(1.0, "11 PM"), (9.0, "7 AM")], id: \.0) { guide in
                    Text(guide.1)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .position(x: labelWidth / 2 - 4, y: guide.0 * hour)
                    Path { path in
                        path.move(to: CGPoint(x: labelWidth, y: guide.0 * hour))
                        path.addLine(to: CGPoint(x: geo.size.width, y: guide.0 * hour))
                    }
                    .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }

                // Thursday, Friday: on time.
                ForEach(0..<2, id: \.self) { i in
                    sleepBar(from: 1, to: 9, width: barWidth, hour: hour, x: x(i))
                        .opacity(weekdayIn)
                }
                // Weekend: two hours later.
                ForEach(2..<4, id: \.self) { i in
                    sleepBar(from: 1 + 2 * slide, to: 9 + 2 * slide, width: barWidth, hour: hour, x: x(i),
                             warn: 0.8 * slide)
                        .opacity(weekendIn)
                }
                // Monday: in bed at 11 but awake until 1, then the 7 AM alarm.
                Group {
                    awakeBar(from: 1, to: 1 + 2 * lyingAwake, width: barWidth, hour: hour, x: x(4))
                    sleepBar(from: 3, to: 3 + 6 * mondaySleep, width: barWidth, hour: hour, x: x(4))
                        .opacity(mondaySleep > 0 ? 1 : 0)
                    // Alarm sits under Monday's bar, the badge to its right.
                    HStack(spacing: 4) {
                        Image(systemName: "alarm.fill")
                            .font(.system(size: 15, weight: .bold))
                            .rotationEffect(.degrees(12 * sin(alarm * .pi * 4)))
                            .frame(width: 18)
                        Text("−2 h sleep")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Palette.unfavorable.opacity(0.14), in: Capsule())
                    }
                    .foregroundStyle(Palette.unfavorable)
                    .fixedSize()
                    .scaleEffect(Ease.pop(alarm), anchor: .leading)
                    .opacity(alarm)
                    // About half the row's width, so the alarm lands under the bar.
                    .position(x: x(4) + 41, y: 9 * hour + 14)
                }
                .opacity(mondayIn)
                // Tuesday, Wednesday: slowly recovering.
                ForEach(Array([1.0, 0.5].enumerated()), id: \.offset) { n, awake in
                    let i = 5 + n
                    awakeBar(from: 1, to: 1 + awake, width: barWidth, hour: hour, x: x(i))
                        .opacity(Ease.clamp(recoverIn * 2 - Double(n) * 0.5))
                    sleepBar(from: 1 + awake, to: 9, width: barWidth, hour: hour, x: x(i))
                        .opacity(Ease.clamp(recoverIn * 2 - Double(n) * 0.5))
                }

                ForEach(days.indices, id: \.self) { i in
                    Text(days[i])
                        .font(.caption2.weight(i == 4 ? .heavy : .semibold))
                        .foregroundStyle(i == 4 && alarm > 0.5 ? Palette.unfavorable : .secondary)
                        .position(x: x(i), y: geo.size.height - 8)
                }
            }
        }
    }

    private func sleepBar(from: Double, to: Double, width: CGFloat, hour: CGFloat, x: CGFloat, warn: Double = 0) -> some View {
        let height = max(0, (to - from) * hour)
        return Capsule()
            .fill(Palette.sleep.opacity(0.75))
            .overlay(Capsule().fill(Palette.unfavorable).opacity(warn))
            .frame(width: width, height: height)
            .position(x: x, y: (from + to) / 2 * hour)
    }

    private func awakeBar(from: Double, to: Double, width: CGFloat, hour: CGFloat, x: CGFloat) -> some View {
        let height = max(0, (to - from) * hour - 3)
        return Capsule()
            .fill(Palette.unfavorable.opacity(0.15))
            .overlay(Capsule().strokeBorder(Palette.unfavorable, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])))
            .frame(width: width, height: height)
            .position(x: x, y: (from + to) / 2 * hour - 1.5)
    }

    private func captions(_ t: Double) -> some View {
        let weekend = Ease.progress(t, from: 1.3, duration: 0.4) * (1 - Ease.progress(t, from: 2.5, duration: 0.3))
        let monday = Ease.progress(t, from: 2.9, duration: 0.4) * (1 - Ease.progress(t, from: 5.5, duration: 0.3))
        let recover = Ease.progress(t, from: 5.9, duration: 0.4)
        return ZStack {
            Text("**Weekend:** you sleep in, 2 hours later.")
                .opacity(weekend)
            Text("**Sunday night** you can't fall asleep. **Monday's alarm** cuts your sleep short.")
                .opacity(monday)
            Text("**It takes days to bounce back.** Then the weekend hits again.")
                .opacity(recover)
        }
        .font(.subheadline)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 40)
    }
}

// MARK: - 4. Circadia helps you sync up

/// A mini version of the Today clock: night and day fill in, then the core habits pop onto it.
struct IdealDayVisual: View {
    let isActive: Bool
    private let radius: CGFloat = 100
    private let pins: [(habit: HabitKey, minutes: Double, tint: Color)] = [
        (.consistentWake, 7 * 60, Palette.sleep),
        (.morningLight, 9 * 60, Palette.light),
        (.caffeineCutoff, 14 * 60, Palette.light),
        (.eveningDim, 21 * 60, Palette.sleep),
        (.sleepOpportunity, 23 * 60, Palette.sleep),
    ]

    var body: some View {
        StoryClock(isActive: isActive, settled: 4) { t in
            let draw = Ease.progress(t, from: 0.2, duration: 1.0)
            let style = StrokeStyle(lineWidth: 16, lineCap: .round)

            ZStack {
                Circle().stroke(Palette.track, lineWidth: 16)
                // Awake 7 AM to 11 PM, asleep 11 PM to 7 AM. Rotations start each arc at its clock time.
                Circle()
                    .trim(from: 0, to: 16.0 / 24 * draw)
                    .rotation(.degrees(90 + 360 * 7 / 24))
                    .stroke(Palette.daylightBand.opacity(0.55), style: style)
                Circle()
                    .trim(from: 0, to: 8.0 / 24 * draw)
                    .rotation(.degrees(90 + 360 * 23 / 24))
                    .stroke(Palette.sleep.opacity(0.7), style: style)

                VStack(spacing: 2) {
                    Text("Your ideal day").font(.headline)
                    Text("24 hours").font(.caption).foregroundStyle(.secondary)
                }
                .opacity(draw)

                ForEach(Array(pins.enumerated()), id: \.offset) { i, pin in
                    let pop = Ease.progress(t, from: 1.2 + Double(i) * 0.3, duration: 0.4)
                    Image(systemName: pin.habit.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(pin.tint)
                        .frame(width: 34, height: 34)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().stroke(pin.tint.opacity(0.4), lineWidth: 1))
                        .scaleEffect(Ease.pop(pop))
                        .opacity(pop)
                        .offset(StoryDial.offset(minutes: pin.minutes, radius: radius))
                }

                Text("Noon").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .offset(y: -radius - 30)
                Text("Midnight").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .offset(y: radius + 30)
            }
            .frame(width: radius * 2, height: radius * 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A 24-hour clock showing your ideal day, with habits placed at the best time: wake up, morning light, caffeine cutoff, dim lights, and bedtime.")
    }
}

// MARK: - 5. Small steps, every day

/// The messy week from page 3 straightens out into one steady line.
struct InSyncVisual: View {
    let isActive: Bool
    private let messy: [Double] = [0.4, -0.3, 0.7, 0.1, 0.9, 2.0, 1.7]

    var body: some View {
        StoryClock(isActive: isActive, settled: 3.5) { t in
            let align = Ease.progress(t, from: 0.8, duration: 1.4)
            let badge = Ease.progress(t, from: 2.3, duration: 0.45)

            VStack(spacing: 14) {
                Label("In sync", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.favorable)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Palette.favorable.opacity(0.14), in: Capsule())
                    .scaleEffect(Ease.pop(badge))
                    .opacity(badge)

                SleepWeekChart(bars: messy.map {
                    SleepWeekChart.Bar(shift: $0 * (1 - align), accent: Palette.favorable, accentAmount: 0.7 * align)
                })
                .frame(height: 220)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A week of uneven sleep times lines up into the same time every night. In sync.")
    }
}
