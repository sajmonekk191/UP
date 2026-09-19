// Renders Resources/AppIcon.icns from the UP! brand mark.
import AppKit
import SwiftUI

struct Icon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.43, green: 0.69, blue: 1), Color(red: 0.09, green: 0.31, blue: 0.58)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 30, y: 16)
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 6)
                .frame(width: 824, height: 824)
            Text("UP!").font(.system(size: 330, weight: .black)).foregroundStyle(.white).tracking(-12)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor func render() {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    let rep = NSBitmapImageRep(cgImage: cg)
    let dir = "Resources/AppIcon.iconset"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/icon_512x512@2x.png"))
}
MainActor.assumeIsolated { render() }
