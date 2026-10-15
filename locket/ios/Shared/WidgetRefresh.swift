import WidgetKit

enum WidgetRefresh {
    /// The widget fetches the newest friend photo itself; this just asks it to.
    static func now() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
