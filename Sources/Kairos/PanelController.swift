import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

/// A borderless panel that takes keyboard focus without activating Kairos,
/// so the app you were typing in stays frontmost and receives the paste.
final class GlassPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
@Observable
final class PanelModel {
    var query = ""
    var selection: UUID?
    var showingSettings = false
    var showingSetup = false
    var previewing: UUID?
    var recordingShortcut = false

    func filter(_ items: [ClipItem]) -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        // Also match a YouTube link by its video title.
        let titles = LinkPreviews.shared.info
        return items.filter { item in
            item.searchText.localizedCaseInsensitiveContains(q)
                || (YouTube.videoID(in: item.text).flatMap { titles[$0]?.title }?
                    .localizedCaseInsensitiveContains(q) ?? false)
        }
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 440, height: 520)

    let store: ClipboardStore
    let settings: Settings
    let model = PanelModel()
    private var panel: GlassPanel!
    private var glass: NSGlassEffectView!
    private var keyMonitor: Any?

    init(store: ClipboardStore, settings: Settings) {
        self.store = store
        self.settings = settings
        super.init()
        buildPanel()
    }

    private func buildPanel() {
        let panel = GlassPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                               styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                               backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.delegate = self

        // Real window-level Liquid Glass: it refracts whatever is behind the panel.
        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: Self.size))
        glass.cornerRadius = 30
        glass.autoresizingMask = [.width, .height]

        // Clip to the same rounded shape so no square corners or shadow edges show.
        let clip = NSView(frame: NSRect(origin: .zero, size: Self.size))
        clip.wantsLayer = true
        clip.layer?.cornerRadius = 30
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        clip.addSubview(glass)
        panel.contentView = clip
        self.glass = glass
        self.panel = panel
    }

    /// The SwiftUI view only exists while the panel is on screen; dropping it
    /// when hidden keeps Kairos's memory low while it waits in the background.
    private func attachContent() {
        guard glass.contentView == nil else { return }
        let host = NSHostingView(rootView: RootView(store: store, settings: settings, model: model, controller: self))
        host.frame = NSRect(origin: .zero, size: Self.size)
        host.autoresizingMask = [.width, .height]
        glass.contentView = host
    }

    private func detachContent() {
        glass.contentView = nil
    }

    // MARK: - Showing and hiding

    func toggle() {
        panel.isVisible ? close() : show()
    }

    func show() {
        guard !panel.isVisible else { return }
        let setup = !settings.hasCompletedSetup
        model.query = ""
        model.showingSettings = false
        model.showingSetup = setup
        model.previewing = nil
        model.selection = store.items.first?.id

        panel.level = setup ? .floating : .popUpMenu
        let target = Placement.frame(for: Self.size, position: settings.position, forceCenter: setup)
        attachContent()
        panel.setFrame(target.offsetBy(dx: 0, dy: 10), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()  // Kairos is never the active app, so force it
        panel.makeKey()
        panel.invalidateShadow()
        installKeyMonitor()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        guard panel.isVisible else { return }
        removeKeyMonitor()
        if model.recordingShortcut { stopRecording() }
        let panel = self.panel!
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                guard panel.alphaValue == 0 else { return }  // reopened mid-fade
                panel.orderOut(nil)
                self.detachContent()
            }
        })
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking elsewhere closes the panel, except during setup, when the
        // user has to visit System Settings and come back.
        guard !model.showingSetup else { return }
        close()
    }

    /// Lets System Settings sit above the setup screen while permission is granted.
    func stepAside() {
        panel.level = .normal
        panel.orderBack(nil)
    }

    /// Brings the setup screen back once permission is granted in System Settings.
    func bringToFront() {
        guard panel.isVisible else { return }
        panel.level = .floating
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func finishSetup() {
        settings.hasCompletedSetup = true
        panel.level = .popUpMenu
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
            model.showingSetup = false
        }
    }

    // MARK: - Actions

    func paste(_ item: ClipItem) {
        store.writeToPasteboard(item)
        removeKeyMonitor()
        panel.alphaValue = 0
        panel.orderOut(nil)  // instantly, so the keystroke lands in the app underneath
        detachContent()

        // Without Accessibility access the item is simply left on the clipboard.
        guard Paster.isTrusted else { return }
        if NSApp.isActive { NSApp.hide(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            Paster.pasteIntoFrontApp()
        }
    }

    func showPreview(_ item: ClipItem) {
        model.selection = item.id
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { model.previewing = item.id }
    }

    func closePreview() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { model.previewing = nil }
    }

    func toggleSettings() {
        if model.recordingShortcut { stopRecording() }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            model.showingSettings.toggle()
        }
    }

    func deleteSelected() {
        let list = model.filter(store.items)
        guard let id = model.selection, let i = list.firstIndex(where: { $0.id == id }) else { return }
        let next = i + 1 < list.count ? list[i + 1].id : (i > 0 ? list[i - 1].id : nil)
        withAnimation(.snappy(duration: 0.25)) {
            store.delete(id)
            model.selection = next
        }
    }

    func startRecording() {
        HotKey.shared.unregister()
        withAnimation(.snappy) { model.recordingShortcut = true }
    }

    func stopRecording() {
        withAnimation(.snappy) { model.recordingShortcut = false }
        HotKey.shared.register(settings.shortcut)
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Local monitors run on the main thread.
            nonisolated(unsafe) let event = event
            let handled = MainActor.assumeIsolated { self.handle(event) }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true when the key was handled and should not reach the text field.
    private func handle(_ event: NSEvent) -> Bool {
        if model.recordingShortcut {
            if Int(event.keyCode) == kVK_Escape {
                stopRecording()
            } else if let shortcut = Shortcut(event: event) {
                settings.shortcut = shortcut
                stopRecording()
            } else {
                NSSound.beep()
            }
            return true
        }

        let command = event.modifierFlags.contains(.command)
        switch Int(event.keyCode) {
        case kVK_Escape:
            if model.previewing != nil {
                closePreview()
            } else if model.showingSettings {
                toggleSettings()
            } else {
                close()
            }
            return true
        case kVK_Return where model.previewing != nil, kVK_ANSI_KeypadEnter where model.previewing != nil:
            if let item = store.items.first(where: { $0.id == model.previewing }) { paste(item) }
            return true
        case kVK_LeftArrow where model.previewing != nil:
            closePreview()
            return true
        case _ where model.previewing != nil:
            return false
        case _ where model.showingSetup:
            return false
        case kVK_ANSI_Comma where command:
            toggleSettings()
            return true
        case _ where model.showingSettings:
            return false
        case kVK_DownArrow:
            moveSelection(1)
            return true
        case kVK_UpArrow:
            moveSelection(-1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let item = selectedItem { paste(item) }
            return true
        case kVK_RightArrow where caretAtEndOfSearch:
            guard let item = selectedItem else { return false }
            showPreview(item)
            return true
        case kVK_Delete where command:
            deleteSelected()
            return true
        default:
            return false
        }
    }

    private var selectedItem: ClipItem? {
        store.items.first { $0.id == model.selection }
    }

    /// → still moves the cursor inside the search text; it opens the preview
    /// only once the cursor can't go further right.
    private var caretAtEndOfSearch: Bool {
        guard let editor = panel.firstResponder as? NSTextView else { return true }
        let range = editor.selectedRange()
        return range.length == 0 && range.location == (editor.string as NSString).length
    }

    private func moveSelection(_ delta: Int) {
        let list = model.filter(store.items)
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == model.selection } ?? -1
        let next = min(max(current + delta, 0), list.count - 1)
        model.selection = list[next].id
    }
}
