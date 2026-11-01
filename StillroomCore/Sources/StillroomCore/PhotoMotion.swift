public enum ZoomAmount: Int, CaseIterable, Sendable {
    case subtle = 6
    case gentle = 12
    case medium = 18
    case strong = 24
    case dramatic = 30
    case maximum = 40

    public static let defaultAmount = ZoomAmount.medium
    public var extent: Double { Double(rawValue) / 100 }
}

/// Gentle movement relative to a fitted photo rather than a screen-filling crop.
public struct PhotoMotion {
    public struct Frame {
        public let scale: Double
        public let x: Double
        public let y: Double
    }

    public let anchorX: Double
    public let anchorY: Double
    private let variant: Int
    private let zoomExtent: Double

    public init(slideIndex: Int, focusX: Double? = nil, focusY: Double? = nil, zoomAmount: ZoomAmount = .defaultAmount) {
        zoomExtent = zoomAmount.extent
        variant = ((slideIndex % 4) + 4) % 4
        anchorX = min(0.8, max(0.2, focusX ?? 0.5))
        anchorY = min(0.8, max(0.2, focusY ?? 0.5))
    }

    public func frame(at progress: Double) -> Frame {
        let t = min(1, max(0, progress))
        let zoom = variant.isMultiple(of: 2) ? t : 1 - t
        let directions = [(-1.0, -0.6), (0.6, 1.0), (-0.8, 1.0), (1.0, -0.5)]
        let direction = directions[variant]
        let scale = 1 + zoomExtent * zoom
        // Interpolate between valid endpoints so pan speed stays steady too.
        let startZoom = variant.isMultiple(of: 2) ? 0.0 : zoomExtent
        let endZoom = variant.isMultiple(of: 2) ? zoomExtent : 0.0
        func translation(_ amount: Double, anchor: Double) -> Double {
            let start = min(anchor * startZoom, max(-(1 - anchor) * startZoom, -amount))
            let end = min(anchor * endZoom, max(-(1 - anchor) * endZoom, amount))
            return start + (end - start) * t
        }
        return Frame(scale: scale,
                     x: translation(direction.0 * 0.02, anchor: anchorX),
                     y: translation(direction.1 * 0.015, anchor: anchorY))
    }
}
