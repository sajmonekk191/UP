// Renders Resources/AppIcon.iconset/icon_512x512@2x.png from the shared UPLogoShape (Sources/UP/UI/Logo.swift).
import AppKit
import SwiftUI

struct Icon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .fill(.black)
            UPLogoShape().fill(.white)
        }
        .frame(width: 824, height: 824)
        .frame(width: 1024, height: 1024)
    }
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    let dir = "Resources/AppIcon.iconset"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try! NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "\(dir)/icon_512x512@2x.png"))
}
