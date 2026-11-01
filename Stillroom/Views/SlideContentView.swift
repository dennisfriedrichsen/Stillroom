import StillroomCore
import SwiftUI

/// Draws one slide (one photo, or a side-by-side pair) in the chosen style.
struct SlideContentView: View {
    let slide: DisplayedSlide
    let total: Int
    let style: VerticalPhotoStyle
    let controller: SlideshowController
    /// Seconds of Ken Burns zoom (the slide's time on screen), or nil for none.
    var kenBurnsDuration: Double?
    var zoomAmount = ZoomAmount.defaultAmount

    var body: some View {
        GeometryReader { geometry in
            content(in: geometry.size)
        }
        .ignoresSafeArea()
    }

    private func content(in size: CGSize) -> some View {
        ZStack {
            Color.black
            if style.usesBackdrop, let backdrop = slide.photos[0].image.backdrop {
                Image(decorative: backdrop, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .overlay(Color.black.opacity(0.35))
            }
            if slide.photos.count > 1 {
                pair(in: size)
            } else if let photo = slide.photos.first {
                if style == .slowPan, let cgImage = photo.image.cgImage,
                   pans(cgImage, in: size) {
                    PanningImage(
                        image: cgImage,
                        focus: photo.image.focus,
                        viewSize: size,
                        label: label(for: slide.position + 1),
                        controller: controller,
                        slideIndex: slide.slideIndex
                    )
                } else {
                    fitted(photo, label: slide.position + 1, in: size)
                }
            }
        }
    }

    @ViewBuilder
    private func fitted(_ photo: DisplayedPhoto, label position: Int, in size: CGSize) -> some View {
        if let cgImage = photo.image.cgImage {
            let fit = min(size.width / CGFloat(cgImage.width), size.height / CGFloat(cgImage.height))
            let fittedSize = CGSize(width: CGFloat(cgImage.width) * fit, height: CGFloat(cgImage.height) * fit)
            let image = Image(cgImage, scale: 1, label: Text(label(for: position)))
                .resizable()
                .frame(width: fittedSize.width, height: fittedSize.height)
            if let kenBurnsDuration {
                KenBurnsImage(
                    image: cgImage,
                    motion: PhotoMotion(slideIndex: slide.slideIndex,
                                        focusX: photo.image.focus.map { Double($0.x) },
                                        focusY: photo.image.focus.map { Double($0.y) },
                                        zoomAmount: zoomAmount),
                    duration: kenBurnsDuration,
                    isPaused: controller.isPaused
                )
                .frame(width: fittedSize.width, height: fittedSize.height)
                .accessibilityLabel(label(for: position))
            } else {
                image
            }
        }
    }

    /// Two photos at the same height, as large as fits, with a small gap between them.
    private func pair(in size: CGSize) -> some View {
        let gap: CGFloat = 24
        let aspects = slide.photos.map { photo -> CGFloat in
            guard let image = photo.image.cgImage, image.height > 0 else { return 0.75 }
            return CGFloat(image.width) / CGFloat(image.height)
        }
        let height = min(size.height, (size.width - gap * 3) / max(0.1, aspects.reduce(0, +)))
        return HStack(spacing: gap) {
            ForEach(Array(slide.photos.enumerated()), id: \.offset) { index, photo in
                if let cgImage = photo.image.cgImage {
                    Image(cgImage, scale: 1, label: Text(label(for: slide.position + index + 1)))
                        .resizable()
                        .frame(width: height * aspects[index], height: height)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Pan only images rendered for panning, i.e. taller than the screen at full width.
    private func pans(_ image: CGImage, in size: CGSize) -> Bool {
        guard image.width > 0, size.width > 0 else { return false }
        let heightAtFullWidth = size.width * CGFloat(image.height) / CGFloat(image.width)
        return heightAtFullWidth > size.height * 1.05
    }

    private func label(for position: Int) -> String {
        "Photo \(position) of \(total)"
    }
}

/// A photo scaled to the screen's width that moves vertically over the slide's
/// display time, gently drifting around the detected face or subject.
private struct PanningImage: View {
    let image: CGImage
    let focus: CGPoint?
    let viewSize: CGSize
    let label: String
    let controller: SlideshowController
    let slideIndex: Int
    @State private var clock = MotionClock()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let height = viewSize.width * CGFloat(image.height) / CGFloat(image.width)
        let path = VerticalPanPath(
            imageHeight: height, viewHeight: viewSize.height, focusY: focus.map { Double($0.y) },
            slideIndex: slideIndex, duration: duration
        )
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || controller.isPaused)) { context in
            let progress = duration > 0 ? clock.elapsed(at: context.date) / duration : 1
            let top = reduceMotion ? path.resting : path.offset(at: progress)
            Image(image, scale: 1, label: Text(label))
                .resizable()
                .frame(width: viewSize.width, height: height)
                .offset(y: -top)
                .frame(width: viewSize.width, height: viewSize.height, alignment: .top)
                .clipped()
        }
        .onChange(of: controller.isPaused, initial: true) { _, paused in
            clock.setRunning(!paused)
        }
    }

    private var duration: Double {
        let value = controller.settings.slideDuration.components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }
}
