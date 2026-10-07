import Foundation
import UserNotifications

/// Local notifications only. Schedules the planner's nudges and reports dismissals, opens and
/// "Done" taps back to the app so it can back off or mark recommendations as followed.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let identifierPrefix = "circadia.nudge."
    nonisolated static let categoryIdentifier = "circadia.nudge"
    nonisolated static let doneAction = "circadia.done"

    var onDismiss: ((RecommendationKind) -> Void)?
    var onOpen: ((RecommendationKind) -> Void)?
    var onDone: ((RecommendationKind, String?) -> Void)?

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        let done = UNNotificationAction(identifier: Self.doneAction, title: "Done", options: [])
        let category = UNNotificationCategory(identifier: Self.categoryIdentifier, actions: [done], intentIdentifiers: [],
                                              options: [.customDismissAction])
        center.setNotificationCategories([category])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func isAuthorized() async -> Bool {
        let status = await authorizationStatus()
        return status == .authorized || status == .provisional
    }

    /// Replaces all pending Circadia nudges with `nudges`.
    func schedule(_ nudges: [PlannedNudge], calendar: Calendar = .current) async {
        await cancelAll()
        for nudge in nudges {
            let content = UNMutableNotificationContent()
            content.title = nudge.title
            content.body = nudge.body
            content.sound = .default
            content.categoryIdentifier = Self.categoryIdentifier
            content.threadIdentifier = nudge.kind.rawValue
            content.userInfo = ["kind": nudge.kind.rawValue, "recommendationID": nudge.recommendationID]
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: nudge.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: Self.identifierPrefix + nudge.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    func pendingCount() async -> Int {
        await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(Self.identifierPrefix) }.count
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let raw = info["kind"] as? String, let kind = RecommendationKind(rawValue: raw) else { return }
        let recommendationID = info["recommendationID"] as? String
        let action = response.actionIdentifier
        await MainActor.run {
            switch action {
            case UNNotificationDismissActionIdentifier: self.onDismiss?(kind)
            case Self.doneAction: self.onDone?(kind, recommendationID)
            default: self.onOpen?(kind)
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
