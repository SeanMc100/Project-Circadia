import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.skyPhase) private var phase
    @State private var showSettings = false
    @State private var showHowCalculated = false
    @State private var showExplainer = false
    @State private var selectedPin: RingModel.Pin?

    var body: some View {
        let vm = TodayViewModel(app: app)
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    header(vm)
                    let ring = vm.ring
                    CircadianRing(model: ring) { habit in
                        selectedPin = ring.pins.first { $0.habit == habit }
                    }
                    .frame(maxWidth: 360)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    ringCaption

                    if let prompt = app.sleepLogPrompt {
                        if let since = app.sleepLogGapSince {
                            SleepLogCard(prompt: prompt, title: "No sleep from your watch lately",
                                         subtitle: "The last night in Apple Health ended \(since.formatted(.dateTime.weekday(.wide))). Log last night yourself so your estimate stays current.")
                        } else {
                            SleepLogCard(prompt: prompt)
                        }
                    }
                    if let missed = app.missedSleepLog {
                        SleepLogCard(prompt: missed, title: "Missed: \(vm.nightName(missed.wakeDay))",
                                     subtitle: "Add it if you remember roughly, so your estimate has no gap.")
                    }

                    if vm.hasNoData {
                        if vm.isPhoneOnly {
                            EmptyStateView(systemImage: "bed.double",
                                           title: "Log your first night",
                                           message: "Circadia estimates your rhythm from when you sleep. Log each morning and your alignment estimate appears after \(CircadianConfig.baselineMinimumNights + 1) nights. The suggestions below already work.")
                        } else {
                            EmptyStateView(systemImage: "bed.double",
                                           title: "No sleep data yet",
                                           message: "Circadia reads sleep from Apple Health: an Apple Watch, another tracker or a sleep app. Don't wear one? Log your sleep each morning instead.",
                                           actionTitle: "Log my sleep instead") { app.setTrackingMode(.phoneOnly) }
                        }
                    } else if let progress = vm.calibrationProgress {
                        EmptyStateView(systemImage: "hourglass",
                                       title: "Calibrating your baseline",
                                       message: "Your alignment estimate is measured against your own typical timing, which needs \(progress.need) nights. You have \(progress.have)\(vm.isPhoneOnly ? " logged" : ""). Suggestions below still work.",
                                       progress: Double(progress.have) / Double(progress.need))
                    } else if let score = app.snapshot.score {
                        breakdown(score)
                    }

                    if let recap = app.recap {
                        RecapEntryCard(recap: recap)
                    } else if !app.checkIn.isEmpty {
                        // No recap yet (sleep not in, or still calibrating): ask here instead.
                        SectionLabel("Last night")
                        CheckInCard(items: app.checkIn)
                    }

                    if !vm.cards.isEmpty || !app.completedToday.isEmpty {
                        SectionLabel("Right now")
                        ForEach(vm.cards) { rec in
                            RecommendationCard(recommendation: rec)
                                .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.95).combined(with: .opacity)))
                        }
                        if vm.cards.isEmpty {
                            Text("Nothing else right now. Your next suggestion will appear when it's relevant.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(app.completedToday) { item in
                            CompletedRecommendationRow(item: item)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    } else if app.hasLoadedOnce {
                        EmptyStateView(systemImage: "moon.zzz", title: "Nothing to do right now",
                                       message: "Your next suggestion will appear when it's relevant.")
                    }

                    if let forecast = app.forecast {
                        SectionLabel("Tomorrow")
                        ForecastCard(forecast: forecast)
                    }

                    SectionLabel("Sun & sky")
                    SunWeatherStrip(snapshot: app.sunWeather, lightWindowText: vm.lightWindowText)

                    if let error = app.dataError {
                        Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .containerRelativeFrame(.horizontal)
                .animation(.easeInOut(duration: 0.3), value: app.completedToday)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .background(SkyBackground())
            .navigationTitle("Today")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showExplainer = true } label: { Image(systemName: "questionmark.circle") }
                        .accessibilityLabel("How Circadia works")
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .refreshable { await app.refresh() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .fullScreenCover(isPresented: $showExplainer) { ExplainerView() }
            .sheet(item: $selectedPin) { pin in HabitDetailSheet(habit: pin.habit, timeText: pin.timeText) }
            .sheet(isPresented: $showHowCalculated) { NavigationStack { HowCalculatedView(score: app.snapshot.score, socialJetlag: app.snapshot.socialJetlag) } }
        }
    }

    private func header(_ vm: TodayViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(phase.greeting)
                .font(.title2.weight(.semibold))
            HStack(spacing: 8) {
                Text(vm.dateTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if vm.isDemoData { Pill(text: "Demo data", tint: .secondary) }
            }
            if let travel = app.settings.travelState {
                Label("Travel mode: \(String(format: "%+.0f", travel.shiftHours)) h from home", systemImage: "airplane")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(phase.palette.accent)
                    .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var ringCaption: some View {
        Text("Your ideal day. Tap an icon to see when and why.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private func breakdown(_ score: AlignmentScore) -> some View {
        let lowest = score.components.filter { $0.value != nil }.min { ($0.value ?? 1) < ($1.value ?? 1) }
        let lightWhen = (app.snapshot.morningLight?.isToday ?? false) ? "this morning's" : "yesterday morning's"
        let hasLight = score.components.contains { $0.kind == .morningLight && $0.value != nil }
        return Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alignment estimate").font(.headline)
                    if let lowest, let value = lowest.value {
                        Text("Lowest: \(lowest.kind.title) (\(Int((value * 100).rounded())))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Details") { showHowCalculated = true }
                    .font(.subheadline.weight(.medium))
                    .accessibilityLabel("How this is calculated")
            }
            if let trend = weeklyTrend {
                Text(trend.text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(trend.color)
            }
            if let provisional = TodayViewModel(app: app).provisionalProgress {
                Label("Provisional: uses your usual sleep times until you've logged \(provisional.need) nights (\(provisional.have) so far).",
                      systemImage: "hourglass")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Looks back over your last \(CircadianConfig.consistencyWindowNights) nights for consistency, compares last night with your \(CircadianConfig.baselineWindowNights)-night baseline\(hasLight ? ", and uses \(lightWhen) light" : ""). \(app.latestNightIsLogged ? "Sleep times come from your sleep log. " : "")See Trends for history.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 7-day average now vs a week earlier.
    private var weeklyTrend: (text: String, color: Color)? {
        let window = CircadianConfig.scoreTrendWindowDays
        let smoothed = ScoreTrends.smoothed(app.scoreHistory)
        guard let now = smoothed.last,
              let weekAgo = Calendar.current.date(byAdding: .day, value: -window, to: now.day),
              let then = ScoreTrends.smoothedValue(smoothed, onOrBefore: weekAgo) else { return nil }
        let avg = Int(now.value.rounded())
        let change = Int((now.value - then.value).rounded())
        if change == 0 { return ("\(window)-day average \(avg), steady vs last week", .secondary) }
        return ("\(window)-day average \(avg), \(change > 0 ? "▲" : "▼") \(abs(change)) vs last week",
                change > 0 ? Palette.favorable : Palette.unfavorable)
    }
}
