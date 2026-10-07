import SwiftUI

struct InsightsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Patterns in your own data: what tends to go with earlier or steadier sleep for you.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    switch app.insights.status {
                    case .notEnoughData(let have, let need):
                        EmptyStateView(systemImage: "hourglass",
                                       title: "Not enough data yet",
                                       message: "Insights need at least \(need) nights so comparisons mean something. You have \(have). Each comparison also needs \(CircadianConfig.insightsMinimumPerGroup)+ days in each group.",
                                       progress: min(1, Double(have) / Double(need)))
                    case .ready where app.insights.insights.isEmpty:
                        EmptyStateView(systemImage: "magnifyingglass",
                                       title: "No clear comparisons yet",
                                       message: "There's enough data overall, but not yet \(CircadianConfig.insightsMinimumPerGroup)+ days on both sides of any comparison. Keep going.")
                    case .ready:
                        ForEach(app.insights.insights) { insight in
                            InsightCard(insight: insight)
                        }
                    }

                    Text("These are associations, not proof of cause. Many things change from day to day, and small samples can mislead.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(SkyBackground())
            .navigationTitle("Insights")
        }
    }
}

struct InsightCard: View {
    let insight: Insight

    private var icon: (String, Color) {
        switch insight.tone {
        case .favorable: ("arrow.down.right.circle.fill", Palette.favorable)
        case .unfavorable: ("arrow.up.right.circle.fill", Palette.unfavorable)
        case .neutral: ("equal.circle.fill", .secondary)
        }
    }

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon.0).font(.title2).foregroundStyle(icon.1).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(insight.headline).font(.headline)
                    Text(insight.detail).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    Text(insight.sampleNote).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let key = insight.mechanismKey {
                        NavigationLink {
                            MechanismDetailView(entry: MechanismLibrary.entry(for: key))
                        } label: {
                            Text("Why this might be").font(.footnote.weight(.semibold))
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
