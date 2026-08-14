import AppKit
import SwiftUI

struct MenuBarQuotaGlyph: View {
    var body: some View {
        Image(nsImage: Self.templateImage)
            .resizable()
            .renderingMode(.template)
            .interpolation(.high)
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }

    private static let templateImage: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()

            let circle = NSBezierPath(ovalIn: NSRect(x: 3.1, y: 3.1, width: 11.8, height: 11.8))
            circle.lineWidth = 1.7
            circle.stroke()

            let font = NSFont.systemFont(ofSize: 9.2, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black
            ]
            let letter = NSString(string: "C")
            let letterSize = letter.size(withAttributes: attributes)
            letter.draw(
                at: NSPoint(
                    x: rect.midX - letterSize.width / 2,
                    y: rect.midY - letterSize.height / 2 + 0.2
                ),
                withAttributes: attributes
            )
            return true
        }
        image.isTemplate = true
        return image
    }()
}
