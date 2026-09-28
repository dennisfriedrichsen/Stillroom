import Testing
@testable import StillroomCore

@Suite("SlideTimer")
@MainActor
struct SlideTimerTests {
    let scheduler = ManualScheduler()

    @Test("Pausing keeps the time left; starting again fires after only that much")
    func pauseAndResume() {
        let timer = SlideTimer(scheduler: scheduler)
        var fired = 0
        timer.start(duration: .seconds(8)) { fired += 1 }
        scheduler.advance(by: .seconds(3))
        timer.pause()
        #expect(!timer.isRunning)
        #expect(timer.elapsed(of: .seconds(8)) == .seconds(3))

        scheduler.advance(by: .seconds(20))
        #expect(fired == 0, "a paused timer doesn't fire")
        #expect(timer.elapsed(of: .seconds(8)) == .seconds(3))

        timer.start(duration: .seconds(8)) { fired += 1 }
        scheduler.advance(by: .seconds(4))
        #expect(fired == 0)
        #expect(timer.elapsed(of: .seconds(8)) == .seconds(7))
        scheduler.advance(by: .seconds(1))
        #expect(fired == 1)
        #expect(!timer.isRunning)
        #expect(timer.elapsed(of: .seconds(8)) == nil, "idle after firing")
    }

    @Test("Starting while running doesn't restart or double-schedule")
    func startWhileRunning() {
        let timer = SlideTimer(scheduler: scheduler)
        var fired = 0
        timer.start(duration: .seconds(8)) { fired += 1 }
        scheduler.advance(by: .seconds(5))
        timer.start(duration: .seconds(8)) { fired += 1 }
        scheduler.advance(by: .seconds(3))
        #expect(fired == 1)
        scheduler.advance(by: .seconds(10))
        #expect(fired == 1)
    }

    @Test("Cancelling forgets the time left from a pause")
    func cancelForgetsPause() {
        let timer = SlideTimer(scheduler: scheduler)
        var fired = 0
        timer.start(duration: .seconds(8)) { fired += 1 }
        scheduler.advance(by: .seconds(6))
        timer.pause()
        timer.cancel()
        #expect(timer.elapsed(of: .seconds(8)) == nil)

        timer.start(duration: .seconds(8)) { fired += 1 }
        scheduler.advance(by: .seconds(7))
        #expect(fired == 0, "a fresh start times the full duration")
        scheduler.advance(by: .seconds(1))
        #expect(fired == 1)
    }
}
