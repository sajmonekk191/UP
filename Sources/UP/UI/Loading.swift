import AppKit
import SwiftUI

/// Placeholder block in the shape of a line of text or an image that is still loading.
struct Bone: View {
    var width: CGFloat?
    var height: CGFloat = 10
    var line: CGFloat?
    var radius: CGFloat?

    var body: some View {
        RoundedRectangle(cornerRadius: radius ?? min(height / 2, 4), style: .continuous)
            .fill(Theme.skeleton)
            .frame(width: width, height: height)
            .frame(height: line)
    }
}

extension EnvironmentValues {
    /// Whether placeholders shimmer; off where nothing is actually loading yet.
    @Entry var shimmers = true
}

extension View {
    /// Sweeps a soft light band across this view's placeholder shapes.
    func shimmering() -> some View { modifier(Shimmer()) }
}

private struct Shimmer: ViewModifier {
    @Environment(\.shimmers) private var shimmers

    func body(content: Content) -> some View {
        content.overlay {
            if shimmers { ShimmerBand().mask { content }.allowsHitTesting(false) }
        }
    }
}

/// Light band animated by Core Animation across the window, so all placeholders share one sweep that never stalls.
private struct ShimmerBand: NSViewRepresentable {
    func makeNSView(context: Context) -> ShimmerBandView { ShimmerBandView() }
    func updateNSView(_ view: ShimmerBandView, context: Context) {}
}

private final class ShimmerBandView: NSView {
    private let band = CAGradientLayer()
    private static let period: CFTimeInterval = 1.9
    private static let width: CGFloat = 320

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let light = NSColor.white
        band.colors = [light.withAlphaComponent(0), light.withAlphaComponent(0.075), light.withAlphaComponent(0)].map(\.cgColor)
        band.startPoint = CGPoint(x: 0, y: 0.3)
        band.endPoint = CGPoint(x: 1, y: 0.7)
        layer?.addSublayer(band)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        sweep()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        sweep()
    }

    private func sweep() {
        guard let window else { return }
        let origin = convert(bounds.origin, to: nil).x
        let travel = window.frame.width * 1.3 + Self.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        band.frame = CGRect(x: -Self.width, y: 0, width: Self.width, height: bounds.height)
        CATransaction.commit()
        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = -Self.width / 2 - origin
        move.toValue = travel - Self.width / 2 - origin
        move.duration = Self.period
        move.repeatCount = .infinity
        let now = band.convertTime(CACurrentMediaTime(), from: nil)
        move.beginTime = now - now.truncatingRemainder(dividingBy: Self.period)
        band.add(move, forKey: "sweep")
    }
}

/// Accent loading ring spun by Core Animation, so it keeps turning while the main thread is busy.
struct Spinner: NSViewRepresentable {
    var size: CGFloat = 16
    var lineWidth: CGFloat = 2

    func makeNSView(context: Context) -> SpinnerView { SpinnerView(lineWidth: lineWidth) }
    func updateNSView(_ view: SpinnerView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SpinnerView, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }
}

final class SpinnerView: NSView {
    private let track = CAShapeLayer()
    private let arc = CAShapeLayer()
    private let lineWidth: CGFloat

    init(lineWidth: CGFloat) {
        self.lineWidth = lineWidth
        super.init(frame: .zero)
        wantsLayer = true
        for shape in [track, arc] {
            shape.fillColor = nil
            shape.lineWidth = lineWidth
            shape.lineCap = .round
            layer?.addSublayer(shape)
        }
        track.strokeColor = NSColor(Theme.accent).withAlphaComponent(0.2).cgColor
        arc.strokeColor = NSColor(Theme.accentBright).cgColor
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let path = CGPath(ellipseIn: bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2), transform: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for shape in [track, arc] {
            shape.frame = bounds
            shape.path = path
        }
        CATransaction.commit()
        spin()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        spin()
    }

