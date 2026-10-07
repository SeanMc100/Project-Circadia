import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.skyPhase) private var phase
    @State private var showSettings = false
    @State private var showHowCalculated = false

    var body: some View {
        let vm = TodayViewModel(app: app)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(vm)
                    CircadianRing(model: vm.ring)
                        .frame(maxWidth: 340)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    ringLegend

                    if vm.hasNoData {
                        EmptyStateView(systemImage: "bed.double",
                                       title: "No sleep data yet",
                                       message: "Circadia needs sleep data from Apple Health, ideally from an Apple Watch. You can turn on demo data in Settings to explore the app.")
                    } else if let progress = vm.calibrationProgress {
                        EmptyStateView(systemImage: "hourglass",
                                       title: "Calibrating your baseline",
                                       message: "Your alignment estimate is measured against your own typical timing, which needs \(progress.need) nights. You have \(progress.have). Suggestions below still work.",
                                       progress: Double(progress.have) / Double(progress.need))
                    } else if let score = app.snapshot.score {
                        breakdown(score)
                    }

                    if !vm.cards.isEmpty {
                        SectionLabel("Right now")
                        ForEach(vm.cards) { rec in
                            RecommendationCard(recommendation: rec)
                        }
                    } else if app.hasLoadedOnce {
                        EmptyStateView(systemImage: "moon.zzz", title: "Nothing to do right now",
                                       message: "Your next suggestion will appear when it's relevant.")
                    }

                    SectionLabel("Sun & sky")
                    SunWeatherStrip(snapshot: app.sunWeather, lightWindowText: vm.lightWindowText)

                    if let note = vm.dataSourceNote {
                        Label(note, systemImage: "testtube.2").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let error = app.dataError {
                        Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.secondary)
                    }
                    WellnessNote(compact: true)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(SkyBackground())
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .refreshable { await app.refresh() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showHowCalculated) { NavigationStack { HowCalculatedView() } }
        }
    }

    private func header(_ vm: TodayViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(phase.greeting)
                .font(.title2.weight(.semibold))
            Text(vm.dateTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let travel = app.settings.travelState {
                Label("Travel mode: \(String(format: "%+.0f", travel.shiftHours)) h from home", systemImage: "airplane")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(phase.palette.accent)
                    .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var ringLegend: some View {
        HStack(spacing: 14) {
            legendItem(color: Palette.sleep, text: "Sleep")
            legendItem(color: Palette.light, text: "Outdoor light")
            legendItem(color: Palette.daylightBand.opacity(0.5), text: "Daylight")
            legendItem(color: phase.palette.accent, text: "Light window", dashed: true)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func legendItem(color: Color, text: String, dashed: Bool = false) -> some View {
        HStack(spacing: 4) {
            if dashed {
                Capsule().stroke(color, style: StrokeStyle(lineWidth: 2, dash: [2, 2])).frame(width: 12, height: 4)
            } else {
                Capsule().fill(color).frame(width: 12, height: 5)
            }
            Text(text)
        }
    }

    private func breakdown(_ score: AlignmentScore) -> some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alignment estimate").font(.headline)
                    Text("A proxy from sleep timing and light, not a measurement")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("How?") { showHowCalculated = true }
                    .font(.subheadline.weight(.medium))
                    .accessibilityLabel("How this is calculated")
            }
            ForEach(score.components) { component in
                ComponentBar(component: component)
            }
            if let jetlag = app.snapshot.socialJetlag {
                Divider()
                HStack {
                    Text("Social jetlag (4 weeks)").font(.subheadline)
                    Spacer()
                    Text(jetlag >= 0 ? "\(ClockMath.durationString(jetlag)) later on weekends" : "\(ClockMath.durationString(jetlag)) earlier on weekends")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
