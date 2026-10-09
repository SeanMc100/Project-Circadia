import Foundation

/// Sample content for Xcode previews and the widget gallery before the app has run.
extension WidgetSnapshot {
    static var preview: WidgetSnapshot {
        let now = Date.now
        func item(_ kind: String, _ label: String, _ title: String, _ detail: String?, _ image: String, light: Bool) -> FocusItem {
            FocusItem(id: "\(kind)-preview", kind: kind, label: label, title: title, detail: detail,
                      systemImage: image, isLight: light, canComplete: true)
        }
        let light = item("morningLight", "Morning light", "Go outside now for about 15 minutes", "Until 9:10 AM",
                         "sunrise.fill", light: true)
        let caffeine = item("caffeineCutoff", "Caffeine cutoff", "Last caffeine by 1:00 PM", nil,
                            "cup.and.saucer.fill", light: false)
        let windDown = item("windDown", "Evening wind-down", "Start dimming the lights", "Bedtime 10:45 PM",
                            "lamp.desk.fill", light: false)
        return WidgetSnapshot(
            generatedAt: now,
            alignment: Alignment(value: 62, band: "Fair", components: [
                Component(kind: "consistency", title: "Consistency", value: 0.66),
                Component(kind: "morningLight", title: "Morning light", value: 0.29),
                Component(kind: "drift", title: "Timing drift", value: 1.0),
            ]),
            statusText: nil,
            focus: [
                FocusEntry(start: now.addingTimeInterval(-600), items: [light, caffeine]),
                FocusEntry(start: now.addingTimeInterval(4 * 3600), items: [caffeine]),
                FocusEntry(start: now.addingTimeInterval(10 * 3600), items: [windDown]),
            ],
            validUntil: now.addingTimeInterval(86_400))
    }

    static var calibratingPreview: WidgetSnapshot {
        var snapshot = preview
        snapshot.alignment = nil
        snapshot.statusText = "Calibrating · 3 of 5 nights"
        return snapshot
    }
}