    private func spin() {
        guard window != nil, arc.animation(forKey: "spin") == nil else { return }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = -2 * Double.pi
        turn.duration = 0.85
        turn.repeatCount = .infinity
        arc.add(turn, forKey: "spin")
        let stretch = CABasicAnimation(keyPath: "strokeEnd")
        stretch.fromValue = 0.14
        stretch.toValue = 0.62
        stretch.duration = 0.85
        stretch.autoreverses = true
        stretch.repeatCount = .infinity
        stretch.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        arc.add(stretch, forKey: "stretch")
    }
}

/// Circle that swells and fades on repeat, animated by Core Animation so the pulse costs the main thread nothing.
struct Pulse: NSViewRepresentable {
    var color: Color
    var scale: ClosedRange<CGFloat>
    /// Outline width, or nil for a filled circle.
    var lineWidth: CGFloat?

    func makeNSView(context: Context) -> PulseView { PulseView(color: NSColor(color), scale: scale, lineWidth: lineWidth) }
    func updateNSView(_ view: PulseView, context: Context) {}
}

final class PulseView: NSView {
    private let circle = CAShapeLayer()
    private let scale: ClosedRange<CGFloat>

    init(color: NSColor, scale: ClosedRange<CGFloat>, lineWidth: CGFloat?) {
        self.scale = scale
        super.init(frame: .zero)
        wantsLayer = true
        circle.fillColor = lineWidth == nil ? color.cgColor : nil
        circle.strokeColor = lineWidth == nil ? nil : color.cgColor
        circle.lineWidth = lineWidth ?? 0
        layer?.addSublayer(circle)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        circle.frame = bounds
        circle.path = CGPath(ellipseIn: bounds, transform: nil)
        CATransaction.commit()
        pulse()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        pulse()
    }

    private func pulse() {
        guard window != nil, circle.animation(forKey: "pulse") == nil else { return }
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = scale.lowerBound
        grow.toValue = scale.upperBound
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 1.4
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.repeatCount = .infinity
        circle.add(group, forKey: "pulse")
    }
}

/// Builds its content a moment after appearing, so heavy parts below the fold do not hold up the first paint.
struct Deferred<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var ready = false

    var body: some View {
        if ready {
            content
        } else {
            Color.clear.frame(height: 1).task {
                try? await Task.sleep(for: .milliseconds(30))
                ready = true
            }
        }
    }
}

/// Spinner with a short line saying what is loading.
struct LoadingNote: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Spinner(size: 14)
            Text(text).font(.callout).foregroundStyle(Theme.textSecondary).lineLimit(1)
        }
    }
}

/// Placeholder in the shape of a stat tile.
struct StatTileSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Bone(width: 64, height: 8, line: 13)
            Bone(width: 78, height: 18, line: 27, radius: 5)
            Bone(width: 104, height: 8, line: 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shimmering()
        .padding(14)
        .panelBackground(Theme.surface, radius: 12)
    }
}

/// Rank block with its queue title and placeholders for the rank and record.
struct RankBlockSkeleton: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Bone(width: 42, height: 42, radius: 21).shimmering().frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).eyebrow()
                VStack(alignment: .leading, spacing: 4) {
                    Bone(width: 112, height: 12, line: 17)
                    Bone(width: 64, height: 8, line: 13)
                    Bone(width: 150, height: 6, radius: 3)
                }
                .shimmering()
            }
        }
    }
}

/// Placeholder rows of an icon with one or two lines of text beside it.
struct RowsSkeleton: View {
    var rows = 5
    var icon: CGFloat = 30
    var trailing: CGFloat? = 64

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<rows, id: \.self) { index in
                HStack(spacing: 10) {
                    Bone(width: icon, height: icon, radius: icon * 0.24)
                    VStack(alignment: .leading, spacing: 5) {
                        Bone(width: [118, 92, 132, 104, 84, 124][index % 6], height: 9)
                        Bone(width: [74, 96, 62, 88, 70, 80][index % 6], height: 7)
                    }
                    Spacer(minLength: 8)
                    if let trailing { Bone(width: trailing, height: 8) }
                }
            }
        }
        .shimmering()
    }
}
