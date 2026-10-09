import Foundation
import SwiftData

/// Persists what the user reports by hand when there's no wearable: logged nights and outdoor time.
@MainActor
final class SelfReportStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Every logged night, oldest first.
    func all() -> [SleepLog] {
        let descriptor = FetchDescriptor<SleepLogEntry>(sortBy: [SortDescriptor(\.wakeDay)])
        return ((try? context.fetch(descriptor)) ?? []).map(\.value)
    }

    func log(wakeDay: Date, calendar: Calendar = .current) -> SleepLog? {
        entry(id: SleepLogEntry.id(wakeDay: wakeDay, calendar: calendar))?.value
    }

    /// Adds the night, or replaces the one already logged for that wake day.
    func save(_ log: SleepLog, at date: Date, calendar: Calendar = .current) {
        if let existing = entry(id: SleepLogEntry.id(wakeDay: log.wakeDay, calendar: calendar)) {
            existing.onset = log.onset
            existing.wake = log.wake
            existing.loggedAt = date
        } else {
            context.insert(SleepLogEntry(log, loggedAt: date, calendar: calendar))
        }
        try? context.save()
    }

    func delete(wakeDay: Date, calendar: Calendar = .current) {
        guard let existing = entry(id: SleepLogEntry.id(wakeDay: wakeDay, calendar: calendar)) else { return }
        context.delete(existing)
        try? context.save()
    }

    // MARK: - Outdoor light

    /// Every light report, oldest first.
    func lightReports() -> [ReportedLight] {
        let descriptor = FetchDescriptor<LightReport>(sortBy: [SortDescriptor(\.start)])
        return ((try? context.fetch(descriptor)) ?? []).map(\.value)
    }

    func lightReport(id: String) -> ReportedLight? {
        lightEntry(id: id)?.value
    }

    /// Adds the report, or replaces the one with the same id.
    func saveLight(_ light: ReportedLight, id: String, at date: Date) {
        if let existing = lightEntry(id: id) {
            existing.day = light.day
            existing.start = light.start
            existing.end = light.end
            existing.minutes = light.minutes
            existing.reportedAt = date
        } else {
            context.insert(LightReport(id: id, light, reportedAt: date))
        }
        try? context.save()
    }

    func deleteLight(id: String) {
        guard let existing = lightEntry(id: id) else { return }
        context.delete(existing)
        try? context.save()
    }

    func deleteAll() {
        try? context.delete(model: SleepLogEntry.self)
        try? context.delete(model: LightReport.self)
        try? context.save()
    }

    private func entry(id: String) -> SleepLogEntry? {
        var descriptor = FetchDescriptor<SleepLogEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func lightEntry(id: String) -> LightReport? {
        var descriptor = FetchDescriptor<LightReport>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
