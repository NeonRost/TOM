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
import Combine
import SwiftUI

enum SettingsKeys {
    static let keepAwakeEnabled = "keepAwakeEnabled"
    static let keepAwakeAllowDisplaySleep = "keepAwakeAllowDisplaySleep"
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

// Naechstes Timer-Ende fuer die Menueleiste. Tickt nur, solange ein Timer
// laeuft, und dann nur alle 30 Sekunden – minutengenau reicht.
// Kein TimelineView: im Label eines MenuBarExtra loest er eine endlose
// Neuberechnung aus (100 % CPU).
final class MenuBarClock: ObservableObject {
    @Published private(set) var nearestEnd: Date?
    @Published private(set) var now = Date()

    private var timer: Timer?
    private var cancellable: AnyCancellable?

    init(timers: [RunTimer]) {
        // @Published meldet vor dem Setzen; erst im naechsten Durchlauf
        // stehen die neuen Werte in den Timern.
        cancellable = Publishers.MergeMany(timers.map { $0.$endDate.map { _ in () } })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.update(timers.compactMap(\.endDate).min())
            }
    }

    private func update(_ end: Date?) {
        now = Date()
        guard end != nearestEnd else { return }
        nearestEnd = end
        if end == nil {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            timer = scheduleTimer(after: 30, repeats: true, tolerance: 5) { [weak self] in
                self?.now = Date()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
}

// Grüner Punkt unten rechts, sobald irgendeine Funktion eingeschaltet ist.
// Läuft ein Timer, steht die kürzeste Restzeit daneben. Symbol und Zeit
// sind ein einziges, fertig gezeichnetes Bild, weil MenuBarExtra-Labels
// zusammengesetzte Views nicht zuverlässig darstellen.
private struct MenuBarLabel: View {
    @ObservedObject var keepAwake: KeepAwakeManager
    @ObservedObject var keySimulator: KeyPressSimulator
    @ObservedObject var mouseMove: MouseMoveSimulator
    @ObservedObject var mouseClick: MouseClickSimulator
    @ObservedObject var clock: MenuBarClock

    private var isAnythingActive: Bool {
        keepAwake.isEnabled || keySimulator.isEnabled || mouseMove.isEnabled || mouseClick.isEnabled
    }

    var body: some View {
        let time = clock.nearestEnd.map { Self.remaining(until: $0, now: clock.now) }
        Image(nsImage: Self.image(active: isAnythingActive, time: time))
    }

    // Restzeit als h:mm, aufgerundet auf die angefangene Minute.
    private static func remaining(until end: Date, now: Date) -> String {
        let minutes = max(Int((end.timeIntervalSince(now) / 60).rounded(.up)), 0)
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    private static let iconSize: CGFloat = 16
    private static let gap: CGFloat = 4

    private static func image(active: Bool, time: String?) -> NSImage {
        // Ziffern gleicher Breite: sonst zuckt das Symbol jede Minute ein wenig.
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        let textWidth = time.map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) } ?? 0
        let width = iconSize + (time == nil ? 0 : gap + textWidth)
        let image = NSImage(size: NSSize(width: width, height: iconSize), flipped: false) { rect in
            let iconRect = NSRect(x: 0, y: 0, width: iconSize, height: iconSize)
            drawIcon(in: iconRect, active: active)
            if let time {
                // Beim Zeichnen gilt das Erscheinungsbild der Menueleiste, labelColor
                // passt sich also hellem und dunklem Hintergrund an.
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
                let size = (time as NSString).size(withAttributes: attributes)
                (time as NSString).draw(
                    at: NSPoint(x: iconSize + gap, y: rect.midY - size.height / 2),
                    withAttributes: attributes
                )
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawIcon(in rect: NSRect, active: Bool) {
        if let base = NSImage(named: "MenuBarIcon") {
            let scale = min(rect.width / base.size.width, rect.height / base.size.height)
            let size = NSSize(width: base.size.width * scale, height: base.size.height * scale)
            base.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                 width: size.width, height: size.height))
        }
        guard active else { return }
        let diameter: CGFloat = 6.5
        let dot = NSRect(x: rect.maxX - diameter, y: rect.minY, width: diameter, height: diameter)
        // Ausgesparter Rand trennt den Punkt vom Glas, wie bei Badges üblich.
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(ovalIn: dot.insetBy(dx: -1.2, dy: -1.2)).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.systemGreen.setFill()
        NSBezierPath(ovalIn: dot).fill()
    }
}

@main
struct TOMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var keepAwake: KeepAwakeManager
    @StateObject private var keySimulator: KeyPressSimulator
    @StateObject private var mouseMove: MouseMoveSimulator
    @StateObject private var mouseClick: MouseClickSimulator
    @StateObject private var menuBarClock: MenuBarClock
    @AppStorage(SettingsKeys.showMenuBarIcon) private var showMenuBarIcon = false

    init() {
        // Zwei laufende TOMs würden sich Einstellungen und Not-Aus teilen und
        // doppelt Ereignisse senden: die vorhandene Instanz nach vorne holen.
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .first(where: { $0 != NSRunningApplication.current }) {
            other.activate(options: [])
            exit(0)
        }

        let defaults = UserDefaults.standard
        let keepAwakeEnabled = defaults.bool(forKey: SettingsKeys.keepAwakeEnabled)
        // Bis Version 1.1 wurde der Ein-Zustand des Tastendrucks gespeichert.
        defaults.removeObject(forKey: "keySimEnabled")
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
            selectedKey: selectedKey,
            mode: storedMode(SettingsKeys.keyPressMode),
            intervalSeconds: interval,
            holdSeconds: storedDuration(SettingsKeys.keyHoldSeconds, default: PressTiming.defaultHoldSeconds),
            pauseSeconds: storedDuration(SettingsKeys.keyPauseSeconds, default: PressTiming.defaultPauseSeconds)
        )
        _keySimulator = StateObject(wrappedValue: keySim)

        // Die Ein-Zustaende der Simulationen werden bewusst NICHT gespeichert:
        // eine App, die nach dem Start unaufgefordert tippt oder klickt, waere gefaehrlich.
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

        BatteryGuard.shared.stopAll = { [weak awake, weak keySim, weak move, weak click] in
            awake?.isEnabled = false
            keySim?.isEnabled = false
            move?.isEnabled = false
            click?.isEnabled = false
        }
        BatteryGuard.shared.start()
        _mouseMove = StateObject(wrappedValue: move)
        _mouseClick = StateObject(wrappedValue: click)
        _menuBarClock = StateObject(wrappedValue: MenuBarClock(
            timers: [awake.runTimer, keySim.runTimer, move.runTimer, click.runTimer]
        ))
    }

    var body: some Scene {
        Window(Text(verbatim: "TOM"), id: "main") {
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
            MenuBarLabel(keepAwake: keepAwake, keySimulator: keySimulator, mouseMove: mouseMove, mouseClick: mouseClick, clock: menuBarClock)
        }
        .menuBarExtraStyle(.window)
    }
}
