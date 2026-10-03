import StillroomCore
import SwiftUI

/// Full-screen slideshow presentation and Siri Remote handling.
///
/// Remote: left/right = previous/next, Play/Pause = pause/resume,
/// click or up/down = show controls, Menu/Back = hide controls, then exit.
struct SlideshowView: View {
    let controller: SlideshowController
    let albumTitle: String
    let style: VerticalPhotoStyle
    let transitions: TransitionSettings
    let isNetworkAvailable: Bool
    let onExit: () -> Void
    let onRestart: () -> Void

    @Environment(PhotoLibraryModel.self) private var library
    @AppStorage(SettingsKey.showCounter) private var showCounter = true
    @AppStorage(SettingsKey.showDiagnostics) private var showDiagnostics = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controlsVisible = false
    /// Slides being drawn: normally one; two or more during a transition.
    @State private var layers: [SlideLayer] = []
    /// The slide a remote press moved to; when it appears, it slides in from that side.
    @State private var pendingPush: PendingPush?
    @State private var hideControlsTask: Task<Void, Never>?
    @FocusState private var focus: Focus?

    private enum Focus: Hashable {
        case canvas
        case controls
        case panel
    }

    private var hasPanel: Bool {
        switch controller.phase {
        case .stalled, .failed: true
        case .idle, .loading, .showing, .finished: false
        }
    }

    private var slideKey: String {
        guard let slide = controller.displayed else { return "none" }
        return "\(slide.cycle)-\(slide.slideIndex)-\(slide.ids.count)"
    }

