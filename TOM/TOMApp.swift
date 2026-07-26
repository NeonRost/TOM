// TOM – menu bar utility that keeps the Mac awake and simulates periodic key presses.
// Copyright (C) 2026 NeonRost
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import AppKit
import SwiftUI

enum SettingsKeys {
    static let keepAwakeEnabled = "keepAwakeEnabled"
    static let keySimEnabled = "keySimEnabled"
    static let selectedKey = "selectedKey"
    static let intervalSeconds = "intervalSeconds"
    static let showMenuBarIcon = "showMenuBarIcon"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Wird vom Fenster-Content gesetzt, damit das Fenster auch nach dem
    // Schließen (SwiftUI gibt das NSWindow dann u. U. frei) wieder geöffnet
    // werden kann.
    var openMainWindow: (() -> Void)?

    // Ohne dies beendet SwiftUI die App beim Schließen des letzten Fensters —
    // fatal, wenn das Menüleistensymbol ausgeblendet ist und Wachhalten oder
    // der Tastendruck-Timer weiterlaufen sollen.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        if let window = sender.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
        sender.activate(ignoringOtherApps: true)
        return false
    }
}

private struct MainWindowContent: View {
    @ObservedObject var keepAwake: KeepAwakeManager
    @ObservedObject var keySimulator: KeyPressSimulator
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView(keepAwake: keepAwake, keySimulator: keySimulator)
            .onAppear {
                appDelegate.openMainWindow = { openWindow(id: "main") }
            }
    }
}

@main
struct TOMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var keepAwake: KeepAwakeManager
    @StateObject private var keySimulator: KeyPressSimulator
    @AppStorage(SettingsKeys.showMenuBarIcon) private var showMenuBarIcon = false

    init() {
        let defaults = UserDefaults.standard
        let keepAwakeEnabled = defaults.bool(forKey: SettingsKeys.keepAwakeEnabled)
        let keySimEnabled = defaults.bool(forKey: SettingsKeys.keySimEnabled)
        let storedKeyId = defaults.string(forKey: SettingsKeys.selectedKey) ?? SimulatedKey.default.id
        let selectedKey = SimulatedKey.all.first(where: { $0.id == storedKeyId }) ?? .default
        let storedInterval = defaults.double(forKey: SettingsKeys.intervalSeconds)
        let interval = storedInterval == 0 ? 1 : storedInterval

        _keepAwake = StateObject(wrappedValue: KeepAwakeManager(initiallyEnabled: keepAwakeEnabled))
        _keySimulator = StateObject(wrappedValue: KeyPressSimulator(
            initiallyEnabled: keySimEnabled,
            selectedKey: selectedKey,
            intervalSeconds: interval
        ))
    }

    var body: some Scene {
        Window("TOM", id: "main") {
            MainWindowContent(keepAwake: keepAwake, keySimulator: keySimulator, appDelegate: appDelegate)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Über TOM") {
                    AboutPanel.show()
                }
            }
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            ContentView(keepAwake: keepAwake, keySimulator: keySimulator)
        } label: {
            Image("MenuBarIcon")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 16, height: 16)
        }
        .menuBarExtraStyle(.window)
    }
}
