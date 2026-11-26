import SwiftUI

@main
struct RespireApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Respire", systemImage: "smallcircle.filled.circle") {
            ControlPanel(engine: delegate.engine)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = Engine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // pas d'icône dans le Dock
        engine.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.shutdown() // rend la main à macOS en quittant
    }
}

struct ControlPanel: View {
    @ObservedObject var engine: Engine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Respire").font(.headline)

            Picker("Mode", selection: $engine.mode) {
                ForEach(Mode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if engine.mode == .breathe || engine.mode == .steady {
                labeled(engine.mode == .breathe ? "Luminosité max" : "Luminosité",
                        value: "\(Int(engine.maxLevel * 100)) %") {
                    Slider(value: $engine.maxLevel, in: 0.05...1)
                }
            }

            if engine.mode == .breathe {
                labeled("Luminosité min", value: "\(Int(engine.minLevel * 100)) %") {
                    Slider(value: $engine.minLevel, in: 0...max(0.01, engine.maxLevel - 0.05))
                }
                labeled("Durée d'une respiration", value: String(format: "%.1f s", engine.period)) {
                    Slider(value: $engine.period, in: 1...12)
                }
            }

            Toggle("Allumer capot fermé (Mac éveillé)", isOn: $engine.glowWhenClosed)
            Toggle("Sur batterie : comportement d'origine", isOn: $engine.automaticOnBattery)

            Text(engine.status)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()
            Button("Quitter Respire") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 300)
    }

    private func labeled<C: View>(_ title: String, value: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(value).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)
            content()
        }
    }
}
