import Testing
@testable import StillroomCore

@Suite("Vertical pan")
struct VerticalPanPathTests {
    @Test("Consecutive slides drift in opposite directions around the same subject")
    func directions() {
        let up = VerticalPanPath(imageHeight: 2560, viewHeight: 1080, focusY: 0.33, slideIndex: 0, duration: 8)
        let down = VerticalPanPath(imageHeight: 2560, viewHeight: 1080, focusY: 0.33, slideIndex: 1, duration: 8)
        #expect(up.start > up.end)
        #expect(down.start < down.end)
        #expect(up.start == down.end)
        #expect(up.end == down.start)
        #expect(abs(up.offset(at: 0.5) - up.resting) < 0.001)
    }

    @Test("Even short slides and tall photos respect the travel and peak speed limits")
    func speedLimit() {
        for duration in [3.0, 5, 8, 30, 60] {
            let path = VerticalPanPath(imageHeight: 4000, viewHeight: 1080, focusY: nil, slideIndex: 0, duration: duration)
            let distance = abs(path.end - path.start)
            #expect(distance <= 1080 * 0.18 + 0.001)
            #expect(distance * 1.5 / duration <= 1080 * 0.025 + 0.001)
        }
    }

    @Test("Both directions stay within the image at its edges and clamp elapsed time")
    func bounds() {
        for height in [800.0, 1080, 1100, 2560] {
            for focus in [0.0, 0.33, 1] {
                for index in [0, 1] {
                    let path = VerticalPanPath(imageHeight: height, viewHeight: 1080, focusY: focus,
                                               slideIndex: index, duration: 8)
                    let travel = max(0, height - 1080)
                    for progress in [-1.0, 0, 0.5, 1, 2] {
                        #expect(path.offset(at: progress) >= -0.001)
                        #expect(path.offset(at: progress) <= travel + 0.001)
                    }
                    #expect(path.offset(at: -1) == path.start)
                    #expect(abs(path.offset(at: 2) - path.end) < 0.001)
                }
            }
        }
    }
}
