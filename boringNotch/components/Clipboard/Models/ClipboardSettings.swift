import Foundation
import Defaults

struct ClipboardSettings {
    @Default(.clipboardMaxItems) var maxItems: Int
    @Default(.clipboardSortNewestFirst) var sortNewestFirst: Bool
    @Default(.clipboardGroupByApp) var groupByApp: Bool
    @Default(.clipboardPersistOnQuit) var persistOnQuit: Bool
}
