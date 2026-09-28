import StillroomCore
import Photos

/// Synchronous PhotoKit fetches, run off the main actor. They block, so call them
/// through `BlockingWork`, never directly from `async` code (see the threading rule
/// in the README).
enum AlbumFetcher {
    struct Detail: Sendable {
        let count: Int
        let keyAssetID: String?
    }

    struct Timing: Sendable {
        var counting: Duration = .zero
        var keyAssets: Duration = .zero

        mutating func add(_ other: Timing) {
            counting += other.counting
            keyAssets += other.keyAssets
        }
    }

    /// Album identifiers, titles, and the folder tree (fast). Counts are filled in separately.
    static func fetchAlbumList() -> AlbumListing {
        // Ordinary user albums only. Shared albums use a different subtype and
        // are intentionally excluded.
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        var albums: [AlbumSummary] = []
        collections.enumerateObjects { collection, _, _ in
            albums.append(AlbumSummary(
                id: collection.localIdentifier,
                title: collection.localizedTitle ?? "Untitled Album",
                photoCount: nil,
                keyAssetID: nil
            ))
        }
        // Fallback order for albums the folder walk doesn't reach.
        albums.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        // Walk the folders in My Albums so the browser mirrors them. With no
        // sort descriptors PhotoKit returns each level in the custom order set
        // in Photos. Apple doesn't document this, so check it on a device.
        let albumIDs = Set(albums.map(\.id))
        var folders: [String: AlbumFolder] = [:]
        var placed: Set<String> = []
        var order: [String] = []
        var visited: Set<String> = []
        var rootItems = items(
            in: PHCollectionList.fetchTopLevelUserCollections(with: nil),
            albumIDs: albumIDs,
            folders: &folders,
            placed: &placed,
            order: &order,
            visited: &visited
        )
        // Anything the folder walk didn't reach still appears at the top level.
        for album in albums where !placed.contains(album.id) {
            rootItems.append(.album(id: album.id))
        }
        // Count albums in the order they're shown, so visible cards fill in first.
        let position = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        albums.sort { lhs, rhs in
            let (l, r) = (position[lhs.id] ?? .max, position[rhs.id] ?? .max)
            if l != r { return l < r }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return AlbumListing(albums: albums, rootItems: rootItems, folders: folders)
    }

    /// Albums and non-empty folders in one level of the tree, recursing into folders.
    private static func items(
        in collections: PHFetchResult<PHCollection>,
        albumIDs: Set<String>,
        folders: inout [String: AlbumFolder],
        placed: inout Set<String>,
        order: inout [String],
        visited: inout Set<String>
    ) -> [LibraryItem] {
        var result: [LibraryItem] = []
        for index in 0..<collections.count {
            let collection = collections.object(at: index)
            let id = collection.localIdentifier
            if collection is PHAssetCollection {
                if albumIDs.contains(id), placed.insert(id).inserted {
                    order.append(id)
                    result.append(.album(id: id))
                }
            } else if let list = collection as? PHCollectionList, visited.insert(id).inserted {
                let children = items(
                    in: PHCollection.fetchCollections(in: list, options: nil),
                    albumIDs: albumIDs,
                    folders: &folders,
                    placed: &placed,
                    order: &order,
                    visited: &visited
                )
                // Folders holding only shared albums or empty folders are skipped.
                guard !children.isEmpty else { continue }
                folders[id] = AlbumFolder(id: id, title: list.localizedTitle ?? "Untitled Folder", items: children)
                result.append(.folder(id: id))
            }
        }
        return result
    }

    /// Eligible still-photo count for each album, plus a stand-in cover (its first
    /// still photo) for the albums in `coverFor`.
    ///
    /// Measured on an Apple TV HD with 157 albums: an unfiltered fetch plus
    /// `countOfAssets(with: .image)` took ~4 s in total, versus 20–32 s for a fetch
    /// with a `mediaType` predicate (same counts), and `fetchKeyAssets` took 20–34 s
    /// versus ~3 s for using the album's first photo as its cover. Key photos are
    /// therefore fetched afterwards by `fetchKeyPhotos` and saved between launches.
    static func fetchDetails(albumIDs: [String], coverFor: Set<String>) -> ([String: Detail], Timing) {
        let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: albumIDs, options: nil)
        let clock = ContinuousClock()
        var timing = Timing()
        var details: [String: Detail] = [:]
        collections.enumerateObjects { collection, _, _ in
            let countStart = clock.now
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            let count = assets.countOfAssets(with: .image)
            let coverStart = clock.now
            timing.counting += coverStart - countStart
            var cover: String?
            if count > 0, coverFor.contains(collection.localIdentifier) {
                // First still photo in album order (usually the very first item).
                assets.enumerateObjects { asset, _, stop in
                    if asset.mediaType == .image {
                        cover = asset.localIdentifier
                        stop.pointee = true
                    }
                }
            }
            timing.keyAssets += clock.now - coverStart
            details[collection.localIdentifier] = Detail(count: count, keyAssetID: cover)
        }
        return (details, timing)
    }

    /// Each album's key photo as chosen in Photos, or nil when it has none.
    /// Albums that no longer exist are left out.
    static func fetchKeyPhotos(albumIDs: [String]) -> [String: String?] {
        let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: albumIDs, options: nil)
        var result: [String: String?] = [:]
        collections.enumerateObjects { collection, _, _ in
            let key = PHAsset.fetchKeyAssets(in: collection, options: nil)?.firstObject
            result[collection.localIdentifier] = .some(key?.localIdentifier)
        }
        return result
    }

    static func snapshot(albumID: String, order: AlbumOrder) -> AlbumSnapshot? {
        guard let collection = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumID],
            options: nil
        ).firstObject else {
            return nil
        }
        let options = PHFetchOptions()
        switch order {
        case .album:
            // No sort descriptors and no predicate, so PhotoKit's album order is
            // untouched; videos are filtered out below instead.
            break
        case .oldestFirst:
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        case .newestFirst:
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        }
        let assets = PHAsset.fetchAssets(in: collection, options: options)
        var ids: [AssetID] = []
        var vertical: Set<AssetID> = []
        ids.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            guard asset.mediaType == .image else { return }
            let id = AssetID(asset.localIdentifier)
            ids.append(id)
            // Metadata only; nothing is downloaded.
            if SlideRenderer.isVertical(width: asset.pixelWidth, height: asset.pixelHeight) {
                vertical.insert(id)
            }
        }
        return AlbumSnapshot(ids: ids, verticalIDs: vertical)
    }
}
