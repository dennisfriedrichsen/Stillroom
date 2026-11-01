import SwiftUI
import StillroomCore

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
    var zoomAmount = ZoomAmount.defaultAmount

    /// Duration of a manual (remote-press) slide between photos.
    static let pushSeconds = 0.35

    /// The saved settings, for launches that don't go through the album screen.
    static func stored(in defaults: UserDefaults = .standard) -> TransitionSettings {
        TransitionSettings(
            transition: defaults.string(forKey: SettingsKey.transition).flatMap(SlideTransition.init) ?? .crossfade,
            fadeSpeed: defaults.string(forKey: SettingsKey.fadeSpeed).flatMap(FadeSpeed.init) ?? .gentle,
            kenBurns: defaults.bool(forKey: SettingsKey.kenBurns),
            zoomAmount: ZoomAmount(rawValue: defaults.integer(forKey: SettingsKey.zoomAmount)) ?? .defaultAmount
        )
    }
}

/// Elapsed time that only counts while running.
struct MotionClock {
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
