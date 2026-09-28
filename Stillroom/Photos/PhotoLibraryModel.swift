import StillroomCore
import Observation
import Photos

/// An ordinary (non-shared) Photos album and its eligible still-photo count.
struct AlbumSummary: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// Still photos (including Live Photos, shown as stills). Videos are excluded.
    /// Nil while the album is still being counted.
    var photoCount: Int?
    /// Cover photo: the album's key photo in Photos once known, otherwise its
    /// first still photo as a stand-in.
    var keyAssetID: String?
}

/// A folder of albums (and other folders) as organized in Photos.
struct AlbumFolder: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    var items: [LibraryItem]
}

/// One entry in the album browser: an album, or a folder that opens its own grid.
enum LibraryItem: Identifiable, Hashable, Sendable {
    case album(id: String)
    case folder(id: String)

    var id: String {
        switch self {
        case .album(let id): "album:\(id)"
        case .folder(let id): "folder:\(id)"
        }
    }
}

/// Albums and the folder tree they're arranged in.
struct AlbumListing: Sendable {
    var albums: [AlbumSummary]
    /// Items at the top level of My Albums.
    var rootItems: [LibraryItem]
    /// Every non-empty folder, by identifier.
    var folders: [String: AlbumFolder]
}

/// Snapshot of an album's eligible photos taken when a slideshow starts.
struct AlbumSnapshot: Sendable {
    /// Still photos in playback order.
    let ids: [AssetID]
    /// Photos whose stored dimensions are vertical, used for side-by-side pairing.
    let verticalIDs: Set<AssetID>
}

/// Playback order for an album's photos.
enum AlbumOrder: String, CaseIterable, Identifiable, Sendable {
    /// The order PhotoKit returns for the album with no sort descriptors,
    /// which is the album's own order in Photos. Apple does not document this
    /// guarantee, so it must be checked against Photos on a real device.
    case album
    /// Documented fallback when album order is unavailable or unwanted: capture date ascending.
    case oldestFirst
    case newestFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .album: "Album Order"
        case .oldestFirst: "Oldest First"
        case .newestFirst: "Newest First"
        }
    }
}

/// Photos authorization, availability, and album access.
@MainActor
@Observable
final class PhotoLibraryModel {
    enum Access: Equatable {
        case notDetermined
        case authorized
        case limited
        case denied
        case restricted
        case unavailable(String)
    }

