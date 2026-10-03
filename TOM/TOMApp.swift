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
    static let keyPressMode = "keyPressMode"
    static let keyHoldSeconds = "keyHoldSeconds"
    static let keyPauseSeconds = "keyPauseSeconds"
    static let mouseClickMode = "mouseClickMode"
    static let mouseHoldSeconds = "mouseHoldSeconds"
    static let mousePauseSeconds = "mousePauseSeconds"
    static let hideFromDock = "hideFromDock"
    static let mouseClickAutoOff = "mouseClickAutoOff"
    static let batteryProtectionEnabled = "batteryProtectionEnabled"
    static let batteryProtectionThreshold = "batteryProtectionThreshold"
    static let keyPressSectionExpanded = "keyPressSectionExpanded"
    static let mouseMoveSectionExpanded = "mouseMoveSectionExpanded"
    static let mouseClickSectionExpanded = "mouseClickSectionExpanded"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Wird vom Fenster-Content gesetzt, damit das Fenster auch nach dem
    // Schließen (SwiftUI gibt das NSWindow dann u. U. frei) wieder geöffnet
    // werden kann.
    var openMainWindow: (() -> Void)?

    private var defaultsObserver: NSObjectProtocol?

    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }
    }

    // Ohne Dock-Symbol nur, solange das Menüleistensymbol sichtbar ist –
    // sonst wäre TOM nirgends mehr erreichbar.
    private var menuBarOnly: Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: SettingsKeys.hideFromDock) && defaults.bool(forKey: SettingsKeys.showMenuBarIcon)
    }

    // Ohne dies beendet SwiftUI die App beim Schließen des letzten Fensters —
    // fatal, wenn das Menüleistensymbol ausgeblendet ist und Wachhalten oder
    // der Tastendruck-Timer weiterlaufen sollen.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Vor dem Start gesetzt, damit das Dock-Symbol gar nicht erst kurz auftaucht.
    func applicationWillFinishLaunching(_ notification: Notification) {
        if menuBarOnly {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let startsInMenuBarOnly = menuBarOnly
        DispatchQueue.main.async {
            if startsInMenuBarOnly {
                self.mainWindow?.close()
            } else {
                // Das Fenster ist hoch; ohne Zentrierung platziert macOS es gern
                // so tief, dass der untere Teil hinter dem Dock verschwindet.
                self.mainWindow?.center()
            }
            self.clearInitialFocus()
        }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyDockVisibility()
        }
    }

    private func applyDockVisibility() {
        let desired: NSApplication.ActivationPolicy = menuBarOnly ? .accessory : .regular
        guard NSApp.activationPolicy() != desired else { return }
        NSApp.setActivationPolicy(desired)
        // Zurück ins Dock (etwa weil das Menüleistensymbol abgeschaltet wurde):
        // Fenster zeigen, sonst bliebe nichts Sichtbares von TOM übrig.
        if desired == .regular {
            showMainWindow()
        }
    }

    private func showMainWindow() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { self.clearInitialFocus() }
    }

    // macOS legt den Fokus sonst automatisch ins erste Zahlenfeld – blau
    // umrandet, und ein versehentlicher Tastendruck ändert das Intervall.
    private func clearInitialFocus() {
        mainWindow?.makeFirstResponder(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        showMainWindow()
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

// Grüner Punkt unten rechts, sobald irgendeine Funktion eingeschaltet ist.
// Als fertig gezeichnetes Bild, weil MenuBarExtra-Labels nur Text und Bild
// zuverlässig darstellen, keine zusammengesetzten Views.
private struct MenuBarLabel: View {
    @ObservedObject var keepAwake: KeepAwakeManager
    @ObservedObject var keySimulator: KeyPressSimulator
    @ObservedObject var mouseMove: MouseMoveSimulator
    @ObservedObject var mouseClick: MouseClickSimulator

    private var isAnythingActive: Bool {
        keepAwake.isEnabled || keySimulator.isEnabled || mouseMove.isEnabled || mouseClick.isEnabled
    }

    var body: some View {
        Image(nsImage: Self.icon(active: isAnythingActive))
    }

    private static func icon(active: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            if let base = NSImage(named: "MenuBarIcon") {
                let scale = min(rect.width / base.size.width, rect.height / base.size.height)
                let size = NSSize(width: base.size.width * scale, height: base.size.height * scale)
                base.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                     width: size.width, height: size.height))
            }
            guard active else { return true }
            let diameter: CGFloat = 6.5
            let dot = NSRect(x: rect.maxX - diameter, y: rect.minY, width: diameter, height: diameter)
            // Ausgesparter Rand trennt den Punkt vom Glas, wie bei Badges üblich.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.2, dy: -1.2)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.systemGreen.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = false
        return image
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

        func storedMode(_ key: String) -> PressMode {
            defaults.string(forKey: key).flatMap(PressMode.init(rawValue:)) ?? .press
        }
        func storedDuration(_ key: String, default fallback: Double) -> Double {
            let value = defaults.double(forKey: key)
            return value == 0 ? fallback : PressTiming.clamp(value)
        }

        let awake = KeepAwakeManager(initiallyEnabled: keepAwakeEnabled)
        _keepAwake = StateObject(wrappedValue: awake)
        let keySim = KeyPressSimulator(
            initiallyEnabled: keySimEnabled,
            selectedKey: selectedKey,
            mode: storedMode(SettingsKeys.keyPressMode),
            intervalSeconds: interval,
            holdSeconds: storedDuration(SettingsKeys.keyHoldSeconds, default: PressTiming.defaultHoldSeconds),
            pauseSeconds: storedDuration(SettingsKeys.keyPauseSeconds, default: PressTiming.defaultPauseSeconds)
        )
        _keySimulator = StateObject(wrappedValue: keySim)

        // Die Ein-Zustaende der Mausfunktionen werden bewusst NICHT gespeichert:
        // eine App, die nach dem Start unaufgefordert klickt, waere gefaehrlich.
        let move = MouseMoveSimulator(intervalSeconds: storedMoveInterval == 0 ? 30 : storedMoveInterval)
        let click = MouseClickSimulator(
            buttonChoice: storedButton,
            mode: storedMode(SettingsKeys.mouseClickMode),
            intervalSeconds: storedClickInterval == 0 ? 30 : storedClickInterval,
            holdSeconds: storedDuration(SettingsKeys.mouseHoldSeconds, default: PressTiming.defaultHoldSeconds),
            pauseSeconds: storedDuration(SettingsKeys.mousePauseSeconds, default: PressTiming.defaultPauseSeconds)
        )
        move.counterpart = click
        click.counterpart = move
        let emergencyStop = EmergencyStop.shared
        emergencyStop.isAnyActive = { [weak keySim, weak move, weak click] in
            (keySim?.isEnabled ?? false) || (move?.isEnabled ?? false) || (click?.isEnabled ?? false)
        }
        emergencyStop.stopAll = { [weak keySim, weak move, weak click] in
            keySim?.isEnabled = false
            move?.isEnabled = false
            click?.isEnabled = false
        }
        emergencyStop.heldModifiers = { [weak keySim] in keySim?.heldModifierFlags ?? [] }
        // Ein beim Start automatisch fortgesetzter Tastendruck lief schon vor
        // dieser Verdrahtung an – den Not-Aus jetzt nachziehen.
        emergencyStop.activeStateChanged()

        BatteryGuard.shared.stopAll = { [weak awake, weak keySim, weak move, weak click] in
            awake?.isEnabled = false
            keySim?.isEnabled = false
            move?.isEnabled = false
            click?.isEnabled = false
            // Wird sonst nur über die Oberfläche gespeichert, die bei
            // geschlossenem Fenster nicht mitläuft.
            UserDefaults.standard.set(false, forKey: SettingsKeys.keepAwakeEnabled)
            UserDefaults.standard.set(false, forKey: SettingsKeys.keySimEnabled)
        }
        BatteryGuard.shared.start()
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
            MenuBarLabel(keepAwake: keepAwake, keySimulator: keySimulator, mouseMove: mouseMove, mouseClick: mouseClick)
        }
        .menuBarExtraStyle(.window)
    }
}
