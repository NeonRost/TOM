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
import CoreGraphics

// Der Ein-Zustand wird bewusst nicht gespeichert: Wie die Mausfunktionen
// startet der Tastendruck nie von selbst – sonst koennte TOM nach der
// Anmeldung unsichtbar eine Taste druecken oder halten.
final class KeyPressSimulator: ObservableObject {
    @Published var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? start() : stop()
        }
    }
    @Published var selectedKey: SimulatedKey {
        didSet {
            defaults.set(Int(selectedKey.keyCode), forKey: SettingsKeys.selectedKeyCode)
            driver.restartIfRunning()
        }
    }
    @Published var mode: PressMode {
        didSet {
            guard mode != oldValue else { return }
            defaults.set(mode.rawValue, forKey: SettingsKeys.keyPressMode)
            driver.mode = mode
            driver.restartIfRunning()
        }
    }
    @Published var intervalSeconds: Double {
        didSet {
            let clamped = min(max(intervalSeconds, 1), 600)
            if clamped != intervalSeconds {
                intervalSeconds = clamped
                return
            }
            defaults.set(intervalSeconds, forKey: SettingsKeys.intervalSeconds)
            driver.interval = intervalSeconds
            if mode == .press { driver.restartIfRunning() }
        }
    }
    @Published var holdSeconds: Double {
        didSet {
            let clamped = PressTiming.clamp(holdSeconds)
            if clamped != holdSeconds {
                holdSeconds = clamped
                return
            }
            defaults.set(holdSeconds, forKey: SettingsKeys.keyHoldSeconds)
            driver.hold = holdSeconds
            if mode == .cycle { driver.restartIfRunning() }
        }
    }
    @Published var pauseSeconds: Double {
        didSet {
            let clamped = PressTiming.clamp(pauseSeconds)
            if clamped != pauseSeconds {
                pauseSeconds = clamped
                return
            }
            defaults.set(pauseSeconds, forKey: SettingsKeys.keyPauseSeconds)
            driver.pause = pauseSeconds
            if mode == .cycle { driver.restartIfRunning() }
        }
    }
    @Published private(set) var accessibilityDenied = false
    @Published private(set) var countdownRemaining = 0

    let runTimer = RunTimer(keyPrefix: "keySim")

    private let defaults = UserDefaults.standard
    private let driver = PressDriver()
    private let countdown = StartCountdown()
    private var heldKeyCode: CGKeyCode?
    private var terminateObserver: NSObjectProtocol?
    private var subscriptions = Set<AnyCancellable>()

    init(selectedKey: SimulatedKey, mode: PressMode, intervalSeconds: Double, holdSeconds: Double, pauseSeconds: Double) {
        self.selectedKey = selectedKey
        self.mode = mode
        self.intervalSeconds = intervalSeconds
        self.holdSeconds = holdSeconds
        self.pauseSeconds = pauseSeconds

        driver.mode = mode
        driver.interval = intervalSeconds
        driver.hold = holdSeconds
        driver.pause = pauseSeconds
        driver.tap = { [weak self] in self?.sendKeyPress() }
        driver.press = { [weak self] in self?.pressKeyDown() }
        driver.release = { [weak self] in self?.releaseHeldKey() }

        // Eine beim Beenden noch gehaltene Taste bliebe sonst systemweit "gedrueckt".
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.releaseHeldKey()
        }
        runTimer.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        runTimer.onExpire = { [weak self] in self?.isEnabled = false }
        AccessibilityAccess.shared.$isTrusted
            .sink { [weak self] trusted in if trusted { self?.accessibilityDenied = false } }
            .store(in: &subscriptions)
    }

    private func start() {
        guard AccessibilityAccess.shared.requestIfNeeded() else {
            accessibilityDenied = true
            isEnabled = false
            return
        }
        accessibilityDenied = false
        runTimer.start()
        countdown.start(
            onTick: { [weak self] in self?.countdownRemaining = $0 },
            onFinish: { [weak self] in self?.driver.start() }
        )
        EmergencyStop.shared.activeStateChanged()
    }

    private func stop() {
        countdown.cancel()
        countdownRemaining = 0
        driver.stop()
        runTimer.stop()
        EmergencyStop.shared.activeStateChanged()
    }

    // Wird die Berechtigung im Betrieb entzogen, verwirft macOS jedes Ereignis
    // stillschweigend – dann lieber sichtbar ausschalten.
    private func hasAccess() -> Bool {
        guard AXIsProcessTrusted() else {
            DispatchQueue.main.async { [weak self] in
                self?.accessibilityDenied = true
                self?.isEnabled = false
            }
            return false
        }
        return true
    }

    // Ein Frame-genaues Loslassen (keyDown und keyUp im selben Tick) übersehen manche
    // Spiele, die den Tastaturstatus nur einmal pro Frame abfragen statt auf das
    // Down/Up-Event zu reagieren. Deshalb wird die Taste kurz "gehalten".
    private static let tapHoldDuration: TimeInterval = 0.08

    private func sendKeyPress() {
        guard hasAccess() else { return }
        let keyCode = selectedKey.keyCode
        Self.post(keyCode, down: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.tapHoldDuration) {
            Self.post(keyCode, down: false)
        }
    }

    private func pressKeyDown() {
        guard hasAccess() else { return }
        releaseHeldKey()
        let keyCode = selectedKey.keyCode
        Self.post(keyCode, down: true)
        heldKeyCode = keyCode
    }

    private func releaseHeldKey() {
        guard let keyCode = heldKeyCode else { return }
        heldKeyCode = nil
        Self.post(keyCode, down: false)
    }

    private static func post(_ keyCode: CGKeyCode, down: Bool) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { return }
        if let modifier = modifierFlag(for: keyCode) {
            // Modifier kommen von echter Hardware als flagsChanged an, nicht als keyDown.
            event.type = .flagsChanged
            event.flags = down ? modifier : []
        } else {
            // Nur die simulierte Taste: Haelt der Nutzer gerade z. B. ⌘, wuerde
            // aus "T" sonst ⌘T.
            event.flags = []
        }
        event.post(tap: .cghidEventTap)
    }

    private static func modifierFlag(for keyCode: CGKeyCode) -> CGEventFlags? {
        switch keyCode {
        case 0x38, 0x3C: return .maskShift
        case 0x3B, 0x3E: return .maskControl
        case 0x3A, 0x3D: return .maskAlternate
        case 0x37, 0x36: return .maskCommand
        default: return nil
        }
    }

    func openAccessibilitySettings() {
        AccessibilityAccess.shared.openSettings()
    }

    deinit {
        releaseHeldKey()
        if let terminateObserver { NotificationCenter.default.removeObserver(terminateObserver) }
    }
}
