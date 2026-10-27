import AppKit

/// The button comes in five cap colours; the menu bar icon matches the one you have.
enum ButtonColor: String, CaseIterable {
    case red, green, blue, yellow, white

    var title: String { rawValue.capitalized }

    var cap: NSColor {
        switch self {
        case .red: return NSColor(srgbRed: 0.91, green: 0.13, blue: 0.11, alpha: 1)
        case .green: return NSColor(srgbRed: 0.16, green: 0.72, blue: 0.27, alpha: 1)
        case .blue: return NSColor(srgbRed: 0.13, green: 0.44, blue: 0.93, alpha: 1)
        case .yellow: return NSColor(srgbRed: 0.99, green: 0.80, blue: 0.10, alpha: 1)
        case .white: return NSColor(srgbRed: 0.97, green: 0.97, blue: 0.97, alpha: 1)
        }
    }

    static var current: ButtonColor {
        get { ButtonColor(rawValue: UserDefaults.standard.string(forKey: "buttonColor") ?? "") ?? .red }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "buttonColor") }
    }
}

/// Menu bar icon: the button seen from the side, a squat enclosure with a coloured dome on top.
/// The dome sinks when pressed and turns into an empty outline when the button isn't connected.
enum StatusIcon {
    static let size = NSSize(width: 20, height: 18)

    static func image(color: ButtonColor, connected: Bool, pressed: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            draw(color: color, connected: connected, pressed: pressed)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Draws into the current context. labelColor resolves at draw time, so the enclosure
    /// follows the light or dark menu bar.
    static func draw(color: ButtonColor, connected: Bool, pressed: Bool) {
        let ink = NSColor.labelColor
        let collarTop: CGFloat = 9.5

        // Enclosure: a wide, low box.
        ink.withAlphaComponent(connected ? 0.85 : 0.4).setFill()
        NSBezierPath(roundedRect: NSRect(x: 1, y: 1.5, width: 18, height: 6.5), xRadius: 2.2, yRadius: 2.2).fill()

        // Bezel collar between the box and the dome.
        ink.withAlphaComponent(connected ? 0.5 : 0.25).setFill()
        NSBezierPath(roundedRect: NSRect(x: 3.5, y: 8, width: 13, height: collarTop - 8), xRadius: 0.7, yRadius: 0.7).fill()

        // Dome: the top half of an ellipse sitting on the collar. Lower when pressed.
        let domeHeight: CGFloat = pressed ? 3.5 : 6.5
        let dome = NSBezierPath()
        dome.appendArc(withCenter: .zero, radius: 1, startAngle: 0, endAngle: 180)
        dome.close()
        var transform = AffineTransform(translationByX: 10, byY: collarTop)
        transform.scale(x: 5.5, y: domeHeight)
        dome.transform(using: transform)

        if connected {
            color.cap.setFill()
            dome.fill()
            // Specular highlight so it reads as a glossy cap rather than a flat dot.
            NSColor.white.withAlphaComponent(0.55).setFill()
            NSBezierPath(ovalIn: NSRect(x: 6.6, y: collarTop + domeHeight * 0.45, width: 3.2, height: max(1.2, domeHeight * 0.28))).fill()
            // Thin edge so the white and yellow caps stay visible on a light menu bar.
            ink.withAlphaComponent(0.35).setStroke()
            dome.lineWidth = 0.75
            dome.stroke()
        } else {
            ink.withAlphaComponent(0.45).setStroke()
            dome.lineWidth = 1.1
            dome.stroke()
        }
    }
}
