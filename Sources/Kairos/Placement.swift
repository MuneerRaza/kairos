import AppKit
import ApplicationServices

/// Works out where the panel should appear.
@MainActor
enum Placement {
    static func frame(for size: NSSize, position: PopupPosition, forceCenter: Bool = false) -> NSRect {
        if !forceCenter {
            switch position {
            case .caret:
                if let caret = caretRect(), let screen = screen(at: NSPoint(x: caret.midX, y: caret.midY)) {
                    return nearCaret(caret, size: size, in: screen.visibleFrame)
                }
            case .mouse:
                let mouse = NSEvent.mouseLocation
                if let screen = screen(at: mouse) {
                    let rect = NSRect(x: mouse.x, y: mouse.y - size.height, width: size.width, height: size.height)
                    return constrained(rect, to: screen.visibleFrame)
                }
            case .center:
                break
            }
        }
        // Fallback for every mode: dead center of the display you're working on.
        let visible = focusedScreen().visibleFrame
        return NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                      width: size.width, height: size.height).integral
    }

    /// The display holding the focused window, else the one under the mouse.
    static func focusedScreen() -> NSScreen {
        if let window = focusedWindowRect(), let screen = screen(at: NSPoint(x: window.midX, y: window.midY)) {
            return screen
        }
        return screen(at: NSEvent.mouseLocation) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: - Geometry

    /// Just below the caret, or above it when there's no room below.
    private static func nearCaret(_ caret: NSRect, size: NSSize, in visible: NSRect) -> NSRect {
        var origin = NSPoint(x: caret.minX - 18, y: caret.minY - 10 - size.height)
        if origin.y < visible.minY { origin.y = caret.maxY + 10 }
        return constrained(NSRect(origin: origin, size: size), to: visible)
    }

    private static func constrained(_ rect: NSRect, to visible: NSRect) -> NSRect {
        var rect = rect
        rect.origin.x = min(max(rect.minX, visible.minX + 8), visible.maxX - rect.width - 8)
        rect.origin.y = min(max(rect.minY, visible.minY + 8), visible.maxY - rect.height - 8)
        return rect.integral
    }

    private static func screen(at point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    /// Accessibility uses a top-left origin on the primary display; AppKit uses bottom-left.
    private static func toAppKit(_ rect: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: - Accessibility queries

    private static func caretRect() -> NSRect? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)  // never hang on a slow app
        guard let element = element(system, kAXFocusedUIElementAttribute),
              let range = value(element, kAXSelectedTextRangeAttribute) else { return nil }

        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         range, &bounds) == .success,
              let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        // Apps that can't report a caret return an empty or zero rect.
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect),
              rect.height > 0, rect.origin != .zero else { return nil }
        return toAppKit(rect)
    }

    private static func focusedWindowRect() -> NSRect? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.15)
        guard let window = element(axApp, kAXFocusedWindowAttribute),
              let position = value(window, kAXPositionAttribute),
              let size = value(window, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return toAppKit(CGRect(origin: origin, size: extent))
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
