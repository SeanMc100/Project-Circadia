import SwiftUI

/// The moment-of-action explanation shown after a light recommendation is completed.
struct PayoffView: View {
    let event: PayoffEvent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.skyPhase) private var phase

    var body: some View {
        let content = PayoffContent.make(for: event)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "sun.and.horizon.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Palette.light)
                        .accessibilityHidden(true)
                    Text(content.title)
                        .font(.largeTitle.weight(.semibold))
                    section("What just happened", content.whatHappened)
                    section("What it means for tonight", content.tonight)
                    NavigationLink {
                        MechanismDetailView(entry: MechanismLibrary.entry(for: content.mechanismKey))
                    } label: {
                        Label("Read more about this mechanism", systemImage: "book")
                    }
                }
                .padding(24)
            }
            .background(SkyBackground())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Nice") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title)
            Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
        }
    }
}
