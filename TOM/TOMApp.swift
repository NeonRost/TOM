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
    // Speichert den Keycode (Tastenposition) als Zahl, nicht das Zeichen —
    // das Zeichen haengt vom aktiven Tastaturlayout ab.
    static let selectedKeyCode = "selectedKeyCode"
    static let intervalSeconds = "intervalSeconds"
    static let showMenuBarIcon = "showMenuBarIcon"
    static let mouseMoveInterval = "mouseMoveInterval"
    static let mouseClickInterval = "mouseClickInterval"
    static let mouseClickButton = "mouseClickButton"
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

    // Das Fenster ist hoch; ohne Zentrierung platziert macOS es gern so tief,
    // dass der untere Teil hinter dem Dock verschwindet.
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }?.center()
        }
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

// Eigene View, weil openWindow nur über die View-Environment verfügbar ist,
// nicht direkt im Commands-Kontext.
private struct AboutCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About TOM") {
            openWindow(id: "about")
        }
    }
}

private struct MainWindowContent: View {
    @ObservedObject var keepAwake: KeepAwakeManager
    @ObservedObject var keySimulator: KeyPressSimulator
    @ObservedObject var mouseMove: MouseMoveSimulator
    @ObservedObject var mouseClick: MouseClickSimulator
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView(keepAwake: keepAwake, keySimulator: keySimulator, mouseMove: mouseMove, mouseClick: mouseClick)
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
    @StateObject private var mouseMove: MouseMoveSimulator
    @StateObject private var mouseClick: MouseClickSimulator
    @AppStorage(SettingsKeys.showMenuBarIcon) private var showMenuBarIcon = false

    init() {
        let defaults = UserDefaults.standard
        let keepAwakeEnabled = defaults.bool(forKey: SettingsKeys.keepAwakeEnabled)
        let keySimEnabled = defaults.bool(forKey: SettingsKeys.keySimEnabled)
        let storedKeyCode = defaults.object(forKey: SettingsKeys.selectedKeyCode) as? Int
        let selectedKey = storedKeyCode.flatMap { SimulatedKey.byCode(CGKeyCode($0)) } ?? .default
        let storedInterval = defaults.double(forKey: SettingsKeys.intervalSeconds)
        let interval = storedInterval == 0 ? 30 : storedInterval
        let storedMoveInterval = defaults.double(forKey: SettingsKeys.mouseMoveInterval)
        let storedClickInterval = defaults.double(forKey: SettingsKeys.mouseClickInterval)
        let storedButton = defaults.string(forKey: SettingsKeys.mouseClickButton)
            .flatMap(MouseButtonChoice.init(rawValue:)) ?? .left

        _keepAwake = StateObject(wrappedValue: KeepAwakeManager(initiallyEnabled: keepAwakeEnabled))
        _keySimulator = StateObject(wrappedValue: KeyPressSimulator(
            initiallyEnabled: keySimEnabled,
            selectedKey: selectedKey,
            intervalSeconds: interval
        ))

        // Die Ein-Zustaende der Mausfunktionen werden bewusst NICHT gespeichert:
        // eine App, die nach dem Start unaufgefordert klickt, waere gefaehrlich.
        let move = MouseMoveSimulator(intervalSeconds: storedMoveInterval == 0 ? 30 : storedMoveInterval)
        let click = MouseClickSimulator(
            buttonChoice: storedButton,
            intervalSeconds: storedClickInterval == 0 ? 30 : storedClickInterval
        )
        move.counterpart = click
        click.counterpart = move
        MouseSafety.shared.isAnyActive = { [weak move, weak click] in
            (move?.isEnabled ?? false) || (click?.isEnabled ?? false)
        }
        MouseSafety.shared.stopAll = { [weak move, weak click] in
            move?.isEnabled = false
            click?.isEnabled = false
        }
        _mouseMove = StateObject(wrappedValue: move)
        _mouseClick = StateObject(wrappedValue: click)
    }

    var body: some Scene {
        Window("TOM", id: "main") {
            MainWindowContent(keepAwake: keepAwake, keySimulator: keySimulator, mouseMove: mouseMove, mouseClick: mouseClick, appDelegate: appDelegate)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutCommand()
            }
        }

        Window("About TOM", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        Window("GNU General Public License v3", id: "license") {
            LicenseView()
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            ContentView(keepAwake: keepAwake, keySimulator: keySimulator, mouseMove: mouseMove, mouseClick: mouseClick)
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
