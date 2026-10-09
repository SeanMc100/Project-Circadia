import Foundation
import WidgetKit

/// The app's side of the widget contract: write the snapshot, then reload only if it changed.
/// Reloads are the expensive part of a widget, so identical refreshes cost nothing.
enum WidgetBridge {
    static func publish(_ snapshot: WidgetSnapshot) {
        guard WidgetShared.loadSnapshot() != snapshot else { return }
        WidgetShared.saveSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
