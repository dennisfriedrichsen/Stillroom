import Testing
@testable import StillroomCore

@Suite("Transition layers")
struct TransitionLayersTests {
    @Test("Next then Previous retains only the new instance of the original slide")
    func reversedPush() {
        var state = TransitionLayers<String>()
        let original = state.append("A", key: "A", opacity: 1)
        let next = state.append("B", key: "B", opacity: 1, offset: 1)
        state.pushIn(next, from: 1)
        #expect(state.layers.map(\.offset) == [-1, 0])

        let returning = state.append("A", key: "A", opacity: 1, offset: -1)
        state.pushIn(returning, from: -1)
        #expect(Set(state.layers.map(\.id)).count == 3)
        #expect(original != returning)
        #expect(state.layers.map(\.offset) == [0, 1, 0])
        state.complete(next)
        #expect(state.layers.count == 3)
        state.complete(returning)
        #expect(state.layers.map(\.id) == [returning])
    }

    @Test("Crossfade targets the returning instance and preserves the outgoing layer")
    func returningCrossfade() {
        var state = TransitionLayers<String>()
        state.append("A", key: "A", opacity: 1)
        let next = state.append("B", key: "B", opacity: 0)
        state.setOpacity(1, of: next)
        let returning = state.append("A", key: "A", opacity: 0)
        #expect(state.layers.map(\.opacity) == [1, 1, 0])
        state.setOpacity(1, of: returning)
        #expect(state.layers.map(\.opacity) == [1, 1, 1])
        state.complete(next)
        #expect(state.layers.count == 3)
        state.complete(returning)
        #expect(state.layers.map(\.id) == [returning])
    }

    @Test("An interrupted black fade cannot resume when its slide is revisited")
    func interruptedBlackFade() {
        var state = TransitionLayers<String>()
        state.append("A", key: "A", opacity: 1)
        let firstB = state.append("B", key: "B", opacity: 0)
        state.fadeOut(before: firstB)
        #expect(state.layers.map(\.opacity) == [0, 0])

        let c = state.append("C", key: "C", opacity: 1, offset: 1)
        state.pushIn(c, from: 1)
        let secondB = state.append("B", key: "B", opacity: 0)
        state.fadeOut(before: secondB)
        // The view gates the second half of the fade with this check.
        #expect(!state.isCurrent(firstB))
        state.complete(firstB)
        state.complete(c)
        #expect(state.layers.count == 4)
        state.setOpacity(1, of: secondB)
        #expect(state.layers.map(\.opacity) == [0, 0, 0, 1])
        state.complete(secondB)
        #expect(state.layers.map(\.id) == [secondB])
    }

    @Test("Completed black fade leaves only the fully visible incoming layer")
    func blackFade() {
        var state = TransitionLayers<String>()
        state.append("A", key: "A", opacity: 1)
        let b = state.append("B", key: "B", opacity: 0)
        state.fadeOut(before: b)
        #expect(state.layers.map(\.opacity) == [0, 0])
        #expect(state.isCurrent(b))
        state.setOpacity(1, of: b)
        state.complete(b)
        #expect(state.layers.map(\.id) == [b])
        #expect(state.layers.map(\.opacity) == [1])
    }

    @Test("Completions from before reset cannot affect a new presentation of the same slide")
    func resetDuringTransition() {
        var state = TransitionLayers<String>()
        let old = state.append("A", key: "A", opacity: 0)
        state.removeAll()
        let current = state.append("A", key: "A", opacity: 1)
        state.setOpacity(0, of: old)
        state.complete(old)
        #expect(!state.isCurrent(old))
        #expect(state.layers.map(\.id) == [current])
        #expect(state.layers.map(\.opacity) == [1])
    }
}
