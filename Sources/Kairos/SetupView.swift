import AppKit
import SwiftUI

/// Keeps a binding in sync with the Accessibility permission while a view is visible.
@MainActor
func watchAccessibility(_ trusted: Binding<Bool>) async {
    while !Task.isCancelled {
        let now = Paster.isTrusted
        if trusted.wrappedValue != now {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { trusted.wrappedValue = now }
        }
        try? await Task.sleep(for: .milliseconds(600))
    }
}

/// First-run screen: grant permissions before using Kairos.
struct SetupView: View {
    @Bindable var settings: Settings
    let model: PanelModel
    let controller: PanelController

    @State private var trusted = Paster.isTrusted
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 76, height: 76)
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .padding(.bottom, 6)
                Text("Welcome to Kairos")
                    .font(.system(size: 22, weight: .semibold))
                Text("Your clipboard, right when you need it.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 30)
            .padding(.bottom, 22)
            .opacity(appeared ? 1 : 0)

            VStack(spacing: 8) {
                step(number: 1, done: trusted,
                     title: "Allow Accessibility",
                     subtitle: "Lets Kairos paste for you and open at your text cursor.") {
                    if trusted {
                        Text("Allowed")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Button("Open Settings") {
                            controller.stepAside()
                            Paster.requestAccess()
                        }
                            .buttonStyle(.glass)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                step(number: 2, done: settings.launchAtLogin,
                     title: "Start at login",
                     subtitle: "Always ready, quietly in the background.") {
                    Toggle("", isOn: Binding(get: { settings.launchAtLogin },
                                             set: { settings.setLaunchAtLogin($0) }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                step(number: 3, done: true,
                     title: "Your shortcut",
                     subtitle: "Press it anywhere. Click to change it.") {
                    ShortcutButton(settings: settings, model: model, controller: controller)
                }
            }
            .padding(.horizontal, 16)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)

            Spacer(minLength: 12)

            Button(action: controller.finishSetup) {
                Text("Start using Kairos")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!trusted)
            .padding(.horizontal, 16)

            Button("Skip for now", action: controller.finishSetup)
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 10)
                .padding(.bottom, 14)
                .opacity(trusted ? 0 : 1)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.05)) { appeared = true }
        }
        .task { await watchAccessibility($trusted) }
        .onChange(of: trusted) { _, granted in
            if granted { controller.bringToFront() }
        }
    }

    private func step<Trailing: View>(number: Int, done: Bool, title: String, subtitle: String,
                                      @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? AnyShapeStyle(Color.green.opacity(0.9)) : AnyShapeStyle(.primary.opacity(0.08)))
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("\(number)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.primary.opacity(0.05), in: .rect(cornerRadius: 18, style: .continuous))
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: done)
    }
}
