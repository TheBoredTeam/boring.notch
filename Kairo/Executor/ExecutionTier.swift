enum ExecutionTier: Int, Comparable {
    case native = 1, browserExtension = 2, uiAutomation = 3
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}
