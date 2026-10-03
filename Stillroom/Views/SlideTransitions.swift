import SwiftUI

/// How one slide gives way to the next when the slideshow advances by itself.
/// Remote presses always slide quickly in the direction pressed.
enum SlideTransition: String, CaseIterable, Identifiable, Sendable {
    case crossfade
    case fadeThroughBlack

    var id: String { rawValue }

    var label: String {
        switch self {
        case .crossfade: "Crossfade"
        case .fadeThroughBlack: "Fade Through Black"
        }
    }
}

/// How long an automatic transition takes.
enum FadeSpeed: String, CaseIterable, Identifiable, Sendable {
    case quick
    case gentle
    case slow

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quick: "Quick"
        case .gentle: "Gentle"
        case .slow: "Slow"
        }
    }

    var seconds: Double {
        switch self {
        case .quick: 0.6
        case .gentle: 1.5
        case .slow: 3
        }
    }
}

/// The transition settings a slideshow plays with.
struct TransitionSettings: Sendable {
    var transition = SlideTransition.crossfade
    var fadeSpeed = FadeSpeed.gentle
    /// Slow zoom on every photo that isn't panning or paired.
    var kenBurns = false

    /// Duration of a manual (remote-press) slide between photos.
    static let pushSeconds = 0.35

    /// The saved settings, for launches that don't go through the album screen.
    static func stored(in defaults: UserDefaults = .standard) -> TransitionSettings {
        TransitionSettings(
            transition: defaults.string(forKey: SettingsKey.transition).flatMap(SlideTransition.init) ?? .crossfade,
            fadeSpeed: defaults.string(forKey: SettingsKey.fadeSpeed).flatMap(FadeSpeed.init) ?? .gentle,
            kenBurns: defaults.bool(forKey: SettingsKey.kenBurns)
        )
    }
}

/// Ken Burns effect: a slow zoom in or out around the photo's subject across the
/// slide's whole time on screen, fades included, so it never stops while visible.
/// Each slide keeps its own clock, so the outgoing slide keeps moving while it
/// fades out. The clock stops while the slideshow is paused.
struct KenBurnsEffect: ViewModifier {
    let zoomsIn: Bool
    let anchor: UnitPoint
    let duration: Double
    let isPaused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = MotionClock()

    static let maxScale = 1.12

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || isPaused)) { context in
            content
                .scaleEffect(reduceMotion ? 1 : scale(at: context.date), anchor: anchor)
        }
        .clipped()
        .onChange(of: isPaused, initial: true) { _, paused in
            clock.setRunning(!paused)
        }
    }

    private func scale(at date: Date) -> Double {
        let progress = duration > 0 ? min(1, clock.elapsed(at: date) / duration) : 1
        let zoom = (Self.maxScale - 1) * progress
        return zoomsIn ? 1 + zoom : Self.maxScale - zoom
    }

    /// Where to zoom: the detected face or subject, else one of a few framings
    /// that varies from slide to slide.
    static func anchor(focus: CGPoint?, slideIndex: Int) -> UnitPoint {
        if let focus {
            return UnitPoint(x: focus.x, y: focus.y)
        }
        let fallbacks: [UnitPoint] = [
            UnitPoint(x: 0.5, y: 0.4),
            UnitPoint(x: 0.3, y: 0.35),
            UnitPoint(x: 0.7, y: 0.4),
            UnitPoint(x: 0.4, y: 0.6),
            UnitPoint(x: 0.65, y: 0.55),
        ]
        return fallbacks[slideIndex % fallbacks.count]
    }
}

/// Elapsed time that only counts while running.
private struct MotionClock {
    private var accumulated: TimeInterval = 0
    private var runningSince: Date?

    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    mutating func setRunning(_ running: Bool) {
        let now = Date()
        if running, runningSince == nil {
            runningSince = now
        } else if !running, let start = runningSince {
            accumulated += now.timeIntervalSince(start)
            runningSince = nil
        }
    }
}
