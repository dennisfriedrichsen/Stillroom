import Foundation

/// Times how long the on-screen slide has been shown, and remembers the time
/// left across a pause. It doesn't decide when a slide should be timed; the
/// controller starts it only while a slide is showing and playback isn't paused.
@MainActor
final class SlideTimer {
    private enum State {
        /// No slide is being timed.
        case idle
        /// Counting down; `endsAt` is on the scheduler's clock.
        case running(endsAt: Duration, work: ScheduledWork)
        /// Paused partway through the slide.
        case paused(remaining: Duration)
    }

    private let scheduler: any Scheduling
    private var state: State = .idle

    init(scheduler: any Scheduling) {
        self.scheduler = scheduler
    }

    var isRunning: Bool {
        if case .running = state { true } else { false }
    }

    /// Times a slide of `duration`, or the rest of it if paused partway through,
    /// then calls `onFire`. Does nothing if already running.
    func start(duration: Duration, onFire: @escaping @MainActor () -> Void) {
        let remaining: Duration
        switch state {
        case .running: return
        case .paused(let left): remaining = left
        case .idle: remaining = duration
        }
        let work = scheduler.schedule(after: remaining) { [weak self] in
            self?.state = .idle
            onFire()
        }
        state = .running(endsAt: scheduler.now + remaining, work: work)
    }

    /// Stops the countdown and keeps the time left. Does nothing unless running.
    func pause() {
        guard case .running(let endsAt, let work) = state else { return }
        work.cancel()
        state = .paused(remaining: max(.zero, endsAt - scheduler.now))
    }

    /// Stops timing and forgets any time left.
    func cancel() {
        if case .running(_, let work) = state {
            work.cancel()
        }
        state = .idle
    }

    /// How far the slide is through `duration`, or nil when no slide is being timed.
    func elapsed(of duration: Duration) -> Duration? {
        switch state {
        case .idle: nil
        case .running(let endsAt, _): duration - max(.zero, endsAt - scheduler.now)
        case .paused(let remaining): duration - remaining
        }
    }
}
