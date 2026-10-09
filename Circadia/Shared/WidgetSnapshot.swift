import Foundation

// Compiled into both the app and the widget extension. The app computes everything; the widget
// only reads this file, so it never touches HealthKit or runs the engines itself.

/// Everything the widgets display, written by the app to the shared App Group container.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct Component: Codable, Equatable, Sendable {
        /// `ScoreComponentKind` raw value.
        let kind: String
        let title: String
        /// 0...1, or nil when unavailable.
        let value: Double?
    }

    struct Alignment: Codable, Equatable, Sendable {
        let value: Int
        let band: String
        let components: [Component]
    }

    /// One recommendation as the widget shows it.
    struct FocusItem: Codable, Equatable, Hashable, Sendable {
        /// The recommendation's stable per-day id, e.g. "caffeineCutoff-2026-10-07".
        let id: String
        /// `RecommendationKind` raw value.
        let kind: String
        let label: String
        let title: String
        let detail: String?
        let systemImage: String
        let isLight: Bool
        let canComplete: Bool
        /// Set on a "Last night" sleep-log question: the guessed times the check confirms.
        var sleepOnset: Date? = nil
        var sleepWake: Date? = nil

        var isSleepLog: Bool { kind == WidgetShared.sleepLogKind }
    }

    /// From `start` until the next entry, these recommendations are on screen, most important first.
    struct FocusEntry: Codable, Equatable, Sendable {
        let start: Date
        let items: [FocusItem]
    }

    /// When the snapshot was written. Ignored by `==` so identical content never triggers a reload.
    var generatedAt: Date
    var alignment: Alignment?
    /// Shown in place of the score when there isn't one yet, e.g. "Calibrating · 3 of 5 nights".
    var statusText: String?
    var focus: [FocusEntry]
    /// After this the precomputed plan has run out; the widget asks the user to open the app.
    var validUntil: Date

    static func == (lhs: WidgetSnapshot, rhs: WidgetSnapshot) -> Bool {
        lhs.alignment == rhs.alignment && lhs.statusText == rhs.statusText
            && lhs.focus == rhs.focus && lhs.validUntil == rhs.validUntil
    }

    static let empty = WidgetSnapshot(generatedAt: .distantPast, alignment: nil, statusText: "Open Circadia to get started",
                                      focus: [], validUntil: .distantPast)
}

/// A recommendation checked off from a widget, waiting for the app to record it.
struct WidgetCompletion: Codable, Equatable, Sendable {
    let id: String
    /// `RecommendationKind` raw value.
    let kind: String
    let completedAt: Date
    /// For a confirmed sleep-log question: the times that were shown.
    var sleepOnset: Date? = nil
    var sleepWake: Date? = nil
}

/// Reads and writes the App Group files shared by the app and the widgets.
enum WidgetShared {
    static let appGroup = "group.com.projectcircadia.app"
    static let alignmentKind = "CircadiaAlignment"
    static let focusKind = "CircadiaFocus"
    /// Focus item kind for "Last night" sleep-log questions (not a recommendation).
    static let sleepLogKind = "sleepLog"
    /// Pending nudges are "<prefix><recommendation id>", so a widget check-off can cancel its nudge.
    static let nudgeIdentifierPrefix = "circadia.nudge."

    private static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    private static var snapshotURL: URL? { container?.appendingPathComponent("widget-snapshot.json") }
    private static var completionsURL: URL? { container?.appendingPathComponent("widget-completions.json") }

    // MARK: Snapshot (app writes, widget reads)

    static func loadSnapshot() -> WidgetSnapshot? {
        read(WidgetSnapshot.self, from: snapshotURL)
    }

    static func saveSnapshot(_ snapshot: WidgetSnapshot) {
        write(snapshot, to: snapshotURL)
    }

    // MARK: Completions (widget writes, app drains)

    static func loadCompletions() -> [WidgetCompletion] {
        read([WidgetCompletion].self, from: completionsURL) ?? []
    }

    static func addCompletion(_ completion: WidgetCompletion) {
        // Anything older than two days can no longer be applied.
        let cutoff = completion.completedAt.addingTimeInterval(-2 * 86_400)
        updateCompletions { all in
            (all.filter { $0.id != completion.id } + [completion]).filter { $0.completedAt > cutoff }
        }
    }

    static func removeCompletions(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        updateCompletions { $0.filter { !ids.contains($0.id) } }
    }

    /// Read-modify-write of the completions file, coordinated so the app draining it and the widget
    /// adding to it (separate processes) can't overwrite each other's changes.
    private static func updateCompletions(_ transform: ([WidgetCompletion]) -> [WidgetCompletion]) {
        guard let url = completionsURL else { return }
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &error) { url in
            write(transform(read([WidgetCompletion].self, from: url) ?? []), to: url)
        }
    }

    // MARK: Files

    private static func read<T: Decodable>(_ type: T.Type, from url: URL?) -> T? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL?) {
        guard let url, let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
