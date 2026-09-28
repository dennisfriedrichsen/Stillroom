import StillroomCore
import SwiftUI

/// Album details, the Play button, and the slideshow settings (shared by every album).
struct AlbumDetailView: View {
    let album: AlbumSummary

    @Environment(PhotoLibraryModel.self) private var library
    @Environment(RecentPlaybackStore.self) private var recents
    @Environment(PlaybackRouter.self) private var router
    @AppStorage(SettingsKey.slideSeconds) private var slideSeconds = SettingsDefault.slideSeconds
    @AppStorage(SettingsKey.shuffle) private var shuffle = false
    @AppStorage(SettingsKey.loop) private var loop = true
    @AppStorage(SettingsKey.showCounter) private var showCounter = true
    @AppStorage(SettingsKey.albumOrder) private var albumOrder = AlbumOrder.album
    @AppStorage(SettingsKey.verticalStyle) private var verticalStyle = VerticalPhotoStyle.defaultStyle
    @FocusState private var playFocused: Bool

    private var current: AlbumSummary {
        library.album(id: album.id) ?? album
    }

    private var resume: ResumePoint? {
        recents.entry(for: current.id)?.resume
    }

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            VStack(alignment: .leading, spacing: 30) {
                AlbumThumbnail(assetID: current.keyAssetID)
                    .frame(width: 720, height: 405)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Text(current.title)
                    .font(.title2.bold())
                Text("\(photoCountText(current.photoCount)) · videos are not included")
                    .foregroundStyle(.secondary)
                playButtons
            }
            // Full-height focus section: pressing left from any settings row lands
            // on Play, not just from rows level with the button.
            .frame(width: 720, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .focusSection()

            Form {
                Section {
                    Toggle("Shuffle", isOn: $shuffle)
                    ChoicePicker("Order", selection: $albumOrder, options: AlbumOrder.allCases) { $0.label }
                    .disabled(shuffle)
                    Toggle("Loop", isOn: $loop)
                    ChoicePicker("Slide Duration", selection: $slideSeconds, options: SettingsDefault.durations) {
                        "\($0) seconds"
                    }
                    Toggle("Show “Photo 12 of 600”", isOn: $showCounter)
                } header: {
                    Text("Slideshow Settings · All Albums")
                }
                Section {
                    ChoicePicker("Vertical Photos", selection: $verticalStyle, options: VerticalPhotoStyle.allCases) {
                        $0.label
                    }
                } footer: {
                    Text(verticalStyle.explanation)
                }
                Section {
                    NavigationLink("Troubleshooting") {
                        TroubleshootingView(album: current)
                    }
                }
            }
        }
        .padding(60)
        .defaultFocus($playFocused, true)
        // Play/Pause on the remote starts (or resumes) from anywhere on this screen,
        // including the settings rows.
        .onPlayPauseCommand {
            guard current.photoCount != 0 else { return }
            play(resume: resume)
        }
    }

    @ViewBuilder
    private var playButtons: some View {
        if let resume {
            Button {
                play(resume: resume)
            } label: {
                Label("Resume from Photo \((resume.position + 1).formatted())", systemImage: "play.fill")
                    .frame(minWidth: 420)
            }
            .buttonStyle(.borderedProminent)
            .focused($playFocused)
            ResumeProgressBar(fraction: resume.fraction)
                .frame(width: 420)
            Button {
                play(resume: nil)
            } label: {
                Label("Start Over", systemImage: "arrow.counterclockwise")
                    .font(.callout)
            }
            .buttonStyle(.bordered)
        } else {
            Button {
                play(resume: nil)
            } label: {
                Label("Play Slideshow", systemImage: "play.fill")
                    .frame(minWidth: 420)
            }
            .buttonStyle(.borderedProminent)
            .disabled(current.photoCount == 0)
            .focused($playFocused)
        }
    }

    private func play(resume: ResumePoint?) {
        router.request = SlideshowRequest(album: current, resume: resume)
    }
}

/// Tools for checking iCloud loading and playback on this Apple TV.
struct TroubleshootingView: View {
    let album: AlbumSummary
    @AppStorage(SettingsKey.showDiagnostics) private var showDiagnostics = false

    var body: some View {
        Form {
            Section {
                NavigationLink("Test iCloud Loading") {
                    CloudProbeView(album: album)
                }
            } footer: {
                Text("Checks 12 photos from “\(album.title)” and reports how long the ones not on this Apple TV take to download.")
            }
            Section {
                Toggle("Diagnostics Overlay", isOn: $showDiagnostics)
            } footer: {
                Text("Shows loading, memory, and network details on the Albums screen and during slideshows.")
            }
        }
        .navigationTitle("Troubleshooting")
        .padding(.horizontal, 300)
    }
}

/// Runs the on-device iCloud loading check for one album.
struct CloudProbeView: View {
    let album: AlbumSummary
    @Environment(PhotoLibraryModel.self) private var library
    @State private var probe = CloudProbe()

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text("Test iCloud Loading")
                .font(.title2.bold())
            Text(
                "Samples 12 photos spread across “\(album.title)”, checks whether each is already on this Apple TV "
                    + "at screen size, and downloads the ones that aren’t. Nothing is saved."
            )
            .foregroundStyle(.secondary)
            Text(probe.summary)
                .font(.headline)
            List(probe.rows) { row in
                HStack {
                    Text("Photo \(row.position)")
                        .frame(width: 260, alignment: .leading)
                    Text(row.local)
                        .frame(width: 300, alignment: .leading)
                        .foregroundStyle(.secondary)
                    Text(row.download)
                }
            }
        }
        .padding(60)
        .task {
            let ids = await library.assetIDs(forAlbum: album.id, order: .album) ?? []
            await probe.run(ids: ids, sampleCount: 12, targetPixelSize: DisplayMetrics.targetPixelSize())
        }
    }
}