    var body: some View {
        ZStack {
            canvas
            statusOverlays
                .allowsHitTesting(false)
            if hasPanel {
                panel
                    .transition(.opacity)
            } else if controlsVisible {
                controlsBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: controlsVisible)
        .animation(.easeInOut(duration: 0.3), value: hasPanel)
        .onPlayPauseCommand {
            controller.togglePause()
            if controller.isPaused { revealControls() }
        }
        .onExitCommand {
            if controlsVisible && !hasPanel {
                hideControls()
            } else {
                onExit()
            }
        }
        .onChange(of: hasPanel, initial: true) { _, showing in
            focus = showing ? .panel : (controlsVisible ? .controls : .canvas)
        }
        .onChange(of: controller.phase) { _, phase in
            // With loop off, the end of the album returns to the album screen.
            if phase == .finished { onExit() }
        }
        .onDisappear { hideControlsTask?.cancel() }
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                ForEach(layers) { layer in
                    SlideContentView(
                        slide: layer.slide,
                        total: controller.total,
                        style: style,
                        controller: controller,
                        isCurrent: layer.id == layers.last?.id,
                        kenBurnsDuration: kenBurnsDuration
                    )
                    .opacity(layer.opacity)
                    .offset(x: layer.offset * geometry.size.width)
                }
            }
        }
        .clipped()
        .onChange(of: slideKey, initial: true) { transitionToDisplayedSlide() }
        .ignoresSafeArea()
        .focusable(!hasPanel && !controlsVisible)
        .focused($focus, equals: .canvas)
        .focusEffectDisabled()
        .onMoveCommand { direction in
            switch direction {
            case .left: navigate(.backward)
            case .right: navigate(.forward)
            case .up, .down: revealControls()
            @unknown default: break
            }
        }
        .onTapGesture { revealControls() }
    }

    /// A slide's Ken Burns zoom spans its whole time on screen, both fades included.
    private var kenBurnsDuration: Double? {
        guard transitions.kenBurns else { return nil }
        let slide = controller.settings.slideDuration
        let seconds = Double(slide.components.seconds) + Double(slide.components.attoseconds) / 1e18
        return seconds + transitions.fadeSpeed.seconds
    }

    /// Moves to the previous or next slide from a remote or control-bar press,
    /// remembering where it went so that slide pushes in from the pressed side.
    private func navigate(_ direction: PushDirection) {
        switch direction {
        case .forward: controller.next()
        case .backward: controller.previous()
        }
        pendingPush = PendingPush(direction: direction, cycle: controller.cycle, position: controller.targetPosition)
    }

    /// Brings in the newly displayed slide. The old slides stay in `layers`
    /// until the new one is fully in, then are dropped. A plain SwiftUI
    /// transition removed the old slide immediately, flashing black between slides.
    private func transitionToDisplayedSlide() {
        guard let slide = controller.displayed else {
            layers = []
            pendingPush = nil
            return
        }
        let key = slideKey
        guard layers.last?.id != key else { return }
        let push = pendingPush.flatMap { $0.cycle == slide.cycle && $0.position == slide.position ? $0.direction : nil }
        pendingPush = nil
        guard !layers.isEmpty else {
            layers = [SlideLayer(id: key, slide: slide, opacity: 1)]
            return
        }
        if let push, !reduceMotion {
            pushIn(slide, key: key, from: push)
        } else if push == nil, transitions.transition == .fadeThroughBlack {
            fadeThroughBlack(to: slide, key: key)
        } else {
            // Remote presses with Reduce Motion on crossfade quickly instead of sliding.
            crossfade(to: slide, key: key, duration: push == nil ? transitions.fadeSpeed.seconds : TransitionSettings.pushSeconds)
        }
    }

    /// Fades the new slide in over the old one, which stays fully visible underneath.
    private func crossfade(to slide: DisplayedSlide, key: String, duration: Double) {
        layers.append(SlideLayer(id: key, slide: slide, opacity: 0))
        withAnimation(.easeInOut(duration: duration)) {
            setOpacity(1, of: key)
        } completion: {
            dropLayers(before: key)
        }
    }

    /// Fades the old slide out to black, then the new one in, each over half the fade time.
    private func fadeThroughBlack(to slide: DisplayedSlide, key: String) {
        let half = transitions.fadeSpeed.seconds / 2
        layers.append(SlideLayer(id: key, slide: slide, opacity: 0))
        withAnimation(.easeIn(duration: half)) {
            for index in layers.indices where layers[index].id != key {
                layers[index].opacity = 0
            }
        } completion: {
            // A newer slide may have started its own transition meanwhile.
            guard layers.last?.id == key else { return }
            withAnimation(.easeOut(duration: half)) {
                setOpacity(1, of: key)
            } completion: {
                dropLayers(before: key)
            }
        }
    }

    /// Slides the new slide in from the side the user pressed, pushing the old one out.
    private func pushIn(_ slide: DisplayedSlide, key: String, from direction: PushDirection) {
        let side: Double = direction == .forward ? 1 : -1
        layers.append(SlideLayer(id: key, slide: slide, opacity: 1, offset: side))
        withAnimation(.easeInOut(duration: TransitionSettings.pushSeconds)) {
            for index in layers.indices {
                if layers[index].id == key {
                    layers[index].offset = 0
                } else {
                    layers[index].offset -= side
                }
            }
        } completion: {
            dropLayers(before: key)
        }
    }

    private func setOpacity(_ opacity: Double, of key: String) {
        if let index = layers.firstIndex(where: { $0.id == key }) {
            layers[index].opacity = opacity
        }
    }

    /// Drops every slide but `key`, unless a newer slide is already on its way in.
    private func dropLayers(before key: String) {
        guard layers.last?.id == key else { return }
        layers.removeAll { $0.id != key }
    }

    // MARK: Status overlays (non-interactive)

    private var statusOverlays: some View {
        ZStack {
            if controller.phase == .loading && controller.displayed == nil {
                VStack(spacing: 24) {
                    ProgressView()
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(loadingText(first: true))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 16) {
                        if controller.isPaused {
                            Label("Paused", systemImage: "pause.fill")
                                .pill()
                        }
                        if showDiagnostics {
                            DiagnosticsOverlay(
                                diagnostics: controller.diagnostics,
                                eligibleAlbums: library.albums.filter { ($0.photoCount ?? 0) > 0 }.count,
                                phase: controller.phase,
                                isNetworkAvailable: isNetworkAvailable
                            )
                        }
                    }
                    Spacer()
                    if controller.phase == .loading && controller.displayed != nil {
                        HStack(spacing: 14) {
                            ProgressView()
                                .scaleEffect(0.6)
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                Text(loadingText(first: false))
                            }
                        }
                        .pill()
                        .transition(.opacity)
                    }
                }
                Spacer()
                HStack(alignment: .bottom) {
                    if let notice = controller.notice {
                        Text(notice)
                            .pill()
                            .transition(.opacity)
                    }
                    Spacer()
                    if showCounter && controller.total > 0 && !hasPanel {
                        Text(counterText)
                            .monospacedDigit()
                            .pill()
                    }
                }
            }
            .padding(10)
        }
        .animation(.easeInOut(duration: 0.3), value: controller.phase)
        .animation(.easeInOut(duration: 0.3), value: controller.notice)
    }

    private var counterText: String {
        let position = controller.targetPosition + 1
        let total = controller.total.formatted()
        if controller.targetSlideSize > 1 {
            return "Photos \(position.formatted())–\((position + controller.targetSlideSize - 1).formatted()) of \(total)"
        }
        return "Photo \(position.formatted()) of \(total)"
    }

    private func loadingText(first: Bool) -> String {
        var text: String
        if !isNetworkAvailable {
            text = "Waiting for network…"
        } else if controller.isRetryingTarget {
            text = "Having trouble loading — retrying…"
        } else if let progress = controller.targetProgress {
            text = "Downloading from iCloud \(Int(progress * 100))%"
        } else {
            text = first ? "Loading first photo…" : "Loading next photo…"
        }
        // After a while, show how long and which attempt, so a slow download
        // is distinguishable from a stuck one.
        if let elapsed = controller.targetLoadingElapsed, elapsed >= .seconds(10) {
            text += " \(elapsed.components.seconds) s"
            if controller.targetAttempt > 1 {
                text += " · attempt \(controller.targetAttempt) of \(controller.maxAttempts)"
            }
        }
        return text
    }

    // MARK: Panels

    @ViewBuilder
    private var panel: some View {
        switch controller.phase {
        case .stalled(let failure):
            PanelView(
                title: controller.displayed == nil
                    ? "Couldn’t Load the First Photo"
                    : "Couldn’t Load Photo \(controller.targetPosition + 1) of \(controller.total)",
                message: stalledMessage(failure)
            ) {
                Button("Retry") { controller.retryCurrent() }
                    .focused($focus, equals: .panel)
                Button("Skip Photo") { controller.skipCurrent() }
                Button("Exit", action: onExit)
            }
        case .failed(let message):
            PanelView(title: "Can’t Continue", message: message) {
                Button("Try Again", action: onRestart)
                    .focused($focus, equals: .panel)
                Button("Done", action: onExit)
            }
        case .idle, .loading, .showing, .finished:
            EmptyView()
        }
    }

    private func stalledMessage(_ failure: ImageLoadFailure) -> String {
        var lines = [failure.message]
        if !isNetworkAvailable {
            lines.append("This Apple TV appears to be offline. Stillroom will try again automatically when the network returns.")
        }
        var holding = "The slideshow is holding here. Nothing is skipped unless you choose Skip Photo."
        if controller.settings.loops {
            holding += " Skipped photos are noted at the end of each cycle."
        }
        lines.append(holding)
        return lines.joined(separator: "\n\n")
    }

    // MARK: Controls

    private var controlsBar: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text(albumTitle)
                        .font(.title3.bold())
                    Spacer()
                    Text(counterText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 30) {
                    Button { navigate(.backward); scheduleHide() } label: {
                        Label("Previous", systemImage: "backward.fill")
                    }
                    Button { controller.togglePause(); scheduleHide() } label: {
                        Label(controller.isPaused ? "Play" : "Pause",
                              systemImage: controller.isPaused ? "play.fill" : "pause.fill")
                    }
                    .focused($focus, equals: .controls)
                    Button { navigate(.forward); scheduleHide() } label: {
                        Label("Next", systemImage: "forward.fill")
                    }
                    Button { controller.setLoops(!controller.settings.loops); scheduleHide() } label: {
                        Label(controller.settings.loops ? "Loop On" : "Loop Off", systemImage: "repeat")
                    }
                    Button { showCounter.toggle(); scheduleHide() } label: {
                        Label(showCounter ? "Counter On" : "Counter Off", systemImage: "number")
                    }
                    Spacer()
                    Button("Exit", action: onExit)
                }
                Text("◀︎ ▶︎ previous / next   ·   ⏯ pause / play   ·   Back hides controls")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(50)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30))
        }
        .padding(.bottom, 20)
    }

    private func revealControls() {
        guard !hasPanel else { return }
        controlsVisible = true
        focus = .controls
        scheduleHide()
    }

    private func hideControls() {
        hideControlsTask?.cancel()
        controlsVisible = false
        focus = .canvas
    }

    private func scheduleHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            // Stay visible while paused so the state is obvious.
            if !controller.isPaused {
                hideControls()
            }
        }
    }
}

/// Centered card with a title, explanation, and buttons.
private struct PanelView<Actions: View>: View {
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 30) {
            Text(title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 30) {
                actions
            }
            .focusSection()
        }
        .padding(60)
        .frame(maxWidth: 1200)
        .background(Color(white: 0.08).opacity(0.92), in: RoundedRectangle(cornerRadius: 30))
    }
}

private extension View {
    /// Small translucent capsule used for status text over photos.
    func pill() -> some View {
        font(.callout)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.black.opacity(0.55), in: Capsule())
            .foregroundStyle(.white)
    }
}

private struct SlideLayer: Identifiable {
    let id: String
    let slide: DisplayedSlide
    var opacity: Double
    /// Horizontal position as a fraction of the screen width (0 is on screen).
    var offset: Double = 0
}

private enum PushDirection {
    case forward
    case backward
}

/// The slide a remote press is heading to. Matched by position, so a press that
/// didn't move (e.g. Previous on the first photo) never affects a later slide.
private struct PendingPush {
    let direction: PushDirection
    let cycle: Int
    let position: Int
}
