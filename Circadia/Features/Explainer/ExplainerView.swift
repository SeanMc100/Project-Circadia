import SwiftUI

/// "How Circadia works": a short visual story. Why the body clock matters, why modern life
/// knocks it off, then what Circadia does about it. Opened from the ? button on Today.
struct ExplainerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.skyPhase) private var phase
    @State private var page = 0

    private let pageCount = 5

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            TabView(selection: $page) {
                StoryPage(isActive: page == 0, title: "You have a clock inside you") {
                    BodyClockVisual(isActive: page == 0)
                } detail: {
                    PointList(isActive: page == 0, points: [
                        StoryPoint(icon: "clock.fill", tint: Palette.sleep,
                                   text: "It's called your **circadian rhythm**."),
                        StoryPoint(icon: "sun.max.fill", tint: Palette.light,
                                   text: "It decides when you **feel awake** and when you **get sleepy**."),
                        StoryPoint(icon: "figure.stand", tint: Palette.sleep,
                                   text: "Almost every part of you runs on it, from **hunger** to **mood** to **body temperature**."),
                    ])
                }
                .tag(0)

                StoryPage(isActive: page == 1, title: "Your body runs on a longer day") {
                    DriftVisual(isActive: page == 1)
                } detail: {
                    PointList(isActive: page == 1, points: [
                        StoryPoint(icon: "clock.fill", tint: Palette.sleep,
                                   text: "The world runs on **24-hour days**. Your body's clock runs a bit longer, about **24 hours and 10 minutes**."),
                        StoryPoint(icon: "mountain.2.fill", tint: Palette.sleep,
                                   text: "With no daylight at all, you'd **drift later every day**. People who lived in caves for science really did."),
                        StoryPoint(icon: "sunrise.fill", tint: Palette.light,
                                   text: "**Morning light** pulls you back on time each day. Get too little, and your clock settles **later than your alarm**."),
                    ])
                }
                .tag(1)

                StoryPage(isActive: page == 2, title: "Modern life skips the reset", visualHeight: 296) {
                    SocialJetLagVisual(isActive: page == 2)
                } detail: {
                    PointList(isActive: page == 2, points: [
                        StoryPoint(icon: "building.2.fill", tint: Palette.unfavorable,
                                   text: "**Indoors all day**, your clock misses its morning signal."),
                        StoryPoint(icon: "iphone", tint: Palette.unfavorable,
                                   text: "**Bright screens at night** push it even later."),
                    ])
                    effects
                    healthCallout
                }
                .tag(2)

                StoryPage(isActive: page == 3, title: "Circadia gets you in sync",
                          subtitle: "In sync means your inner clock matches your real day.",
                          footnote: "Uses sleep and daylight from Apple Health. Your data stays on this iPhone.") {
                    IdealDayVisual(isActive: page == 3)
                } detail: {
                    PointList(isActive: page == 3, points: [
                        StoryPoint(icon: "clock.fill", tint: phase.palette.accent,
                                   text: "**Your ideal day** on one clock, with the best time for each habit."),
                        StoryPoint(icon: "bell.badge.fill", tint: phase.palette.accent,
                                   text: "**Nudges at the right moment**, like when to get outside or stop caffeine."),
                        StoryPoint(icon: "chart.line.uptrend.xyaxis", tint: phase.palette.accent,
                                   text: "**See your progress** as your days get more steady."),
                    ])
                }
                .tag(3)

                StoryPage(isActive: page == 4, title: "Small steps, every day",
                          subtitle: "Your clock moves a little each day, so steady habits add up. Start with three:",
                          footnote: "Tap any icon on the Today clock to see why it works.") {
                    InSyncVisual(isActive: page == 4)
                } detail: {
                    PointList(isActive: page == 4, points: [
                        StoryPoint(icon: HabitKey.consistentWake.systemImage, tint: Palette.sleep,
                                   text: "**Wake up at the same time**, even on weekends."),
                        StoryPoint(icon: HabitKey.morningLight.systemImage, tint: Palette.light,
                                   text: "**Get outside in the morning**, even for 10 minutes."),
                        StoryPoint(icon: HabitKey.eveningDim.systemImage, tint: Palette.sleep,
                                   text: "**Keep evenings dim** so sleepiness shows up on time."),
                    ])
                }
                .tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .background(SkyBackground())
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 18) {
            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? phase.palette.accent : Color.primary.opacity(0.18))
                        .frame(width: i == page ? 22 : 7, height: 7)
                }
            }
            .animation(.spring(duration: 0.35), value: page)
            .accessibilityElement()
            .accessibilityLabel("Page \(page + 1) of \(pageCount)")

            Button {
                if page < pageCount - 1 {
                    withAnimation { page += 1 }
                } else {
                    dismiss()
                }
            } label: {
                Text(page < pageCount - 1 ? "Next" : "Got it")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Page 3 extras

    private var effects: some View {
        HStack(spacing: 10) {
            EffectTile(icon: "cloud.fog.fill", text: "Groggy mornings", index: 0, isActive: page == 2)
            EffectTile(icon: "bed.double.fill", text: "Trouble falling asleep", index: 1, isActive: page == 2)
            EffectTile(icon: "battery.25", text: "Low energy and mood", index: 2, isActive: page == 2)
        }
    }

    private var healthCallout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.title3)
                .foregroundStyle(Palette.unfavorable)
                .accessibilityHidden(true)
            Text("Over years, being out of sync is **linked to weight gain, diabetes, and heart disease**.")
                .font(.body)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Palette.unfavorable.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Page layout

