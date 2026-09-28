/// What happened to each photo during the current cycle, for the cycle report
/// and for leaving unavailable photos off their slides.
///
/// Skipped and removed photos are excluded for the rest of the cycle. Showing a
/// photo clears an earlier skip, so a photo that loads on a later try isn't
/// reported as skipped.
struct CycleTracker {
    private(set) var displayed: Set<AssetID> = []
    /// In the order they were skipped.
    private(set) var skipped: [AssetID] = []
    /// In the order they were found missing.
    private(set) var removed: [AssetID] = []
    private var excluded: Set<AssetID> = []

    mutating func recordShown(_ ids: [AssetID]) {
        displayed.formUnion(ids)
        skipped.removeAll { ids.contains($0) }
    }

    /// The user skipped a photo that couldn't be loaded.
    mutating func recordSkipped(_ id: AssetID) {
        if !skipped.contains(id) { skipped.append(id) }
        excluded.insert(id)
    }

    /// The photo was deleted or can no longer be shown.
    mutating func recordRemoved(_ id: AssetID) {
        if !removed.contains(id) { removed.append(id) }
        excluded.insert(id)
    }

    /// Photos among `ids` that were skipped this cycle.
    func skippedIDs(among ids: [AssetID]) -> [AssetID] {
        ids.filter { skipped.contains($0) }
    }

    /// Puts skipped photos back on their slide, e.g. when the user returns to it.
    /// They stay listed as skipped until they're shown.
    mutating func readmit(_ ids: [AssetID]) {
        excluded.subtract(ids)
    }

    /// Photos among `ids` that haven't been skipped or removed this cycle.
    func active(_ ids: [AssetID]) -> [AssetID] {
        ids.filter { !excluded.contains($0) }
    }

    func report(cycle: Int, total: Int) -> CycleReport {
        CycleReport(
            cycle: cycle,
            total: total,
            displayed: displayed.count,
            skippedUnavailable: skipped,
            removedFromLibrary: removed
        )
    }
}
