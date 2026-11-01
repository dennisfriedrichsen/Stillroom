import Foundation

/// Presentation instances have unique identities even when revisiting the same slide.
public struct TransitionLayers<Content> {
    public struct Layer: Identifiable {
        public let id: UUID
        public let key: String
        public let content: Content
        public fileprivate(set) var opacity: Double
        public fileprivate(set) var offset: Double
    }

    public private(set) var layers: [Layer] = []

    public init() {}

    @discardableResult
    public mutating func append(_ content: Content, key: String, opacity: Double, offset: Double = 0) -> UUID {
        let id = UUID()
        layers.append(Layer(id: id, key: key, content: content, opacity: opacity, offset: offset))
        return id
    }

    public func isCurrent(_ id: UUID) -> Bool {
        layers.last?.id == id
    }

    public mutating func setOpacity(_ opacity: Double, of id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[index].opacity = opacity
    }

    public mutating func fadeOut(before id: UUID) {
        guard isCurrent(id) else { return }
        for index in layers.indices where layers[index].id != id {
            layers[index].opacity = 0
        }
    }

    public mutating func pushIn(_ id: UUID, from side: Double) {
        guard isCurrent(id) else { return }
        for index in layers.indices {
            layers[index].offset = layers[index].id == id ? 0 : layers[index].offset - side
        }
    }

    /// An interrupted transition cannot discard layers belonging to its successor.
    public mutating func complete(_ id: UUID) {
        guard isCurrent(id) else { return }
        layers.removeAll { $0.id != id }
    }

    public mutating func removeAll() {
        layers.removeAll()
    }
}
