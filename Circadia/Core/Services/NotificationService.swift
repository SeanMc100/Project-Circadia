import Foundation
import UserNotifications

/// Local notifications only. Schedules the planner's nudges and reports dismissals, opens and
/// "Done" taps back to the app so it can back off or mark recommendations as followed.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let identifierPrefix = WidgetShared.nudgeIdentifierPrefix
    nonisolated static let categoryIdentifier = "circadia.nudge"
    nonisolated static let doneAction = "circadia.done"
    nonisolated static let sleepLogCategory = "circadia.sleepLog"
    nonisolated static let sleepLogConfirmAction = "circadia.sleepLog.confirm"

    var onDismiss: ((RecommendationKind) -> Void)?
    var onOpen: ((RecommendationKind) -> Void)?
    var onDone: ((RecommendationKind, String?) -> Void)?
    /// "Looks right" on the "Log last night?" reminder, with the times it showed.
    var onSleepLogConfirm: ((SleepLog) -> Void)?

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        let done = UNNotificationAction(identifier: Self.doneAction, title: "Done", options: [])
        let category = UNNotificationCategory(identifier: Self.categoryIdentifier, actions: [done], intentIdentifiers: [],
                                              options: [.customDismissAction])
        // No .foreground option: confirming doesn't open the app.
        let confirm = UNNotificationAction(identifier: Self.sleepLogConfirmAction, title: "Looks right", options: [])
        let sleepLog = UNNotificationCategory(identifier: Self.sleepLogCategory, actions: [confirm], intentIdentifiers: [])
        center.setNotificationCategories([category, sleepLog])
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

    /// Replaces all pending Circadia nudges with `nudges` and the sleep-log reminders.
    func schedule(_ nudges: [PlannedNudge], sleepReminders: [PlannedSleepReminder] = [], calendar: Calendar = .current) async {
        await cancelAll()
        for reminder in sleepReminders {
            let content = UNMutableNotificationContent()
            content.title = "Log last night?"
            content.body = "Asleep around \(ClockMath.timeString(reminder.onset)), up around \(ClockMath.timeString(reminder.wake)). Press and hold for Looks right, or open Circadia to adjust."
            content.sound = .default
            content.categoryIdentifier = Self.sleepLogCategory
            content.threadIdentifier = SleepLogPrompt.kind
            content.userInfo = ["wakeDay": reminder.wakeDay.timeIntervalSince1970,
                                "onset": reminder.onset.timeIntervalSince1970,
                                "wake": reminder.wake.timeIntervalSince1970]
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: Self.identifierPrefix + reminder.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
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
        if response.notification.request.content.categoryIdentifier == Self.sleepLogCategory {
            guard response.actionIdentifier == Self.sleepLogConfirmAction,
                  let day = info["wakeDay"] as? Double, let onset = info["onset"] as? Double, let wake = info["wake"] as? Double else { return }
            let log = SleepLog(wakeDay: Date(timeIntervalSince1970: day), onset: Date(timeIntervalSince1970: onset),
                               wake: Date(timeIntervalSince1970: wake))
            await MainActor.run { self.onSleepLogConfirm?(log) }
            return
        }
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
