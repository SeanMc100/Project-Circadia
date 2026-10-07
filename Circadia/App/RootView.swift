import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        TimelineView(.periodic(from: .now, by: 300)) { timeline in
            let phase = SkyPhase.current(at: timeline.date, sun: app.sunWeather?.sun)
            Group {
                if app.settings.hasCompletedOnboarding {
                    MainTabView()
                } else {
                    OnboardingView()
                }
            }
            .sheet(item: $app.payoff) { event in
                PayoffView(event: event)
                    .environment(\.skyPhase, phase)
                    .tint(phase.palette.accent)
            }
            .environment(\.skyPhase, phase)
            .tint(phase.palette.accent)
        }
        .task { app.start() }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.horizon") }
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
            InsightsView()
                .tabItem { Label("Insights", systemImage: "lightbulb") }
            LearnView()
                .tabItem { Label("Learn", systemImage: "book") }
        }
    }
}
