#if DEBUG
import StillroomCore
import SwiftUI

/// DEBUG-only album screen for checking its layout and focus in the simulator,
/// which has no iCloud Photos library. Launch with `-demoAlbumScreen` for a fresh
/// album, and add `-demoResume` for one left part way through. Play shows a
/// placeholder instead of a slideshow.
struct DemoAlbumScreen: View {
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-demoAlbumScreen")
    private static let album = AlbumSummary(id: "demo-album", title: "Summer in Maine", photoCount: 392, keyAssetID: nil)

    @Environment(PlaybackRouter.self) private var router
    @State private var recents = Self.makeRecents()

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            AlbumDetailView(album: Self.album)
        }
        .environment(recents)
        .fullScreenCover(item: $router.request) { request in
            VStack(spacing: 30) {
                Text("Demo: would play “\(request.album.title)”")
                    .font(.title2.bold())
                Text(request.resume.map { "Resuming from Photo \($0.position + 1)" } ?? "From the beginning")
                Button("Close") { router.request = nil }
            }
        }
    }

    /// A throwaway store, so the demo never touches the real Recently Played list.
    private static func makeRecents() -> RecentPlaybackStore {
        let suite = "Stillroom.demoAlbumScreen"
        UserDefaults().removePersistentDomain(forName: suite)
        let store = RecentPlaybackStore(defaults: UserDefaults(suiteName: suite)!)
        if ProcessInfo.processInfo.arguments.contains("-demoResume") {
            let resume = ResumePoint(
                assetID: "demo-128", position: 127, total: 392,
                albumOrder: .album, shuffled: false, seed: 0
            )
            store.record(albumID: album.id, resume: resume)
        }
        return store
    }
}
#endif
