import Testing
@testable import StillroomCore

@Suite("CycleTracker")
struct CycleTrackerTests {
    let a = AssetID("a"), b = AssetID("b"), c = AssetID("c")

    @Test("Skipped and removed photos leave their slides; the report lists each once")
    func skipAndRemove() {
        var tracker = CycleTracker()
        tracker.recordShown([a])
        tracker.recordSkipped(b)
        tracker.recordSkipped(b)
        tracker.recordRemoved(c)
        tracker.recordRemoved(c)
        #expect(tracker.active([a, b, c]) == [a])

        let report = tracker.report(cycle: 2, total: 3)
        #expect(report == CycleReport(cycle: 2, total: 3, displayed: 1, skippedUnavailable: [b], removedFromLibrary: [c]))
    }

    @Test("A readmitted photo is back on its slide but stays skipped until shown")
    func readmitThenShow() {
        var tracker = CycleTracker()
        tracker.recordSkipped(a)
        tracker.recordSkipped(b)
        #expect(tracker.skippedIDs(among: [a, c]) == [a])

        tracker.readmit([a])
        #expect(tracker.active([a, b]) == [a])
        #expect(tracker.skipped == [a, b])

        tracker.recordShown([a])
        #expect(tracker.skipped == [b])
        #expect(tracker.report(cycle: 1, total: 2).displayed == 1)
    }
}
