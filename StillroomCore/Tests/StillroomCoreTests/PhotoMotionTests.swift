import Testing
@testable import StillroomCore

@Suite("Whole-photo motion")
struct PhotoMotionTests {
    @Test("Motion always covers the fitted photo rectangle without an extra background border", arguments: ZoomAmount.allCases)
    func noBorder(zoom: ZoomAmount) {
        for index in 0..<4 {
            for focus in [0.0, 0.5, 1] {
                let motion = PhotoMotion(slideIndex: index, focusX: focus, focusY: focus, zoomAmount: zoom)
                for step in 0...100 {
                    let frame = motion.frame(at: Double(step) / 100)
                    let left = motion.anchorX * (1 - frame.scale) + frame.x
                    let top = motion.anchorY * (1 - frame.scale) + frame.y
                    #expect(frame.scale >= 1)
                    #expect(left <= 0.000001)
                    #expect(top <= 0.000001)
                    #expect(left + frame.scale >= 0.999999)
                    #expect(top + frame.scale >= 0.999999)
                }
            }
        }
    }

    @Test("Zoom advances by equal amounts across the whole slide", arguments: ZoomAmount.allCases)
    func steadyZoom(zoom: ZoomAmount) {
        for index in 0..<4 {
            let motion = PhotoMotion(slideIndex: index, zoomAmount: zoom)
            let step = motion.frame(at: 0.01).scale - motion.frame(at: 0).scale
            let xStep = motion.frame(at: 0.01).x - motion.frame(at: 0).x
            let yStep = motion.frame(at: 0.01).y - motion.frame(at: 0).y
            for sample in 1...100 {
                let delta = motion.frame(at: Double(sample) / 100).scale
                    - motion.frame(at: Double(sample - 1) / 100).scale
                #expect(abs(delta - step) < 0.000001)
                let current = motion.frame(at: Double(sample) / 100)
                let previous = motion.frame(at: Double(sample - 1) / 100)
                #expect(abs(current.x - previous.x - xStep) < 0.000001)
                #expect(abs(current.y - previous.y - yStep) < 0.000001)
            }
        }
    }

    @Test("Motion alternates zoom direction and varies the pan")
    func variation() {
        for index in 0..<4 {
            let motion = PhotoMotion(slideIndex: index)
            let start = motion.frame(at: 0)
            let end = motion.frame(at: 1)
            #expect(min(start.scale, end.scale) == 1)
            #expect(abs(max(start.scale, end.scale) - 1.18) < 0.000001)
            #expect((end.scale > start.scale) == index.isMultiple(of: 2))
            #expect(start.x != end.x)
            #expect(start.y != end.y)
        }
        #expect(PhotoMotion(slideIndex: 0).frame(at: 1).y < 0)
        #expect(PhotoMotion(slideIndex: 2).frame(at: 1).y > 0)
    }

    @Test("Visible photo area matches the selected zoom limit", arguments: ZoomAmount.allCases)
    func visibleArea(zoom: ZoomAmount) {
        for index in 0..<4 {
            for focus in [0.0, 0.5, 1] {
                let motion = PhotoMotion(slideIndex: index, focusX: focus, focusY: focus, zoomAmount: zoom)
                for step in 0...100 {
                    let frame = motion.frame(at: Double(step) / 100)
                    let left = motion.anchorX * (1 - frame.scale) + frame.x
                    let top = motion.anchorY * (1 - frame.scale) + frame.y
                    let width = min(1, left + frame.scale) - max(0, left)
                    let height = min(1, top + frame.scale) - max(0, top)
                    #expect(width * height / (frame.scale * frame.scale) >= 1 / ((1 + zoom.extent) * (1 + zoom.extent)) - 0.000001)
                }
            }
        }
    }

    @Test("Motion holds at its endpoints while waiting for the next photo")
    func clampedTime() {
        let motion = PhotoMotion(slideIndex: 1)
        #expect(motion.frame(at: -1).scale == motion.frame(at: 0).scale)
        #expect(motion.frame(at: 5).scale == motion.frame(at: 1).scale)
        #expect(motion.frame(at: 5).x == motion.frame(at: 1).x)
        #expect(motion.frame(at: 5).y == motion.frame(at: 1).y)
    }
}