/// One page: a large animated visual on top, a short title, then a few big, scannable points.
private struct StoryPage<Visual: View, Detail: View>: View {
    let isActive: Bool
    let title: String
    var subtitle: String?
    var footnote: String?
    var visualHeight: CGFloat
    let visual: Visual
    let detail: Detail

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(isActive: Bool, title: String, subtitle: String? = nil, footnote: String? = nil, visualHeight: CGFloat = 280,
         @ViewBuilder visual: () -> Visual, @ViewBuilder detail: () -> Detail) {
        self.visualHeight = visualHeight
        self.isActive = isActive
        self.title = title
        self.subtitle = subtitle
        self.footnote = footnote
        self.visual = visual()
        self.detail = detail()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                visual
                    .frame(height: visualHeight)
                    .frame(maxWidth: .infinity)

                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Text(title)
                            .font(.title.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                        if let subtitle {
                            Text(subtitle)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .opacity(isActive ? 1 : 0)
                    .offset(y: isActive || reduceMotion ? 0 : 16)
                    .animation(.easeOut(duration: 0.5).delay(0.15), value: isActive)

                    detail

                    if let footnote {
                        Text(footnote)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .opacity(isActive ? 1 : 0)
                            .animation(.easeOut(duration: 0.5).delay(1.0), value: isActive)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

struct StoryPoint {
    let icon: String
    let tint: Color
    let text: LocalizedStringKey
}

/// Big, short bullet points that slide in one after another when the page appears.
private struct PointList: View {
    let isActive: Bool
    let points: [StoryPoint]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: point.icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(point.tint)
                        .frame(width: 38, height: 38)
                        .background(point.tint.opacity(0.14), in: Circle())
                        .accessibilityHidden(true)
                    Text(point.text)
                        .font(.title3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .opacity(isActive ? 1 : 0)
                .offset(x: isActive || reduceMotion ? 0 : 24)
                .animation(.easeOut(duration: 0.4).delay(0.3 + 0.2 * Double(index)), value: isActive)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small tile naming one effect of being out of sync.
private struct EffectTile: View {
    let icon: String
    let text: String
    let index: Int
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Palette.unfavorable)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 84)
        .padding(.horizontal, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .scaleEffect(isActive || reduceMotion ? 1 : 0.85)
        .opacity(isActive ? 1 : 0)
        .animation(.spring(duration: 0.45, bounce: 0.35).delay(0.9 + 0.15 * Double(index)), value: isActive)
    }
}

#Preview {
    ExplainerView()
}
