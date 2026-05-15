final class KairoShortTermMemory {
    private var items: [String] = []
    private let limit = 20

    func append(_ s: String) {
        items.append(s)
        if items.count > limit { items.removeFirst(items.count - limit) }
    }

    func recent() -> [String] { items }
}
