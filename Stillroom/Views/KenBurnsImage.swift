import StillroomCore
import SwiftUI
import UIKit

/// Core Animation interpolates the photo transform without per-frame SwiftUI updates.
struct KenBurnsImage: UIViewRepresentable {
    let image: CGImage
    let motion: PhotoMotion
    let duration: Double
    let isPaused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> MotionImageView {
        MotionImageView()
    }

    func updateUIView(_ view: MotionImageView, context: Context) {
        view.configure(image: image, motion: motion, duration: duration,
                       paused: isPaused, reduceMotion: reduceMotion)
    }
}

final class MotionImageView: UIView {
    private let photo = CALayer()
    private var motion = PhotoMotion(slideIndex: 0)
    private var duration = 0.0
    private var paused = false
    private var reduceMotion = false
    private var animatedSize = CGSize.zero
    private var needsAnimation = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        photo.contentsGravity = .resize
        photo.minificationFilter = .linear
        photo.magnificationFilter = .linear
        layer.addSublayer(photo)
    }

    required init?(coder: NSCoder) { nil }

    func configure(image: CGImage, motion: PhotoMotion, duration: Double, paused: Bool, reduceMotion: Bool) {
        if photo.contents == nil { photo.contents = image }
        self.motion = motion
        self.duration = duration
        if self.reduceMotion != reduceMotion {
            self.reduceMotion = reduceMotion
            needsAnimation = true
        }
        self.paused = paused
        setPaused(paused && !reduceMotion)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard needsAnimation || animatedSize != bounds.size else { return }
        needsAnimation = false
        animatedSize = bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        photo.removeAllAnimations()
        photo.speed = 1
        photo.timeOffset = 0
        photo.beginTime = 0
        photo.bounds = CGRect(origin: .zero, size: bounds.size)
        photo.position = CGPoint(x: bounds.midX, y: bounds.midY)
        photo.transform = reduceMotion ? CATransform3DIdentity : transform(at: 1)
        if !reduceMotion, duration > 0 {
            let animation = CABasicAnimation(keyPath: "transform")
            animation.fromValue = NSValue(caTransform3D: transform(at: 0))
            animation.toValue = NSValue(caTransform3D: transform(at: 1))
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            photo.add(animation, forKey: "photoMotion")
        }
        CATransaction.commit()
        setPaused(paused && !reduceMotion)
    }

    private func transform(at progress: Double) -> CATransform3D {
        let frame = motion.frame(at: progress)
        let x = ((motion.anchorX - 0.5) * (1 - frame.scale) + frame.x) * bounds.width
        let y = ((motion.anchorY - 0.5) * (1 - frame.scale) + frame.y) * bounds.height
        return CATransform3DMakeAffineTransform(CGAffineTransform(
            a: frame.scale, b: 0, c: 0, d: frame.scale, tx: x, ty: y
        ))
    }

    private func setPaused(_ paused: Bool) {
        if paused, photo.speed != 0 {
            let time = photo.convertTime(CACurrentMediaTime(), from: nil)
            photo.speed = 0
            photo.timeOffset = time
        } else if !paused, photo.speed == 0 {
            let time = photo.timeOffset
            photo.speed = 1
            photo.timeOffset = 0
            photo.beginTime = 0
            photo.beginTime = photo.convertTime(CACurrentMediaTime(), from: nil) - time
        }
    }
}
