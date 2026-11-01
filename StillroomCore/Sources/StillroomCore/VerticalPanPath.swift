/// A short, speed-limited drift around the subject, in screen coordinates.
public struct VerticalPanPath {
    public let start: Double
    public let end: Double
    public let resting: Double

    public init(imageHeight: Double, viewHeight: Double, focusY: Double?, slideIndex: Int, duration: Double) {
        let travel = max(0, imageHeight - viewHeight)
        let target = min(travel, max(0, (focusY ?? 0.33) * imageHeight - viewHeight / 2))
        // Smoothstep peaks at 1.5 times average speed: cap it at 2.5% of screen height per second.
        let distance = min(travel, max(0, viewHeight) * 0.18,
                           max(0, viewHeight) * max(0, duration) * 0.025 / 1.5)
        let low = min(max(0, target - distance / 2), travel - distance)
        let high = low + distance
        start = slideIndex.isMultiple(of: 2) ? high : low
        end = slideIndex.isMultiple(of: 2) ? low : high
        resting = target
    }

    public func offset(at progress: Double) -> Double {
        let t = min(1, max(0, progress))
        return start + (end - start) * t * t * (3 - 2 * t)
    }
}
