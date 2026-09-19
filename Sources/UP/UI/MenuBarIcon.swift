import AppKit

/// Menu bar template icon: an exclamation mark whose bar is an upward arrow ("UP!").
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 12, height: 16), flipped: false) { _ in
            NSColor.black.setFill()
            let head = NSBezierPath()
            head.move(to: NSPoint(x: 6, y: 16))
            head.line(to: NSPoint(x: 11, y: 11))
            head.line(to: NSPoint(x: 7, y: 11))
            head.line(to: NSPoint(x: 7, y: 6))
            head.appendArc(withCenter: NSPoint(x: 6, y: 6), radius: 1, startAngle: 0, endAngle: 180, clockwise: true)
            head.line(to: NSPoint(x: 5, y: 11))
            head.line(to: NSPoint(x: 1, y: 11))
            head.close()
            head.fill()
            NSBezierPath(ovalIn: NSRect(x: 4.5, y: 0, width: 3, height: 3)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
