import AppKit
import SwiftUI

struct RootView: View {
    let store: ClipboardStore
    let settings: Settings
    @Bindable var model: PanelModel
    let controller: PanelController

    var body: some View {
        ZStack {
            if model.showingSetup {
                SetupView(settings: settings, model: model, controller: controller)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .scale(scale: 1.04).combined(with: .opacity)))
            } else if let item = store.items.first(where: { $0.id == model.previewing }) {
                PreviewView(item: item, store: store, controller: controller)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            } else if model.showingSettings {
                SettingsView(settings: settings, store: store, model: model, controller: controller)
                    .transition(.asymmetric(
                        insertion: .offset(x: 36).combined(with: .opacity),
                        removal: .offset(x: 36).combined(with: .opacity)))
            } else {
                HistoryView(store: store, model: model, controller: controller)
                    .transition(.asymmetric(
                        insertion: .offset(x: -36).combined(with: .opacity),
                        removal: .offset(x: -36).combined(with: .opacity)))
            }
        }
        .frame(width: PanelController.size.width, height: PanelController.size.height)
    }
}

// MARK: - History

struct HistoryView: View {
    let store: ClipboardStore
    @Bindable var model: PanelModel
    let controller: PanelController

    @FocusState private var searchFocused: Bool
    @Namespace private var selectionNamespace
    @State private var appeared = false
    @State private var lastMouse = CGPoint.zero

    private var items: [ClipItem] { model.filter(store.items) }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)
            content
            footer
        }
        .onAppear(perform: reveal)
        .onChange(of: model.query) { model.selection = items.first?.id }
    }

    private var header: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                // Nothing to search until something has been copied.
                if store.items.isEmpty {
                    Spacer()
                } else {
                    searchField
                        .transition(.scale(scale: 0.9, anchor: .trailing).combined(with: .opacity))
                }

                Button(action: controller.toggleSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 42, height: 42)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .help("Settings  ⌘,")
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.items.isEmpty)
        }
    }

    private var searchField: some View {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("Search", text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($searchFocused)
                    if !model.query.isEmpty {
                        Button { model.query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 15)
                .frame(height: 42)
                .glassEffect(.regular, in: .capsule)
                .animation(.snappy(duration: 0.2), value: model.query.isEmpty)
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            EmptyState(searching: !model.query.isEmpty)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item, index: index)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.never)
                .onChange(of: model.selection) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.16)) { proxy.scrollTo(id) }
                }
            }
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.025),
                    .init(color: .black, location: 0.96),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
        }
    }

    private func row(_ item: ClipItem, index: Int) -> some View {
        let selected = item.id == model.selection
        return ItemRow(item: item, store: store, selected: selected) { controller.showPreview(item) }
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.tint.opacity(0.2))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                        }
                        .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.selection)
            .contentShape(.rect(cornerRadius: 16))
            .onTapGesture { controller.paste(item) }
            .onContinuousHover { phase in
                if case .active = phase { hovered(item) }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .scaleEffect(appeared ? 1 : 0.97, anchor: .top)
            .animation(.spring(response: 0.46, dampingFraction: 0.82)
                .delay(Double(min(index, 10)) * 0.022), value: appeared)
            .id(item.id)
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .scale(scale: 0.92).combined(with: .opacity)))
    }

    private var footer: some View {
        HStack(spacing: 14) {
            KeyHint(keys: "↩", label: "Paste")
            KeyHint(keys: "⌘⌫", label: "Delete")
            KeyHint(keys: "esc", label: "Close")
            Spacer()
            ClearButton(store: store)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    /// Mouse hover selects a row, but only when the mouse really moved, so
    /// keyboard scrolling under a resting cursor doesn't steal the selection.
    private func hovered(_ item: ClipItem) {
        let point = NSEvent.mouseLocation
        guard point != lastMouse else { return }
        lastMouse = point
        if model.selection != item.id { model.selection = item.id }
    }

    private func reveal() {
        lastMouse = NSEvent.mouseLocation
        searchFocused = true
        appeared = false
        DispatchQueue.main.async { appeared = true }
    }
}

struct ItemRow: View {
    let item: ClipItem
    let store: ClipboardStore
    let selected: Bool
    let onPreview: () -> Void

    private var previews: LinkPreviews { .shared }
    private var videoID: String? { item.kind == .text ? YouTube.videoID(in: item.text) : nil }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 38, height: 38)
                .task(id: videoID) { if let videoID { previews.load(videoID) } }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .truncationMode(.tail)
                if let meta {
                    Text(meta)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Button(action: onPreview) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .glassEffect(.regular.interactive(), in: .circle)
            .opacity(selected ? 1 : 0.45)
            .help("Preview")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch item.kind {
        case .image:
            if let url = store.imageURL(item), let image = Thumbnails.image(at: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 38, height: 38)
                    .clipShape(.rect(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
                    }
            } else {
                symbolTile("photo")
            }
        case .files:
            if let path = item.paths?.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                symbolTile("doc")
            }
        case .text:
            if let videoID, let image = previews.thumbnails[videoID] {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 38, height: 38)
                    .clipShape(.rect(cornerRadius: 10, style: .continuous))
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                    .transition(.opacity)
            } else {
                symbolTile(isLink ? "link" : "text.alignleft")
            }
        }
    }

    private func symbolTile(_ name: String) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.primary.opacity(0.06))
            .overlay {
                Image(systemName: name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
    }

    private var isLink: Bool {
        guard let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.contains(" "), let url = URL(string: text) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }

    private var title: String {
        if let videoID, let info = previews.info[videoID] { return info.title }
        switch item.kind {
        case .text:
            let text = String((item.text ?? "").prefix(300))
            return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        case .files:
            let paths = item.paths ?? []
            let first = paths.first.map { ($0 as NSString).lastPathComponent } ?? "File"
            return paths.count > 1 ? "\(first)  +\(paths.count - 1) more" : first
        case .image:
            return "Image"
        }
    }

    private var meta: String? {
        if let videoID, let info = previews.info[videoID] {
            return ["YouTube", info.channel].compactMap(\.self).joined(separator: " · ")
        }
        switch item.kind {
        case .text:
            let count = item.text?.count ?? 0
            return "\(count) character\(count == 1 ? "" : "s")"
        case .files:
            let folder = (item.paths?.first as NSString?)?.deletingLastPathComponent ?? ""
            return (folder as NSString).abbreviatingWithTildeInPath
        case .image:
            return nil
        }
    }
}

struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 17)
                .background(.primary.opacity(0.08), in: .rect(cornerRadius: 5, style: .continuous))
            Text(label)
                .font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
    }
}

struct ClearButton: View {
    let store: ClipboardStore

    var body: some View {
        DestructiveButton(title: "Clear") {
            withAnimation(.snappy(duration: 0.3)) { store.clear() }
        }
        .disabled(store.items.isEmpty)
        .opacity(store.items.isEmpty ? 0.4 : 1)
    }
}

/// A glass capsule button that turns red on hover.
struct DestructiveButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let red = hovering && isEnabled
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(red ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 13)
                .frame(height: 28)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(red ? .regular.tint(.red.opacity(0.2)).interactive() : .regular.interactive(), in: .capsule)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: red)
    }
}

struct EmptyState: View {
    let searching: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: searching ? "magnifyingglass" : "doc.on.clipboard")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
                .symbolEffect(.bounce, value: searching)
            Text(searching ? "No matches" : "Nothing copied yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            if !searching {
                Text("Copy something and it will show up here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.bottom, 30)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Bindable var settings: Settings
    let store: ClipboardStore
    @Bindable var model: PanelModel
    let controller: PanelController

    @State private var trusted = Paster.isTrusted

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button(action: controller.toggleSettings) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)

                Text("Settings")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
            }
            .padding(.bottom, 4)

            section {
                row("Shortcut", subtitle: "Opens Kairos from anywhere") {
                    ShortcutButton(settings: settings, model: model, controller: controller)
                }
                divider
                row("Opens at", subtitle: "Falls back to screen center when needed") {
                    Picker("", selection: $settings.position) {
                        ForEach(PopupPosition.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                divider
                row("History size", subtitle: "Older items drop off automatically") {
                    HStack(spacing: 8) {
                        Text("\(settings.maxItems)")
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(settings.maxItems)))
                            .frame(minWidth: 28, alignment: .trailing)
                        Stepper("", value: $settings.maxItems, in: 10...200, step: 10)
                            .labelsHidden()
                    }
                    .animation(.snappy, value: settings.maxItems)
                }
                divider
                row("Start at login") {
                    Toggle("", isOn: Binding(get: { settings.launchAtLogin },
                                             set: { settings.setLaunchAtLogin($0) }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            // Only shown until permission is granted.
            if !trusted {
                section {
                    row("Accessibility", subtitle: "Needed to paste for you and find your text cursor") {
                        Button("Allow") { Paster.requestAccess() }
                            .buttonStyle(.glass)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            Spacer()

            HStack {
                Text("Kairos \(version)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                DestructiveButton(title: "Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(18)
        .task { await watchAccessibility($trusted) }
        .onChange(of: settings.maxItems) { store.trim() }
    }

    private var divider: some View {
        Divider().opacity(0.5)
    }

    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .padding(.horizontal, 14)
            .background(.primary.opacity(0.05), in: .rect(cornerRadius: 18, style: .continuous))
    }

    private func row<Trailing: View>(_ title: String, subtitle: String? = nil,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing()
        }
        .padding(.vertical, 11)
    }
}

struct ShortcutButton: View {
    let settings: Settings
    let model: PanelModel
    let controller: PanelController

    var body: some View {
        Button {
            model.recordingShortcut ? controller.stopRecording() : controller.startRecording()
        } label: {
            Text(model.recordingShortcut ? "Press keys…" : settings.shortcut.display)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .contentTransition(.interpolate)
                .padding(.horizontal, 12)
                .frame(minWidth: 64, minHeight: 28)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(model.recordingShortcut ? .regular.tint(.accentColor.opacity(0.35)).interactive()
                                             : .regular.interactive(),
                     in: .capsule)
    }
}

// MARK: - Preview

struct PreviewView: View {
    let item: ClipItem
    let store: ClipboardStore
    let controller: PanelController

    var body: some View {
        VStack(spacing: 12) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button(action: controller.closePreview) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)

                    Text(heading)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Spacer()

                    Button { controller.paste(item) } label: {
                        Label("Paste", systemImage: "return")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.accentColor.opacity(0.35)).interactive(), in: .capsule)
                }
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.primary.opacity(0.05), in: .rect(cornerRadius: 18, style: .continuous))
        }
        .padding(16)
    }

    private var heading: String {
        switch item.kind {
        case .text: "Text"
        case .image: "Image"
        case .files: (item.paths?.count ?? 0) > 1 ? "Files" : "File"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:
            if let id = YouTube.videoID(in: item.text) {
                VideoPreview(id: id, link: item.text ?? "")
            } else {
                textPreview
            }
        case .image:
            if let url = store.imageURL(item), let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    .padding(12)
            }
        case .files:
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(item.paths ?? [], id: \.self) { path in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                .resizable()
                                .frame(width: 28, height: 28)
                            Text((path as NSString).abbreviatingWithTildeInPath)
                                .font(.system(size: 12))
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
    }

    private var textPreview: some View {
        ScrollView {
            Text(item.text ?? "")
                .font(.system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
        .scrollIndicators(.automatic)
    }
}

/// Large thumbnail, title and link for a copied YouTube link.
struct VideoPreview: View {
    let id: String
    let link: String

    private var previews: LinkPreviews { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Not every video has the HD thumbnail; fall back to the small one.
            AsyncImage(url: YouTube.thumbnailURL(id, large: true)) { phase in
                if let image = phase.image {
                    image.resizable()
                } else if let small = previews.thumbnails[id] {
                    Image(nsImage: small).resizable()
                } else {
                    Rectangle().fill(.primary.opacity(0.06))
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 12, style: .continuous))

            if let info = previews.info[id] {
                Text(info.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(3)
                if let channel = info.channel {
                    Text(channel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Text(link)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .task { previews.load(id) }
    }
}
