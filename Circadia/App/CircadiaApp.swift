import BackgroundTasks
import SwiftData
import SwiftUI

/// Dependency container. One instance for the app's lifetime.
@MainActor
final class AppContainer {
    static let shared = AppContainer()

    let settings: AppSettings
    let modelContainer: ModelContainer
    let appModel: AppModel

    private init() {
        settings = AppSettings()
        // SwiftData's default store lives in Application Support, which may not exist on first launch.
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        }
        do {
            modelContainer = try ModelContainer(for: RecommendationRecord.self)
        } catch {
            // Fall back to memory rather than crash; history simply won't persist this session.
            modelContainer = try! ModelContainer(for: RecommendationRecord.self,
                                                 configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        appModel = AppModel(settings: settings, modelContext: modelContainer.mainContext)
    }
}

enum BackgroundRefreshScheduler {
    static let taskIdentifier = "com.circadia.app.refresh"

    /// Ask iOS to wake the app around 4:30 AM to refresh data and reschedule the day's nudges.
    static func scheduleNext(after now: Date = Date(), calendar: Calendar = .current) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        var next = calendar.date(bySettingHour: 4, minute: 30, second: 0, of: now) ?? now
        if next <= now { next = calendar.date(byAdding: .day, value: 1, to: next) ?? now.addingTimeInterval(86_400) }
        request.earliestBeginDate = next
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Unsupported in Simulator and when Background App Refresh is off; the app still
            // refreshes on launch, on foreground, and on HealthKit observer callbacks.
        }
    }

    @MainActor
    static func handle() async {
        await AppContainer.shared.appModel.refresh()
    }
}

@main
struct CircadiaApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let container = AppContainer.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container.appModel)
                .environment(container.settings)
                .modelContainer(container.modelContainer)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { container.appModel.requestRefresh() }
        }
        .backgroundTask(.appRefresh(BackgroundRefreshScheduler.taskIdentifier)) {
            await BackgroundRefreshScheduler.handle()
        }
    }
}
