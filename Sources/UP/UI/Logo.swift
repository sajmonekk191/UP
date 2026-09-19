import CoreText
import SwiftUI

/// "UP!" set in Futura Bold, centered in the rect.
struct UPLogoShape: Shape {
    var fill: CGFloat = 0.6

    func path(in rect: CGRect) -> Path {
        let logo = Self.logo
        let bounds = logo.bounds
        let scale = min(rect.width * fill / bounds.width, rect.height * fill / bounds.height)
        var transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: -scale)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
        return Path(logo.path.copy(using: &transform) ?? logo.path)
    }

    /// Glyph outlines in font units with the baseline at y = 0.
    static let logo: (path: CGPath, bounds: CGRect) = {
        let font = CTFontCreateWithName("Futura-Bold" as CFString, 100, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "UP!", attributes: [.font: font]))
        let path = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for index in 0..<count {
                guard let outline = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
                path.addPath(outline, transform: CGAffineTransform(translationX: positions[index].x, y: positions[index].y))
            }
        }
        return (path.copy() ?? path, path.boundingBoxOfPath)
    }()
}

/// Brand mark: black tile with the white UP! logo, matching the app icon.
struct AppMark: View {
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(.black)
            UPLogoShape().fill(.white)
        }
        .frame(width: size, height: size)
    }
}