    private(set) var access: Access
    private(set) var albums: [AlbumSummary] = [] {
        didSet { albumIndex = Dictionary(albums.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first }) }
    }
    /// Top level of the folder tree, as in My Albums in Photos.
    private(set) var rootItems: [LibraryItem] = []
    private(set) var folders: [String: AlbumFolder] = [:]
    private var albumIndex: [String: Int] = [:]
    private(set) var isLoadingAlbums = false
    private(set) var hasLoadedAlbums = false
    /// Albums whose photo count is known during the current scan.
    private(set) var countedAlbums = 0
    /// Incremented (debounced) whenever the photo library changes.
    private(set) var libraryRevision = 0
    /// While true (during a slideshow), library changes don't trigger a full album
    /// rescan; one runs when the slideshow ends. The slideshow still sees
    /// `libraryRevision` change so it can re-snapshot its own album.
    var defersAlbumRescans = false {
        didSet {
            guard !defersAlbumRescans else { return }
            if rescanPending {
                rescanPending = false
                Task { await loadAlbums() }
            } else if !pendingKeyPhotoIDs.isEmpty {
                refreshKeyPhotos(albumIDs: pendingKeyPhotoIDs)
            }
        }
    }

    private let observer = LibraryObserver()
    private var isObserving = false
    private var changeDebounce: Task<Void, Never>?
    private var rescanPending = false

    /// Key photos by album identifier, persisted so covers are right from launch.
    private var keyPhotos = KeyPhotoStore.load()
    private var keyPhotoTask: Task<Void, Never>?
    /// Albums still to check when a key-photo refresh was paused by a slideshow.
    private var pendingKeyPhotoIDs: [String] = []

    /// Albums are counted in batches so the grid fills in progressively.
    private static let countBatchSize = 12
    /// Key photos are slow to fetch (~0.2 s per album on an Apple TV HD), so they're
    /// fetched in small batches after counting, at low priority.
    private static let keyPhotoBatchSize = 6

    /// Set once the user has pressed Continue on the explanation screen.
    ///
    /// On tvOS 26 (seen on the 26.5 simulator), merely calling
    /// `authorizationStatus(for:)` while the status is undetermined shows the
    /// system prompt, which would cover the explanation screen at launch. Until
    /// the user asks, the app therefore assumes "not determined" without querying.
    private static let hasRequestedAccessKey = "hasRequestedPhotosAccess"
    private var hasRequestedAccess: Bool {
        get { UserDefaults.standard.bool(forKey: Self.hasRequestedAccessKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.hasRequestedAccessKey) }
    }

    init() {
        access = UserDefaults.standard.bool(forKey: Self.hasRequestedAccessKey)
            ? Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
            : .notDetermined
        observer.onChange = { [weak self] in
            Task { @MainActor in self?.libraryDidChange() }
        }
        observer.onUnavailable = { [weak self] reason in
            Task { @MainActor in self?.access = .unavailable(reason) }
        }
        if access == .authorized || access == .limited {
            startObserving()
        }
    }

    /// Shows the system Photos permission prompt (first launch only).
    func requestAccess() async {
        hasRequestedAccess = true
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        access = Self.map(status)
        StillroomLog.library.info("Photos authorization: \(String(describing: self.access))")
        if access == .authorized || access == .limited {
            startObserving()
        }
    }

    /// Re-reads the authorization state, e.g. when returning from Settings.
    func refreshAccess() {
        guard hasRequestedAccess else { return }
        let updated = Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        if case .unavailable = access, updated == .authorized { return }
        access = updated
        if access == .authorized || access == .limited {
            startObserving()
        }
    }

    /// Lists albums immediately, then fills in photo counts and covers in batches.
    /// Concurrent calls are coalesced into one follow-up scan.
    func loadAlbums() async {
        guard access == .authorized || access == .limited else { return }
        guard !isLoadingAlbums else {
            rescanPending = true
            return
        }
        isLoadingAlbums = true
        keyPhotoTask?.cancel()
        pendingKeyPhotoIDs = []
        let clock = ContinuousClock()
        let start = clock.now

        let listing = await BlockingWork.run {
            AlbumFetcher.fetchAlbumList()
        }
        let listed = listing.albums
        // Forget key photos of albums that no longer exist.
        let listedIDs = Set(listed.map(\.id))
        if keyPhotos.keys.contains(where: { !listedIDs.contains($0) }) {
            keyPhotos = keyPhotos.filter { listedIDs.contains($0.key) }
            KeyPhotoStore.save(keyPhotos)
        }
        // Keep counts from a previous scan so a rescan doesn't blank the grid,
        // and show saved key photos straight away.
        let previous = Dictionary(albums.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var merged = listed
        for index in merged.indices {
            let id = merged[index].id
            merged[index].photoCount = previous[id]?.photoCount
            merged[index].keyAssetID = keyPhotos[id] ?? previous[id]?.keyAssetID
        }
        albums = merged
        rootItems = listing.rootItems
        folders = listing.folders
        countedAlbums = 0
        hasLoadedAlbums = true
        let listedAt = clock.now
        StillroomLog.library.info(
            "Listed \(listed.count) albums in \(String(describing: listedAt - start))"
        )

        var timing = AlbumFetcher.Timing()
        let ids = listed.map(\.id)
        for batchStart in stride(from: 0, to: ids.count, by: Self.countBatchSize) {
            let batch = Array(ids[batchStart..<min(batchStart + Self.countBatchSize, ids.count)])
            // Albums with a saved key photo don't need a stand-in cover.
            let needsCover = Set(batch.filter { keyPhotos[$0] == nil })
            let (details, batchTiming) = await BlockingWork.run {
                AlbumFetcher.fetchDetails(albumIDs: batch, coverFor: needsCover)
            }
            timing.add(batchTiming)
            // Assign once per batch so observers (and the index) update once.
            var updated = albums
            for index in updated.indices {
                let id = updated[index].id
                if let detail = details[id] {
                    updated[index].photoCount = detail.count
                    if keyPhotos[id] == nil {
                        updated[index].keyAssetID = detail.keyAssetID
                    }
                }
            }
            albums = updated
            countedAlbums = min(ids.count, batchStart + batch.count)
        }

        StillroomLog.library.info(
            "Counted \(ids.count) albums in \(String(describing: clock.now - listedAt)) (counting \(String(describing: timing.counting)), covers \(String(describing: timing.keyAssets)))"
        )
        isLoadingAlbums = false
        if rescanPending && !defersAlbumRescans {
            rescanPending = false
            await loadAlbums()
            return
        }
        refreshKeyPhotos(albumIDs: ids)
    }

    /// Replaces stand-in covers with each album's key photo from Photos, in display
    /// order, and saves them. Runs after counting; pauses during a slideshow so it
    /// doesn't compete with photo downloads, and resumes when the slideshow ends.
    private func refreshKeyPhotos(albumIDs: [String]) {
        keyPhotoTask?.cancel()
        pendingKeyPhotoIDs = []
        keyPhotoTask = Task { [weak self] in
            let clock = ContinuousClock()
            let start = clock.now
            var changed = 0
            for batchStart in stride(from: 0, to: albumIDs.count, by: Self.keyPhotoBatchSize) {
                guard let self, !Task.isCancelled else { return }
                if self.defersAlbumRescans {
                    self.pendingKeyPhotoIDs = Array(albumIDs[batchStart...])
                    StillroomLog.library.info("Key photos paused with \(self.pendingKeyPhotoIDs.count) albums left")
                    return
                }
                let batch = Array(albumIDs[batchStart..<min(batchStart + Self.keyPhotoBatchSize, albumIDs.count)])
                let results = await BlockingWork.run(qos: .utility) {
                    AlbumFetcher.fetchKeyPhotos(albumIDs: batch)
                }
                guard !Task.isCancelled else { return }
                changed += self.apply(keyPhotos: results)
            }
            StillroomLog.library.info(
                "Checked key photos for \(albumIDs.count) albums in \(String(describing: clock.now - start)) (\(changed) changed)"
            )
        }
    }

    /// Stores fetched key photos and updates covers. Returns how many covers changed.
    private func apply(keyPhotos results: [String: String?]) -> Int {
        var saved = keyPhotos
        for (albumID, keyID) in results {
            saved[albumID] = keyID
        }
        if saved != keyPhotos {
            keyPhotos = saved
            KeyPhotoStore.save(saved)
        }
        var updated = albums
        var changed = 0
        for index in updated.indices {
            let id = updated[index].id
            guard let result = results[id] else { continue }
            // Without a key photo the stand-in stays, unless the album is now empty.
            let cover = result ?? (updated[index].photoCount == 0 ? nil : updated[index].keyAssetID)
            if updated[index].keyAssetID != cover {
                updated[index].keyAssetID = cover
                changed += 1
            }
        }
        if changed > 0 {
            albums = updated
        }
        return changed
    }

    func album(id: String) -> AlbumSummary? {
        albumIndex[id].map { albums[$0] }
    }

    /// Every album inside the folder, including those in subfolders.
    func albums(inFolder folderID: String) -> [AlbumSummary] {
        guard let folder = folders[folderID] else { return [] }
        return folder.items.flatMap { item -> [AlbumSummary] in
            switch item {
            case .album(let id): album(id: id).map { [$0] } ?? []
            case .folder(let id): albums(inFolder: id)
            }
        }
    }

    /// Snapshot of the album's eligible still photos, in playback order.
    /// Returns nil if the album no longer exists.
    func snapshot(forAlbum albumID: String, order: AlbumOrder) async -> AlbumSnapshot? {
        await BlockingWork.run {
            AlbumFetcher.snapshot(albumID: albumID, order: order)
        }
    }

    func assetIDs(forAlbum albumID: String, order: AlbumOrder) async -> [AssetID]? {
        await snapshot(forAlbum: albumID, order: order)?.ids
    }

    private func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        let library = PHPhotoLibrary.shared()
        library.register(observer as any PHPhotoLibraryChangeObserver)
        library.register(observer as any PHPhotoLibraryAvailabilityObserver)
        if let reason = library.unavailabilityReason {
            access = .unavailable(reason.localizedDescription)
        }
    }

    private func libraryDidChange() {
        // iCloud sync delivers frequent bursts of changes, and a full rescan of a
        // large library takes tens of seconds on older Apple TVs; coalesce them.
        changeDebounce?.cancel()
        changeDebounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self else { return }
            self.libraryRevision += 1
            StillroomLog.library.info("Photo library changed (revision \(self.libraryRevision))")
            if self.defersAlbumRescans {
                self.rescanPending = true
            } else {
                await self.loadAlbums()
            }
        }
    }

    private static func map(_ status: PHAuthorizationStatus) -> Access {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .limited: .limited
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }
}

/// Receives PhotoKit notifications on PhotoKit's background queue.
private final class LibraryObserver: NSObject, PHPhotoLibraryChangeObserver, PHPhotoLibraryAvailabilityObserver,
    @unchecked Sendable {
    // Set once during init on the main actor, before registration; read-only afterwards.
    var onChange: (@Sendable () -> Void)?
    var onUnavailable: (@Sendable (String) -> Void)?

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange?()
    }

    func photoLibraryDidBecomeUnavailable(_ photoLibrary: PHPhotoLibrary) {
        let reason = photoLibrary.unavailabilityReason?.localizedDescription ?? "The photo library is unavailable."
        onUnavailable?(reason)
    }
}

/// Saved key-photo identifiers by album identifier. Only local identifiers are
/// stored; the thumbnails themselves come from PhotoKit's own cache.
enum KeyPhotoStore {
    private static let key = "albumKeyPhotos"

    static func load() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    static func save(_ keyPhotos: [String: String]) {
        UserDefaults.standard.set(keyPhotos, forKey: key)
    }
}
