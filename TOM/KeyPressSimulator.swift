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
import ApplicationServices
import Combine
import CoreGraphics

// Wie Taste bzw. Maustaste betaetigt wird: kurz im Intervall, dauerhaft
// gehalten oder abwechselnd gehalten und losgelassen.
enum PressMode: String, CaseIterable, Identifiable {
    case press, hold, cycle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .press: return String(localized: "Press")
        case .hold: return String(localized: "Hold")
        case .cycle: return String(localized: "Hold & Pause")
        }
    }
}

enum PressTiming {
    static let range: ClosedRange<Double> = 0.1...600
    static let step = 0.1
    static let defaultHoldSeconds = 2.0
    static let defaultPauseSeconds = 5.0

    static func clamp(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

final class KeyPressSimulator: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? start() : stop()
        }
    }
    @Published var selectedKey: SimulatedKey {
        didSet { restartIfRunning() }
    }
    @Published var mode: PressMode {
        didSet { if mode != oldValue { restartIfRunning() } }
    }
    @Published var intervalSeconds: Double {
        didSet {
            let clamped = min(max(intervalSeconds, 1), 600)
            if clamped != intervalSeconds {
                intervalSeconds = clamped
                return
            }
            if mode == .press { restartIfRunning() }
        }
    }
    @Published var holdSeconds: Double {
        didSet {
            let clamped = PressTiming.clamp(holdSeconds)
            if clamped != holdSeconds {
                holdSeconds = clamped
                return
            }
            if mode == .cycle { restartIfRunning() }
        }
    }
    @Published var pauseSeconds: Double {
        didSet {
            let clamped = PressTiming.clamp(pauseSeconds)
            if clamped != pauseSeconds {
                pauseSeconds = clamped
                return
            }
            if mode == .cycle { restartIfRunning() }
        }
    }
    @Published private(set) var accessibilityDenied = false
    @Published private(set) var countdownRemaining = 0

    static let startDelaySeconds = 5

    private var timer: Timer?
    private var countdownTimer: Timer?
    private var isRunning = false
    private var heldKeyCode: CGKeyCode?
    private var terminateObserver: NSObjectProtocol?
    private var timerChange: AnyCancellable?

    let runTimer = RunTimer(keyPrefix: "keySim")

    init(
        initiallyEnabled: Bool,
        selectedKey: SimulatedKey,
        mode: PressMode,
        intervalSeconds: Double,
        holdSeconds: Double,
        pauseSeconds: Double
    ) {
        self.isEnabled = false
        self.selectedKey = selectedKey
        self.mode = mode
        self.intervalSeconds = intervalSeconds
        self.holdSeconds = holdSeconds
        self.pauseSeconds = pauseSeconds
        // Eine beim Beenden noch gehaltene Taste bliebe sonst systemweit "gedrueckt".
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.releaseHeldKey()
        }
        timerChange = runTimer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        runTimer.onExpire = { [weak self] in
            self?.isEnabled = false
            // Wird sonst nur über die Oberfläche gespeichert.
            UserDefaults.standard.set(false, forKey: SettingsKeys.keySimEnabled)
        }
        if initiallyEnabled && runTimer.resume() {
            self.isEnabled = true
            start(timerAlreadyRunning: true)
        }
    }

    private func start(timerAlreadyRunning: Bool = false) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            accessibilityDenied = true
            isEnabled = false
            return
        }
        accessibilityDenied = false
        if !timerAlreadyRunning { runTimer.start() }
        beginCountdown()
        EmergencyStop.shared.activeStateChanged()
    }

    // Startverzoegerung, damit das Zielfenster in Ruhe nach vorne geholt
    // werden kann, bevor der erste Tastendruck kommt.
    private func beginCountdown() {
        countdownRemaining = Self.startDelaySeconds
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.countdownRemaining -= 1
            if self.countdownRemaining <= 0 {
                self.countdownTimer?.invalidate()
                self.countdownTimer = nil
                self.run()
            }
        }
    }

    private func stop() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownRemaining = 0
        haltActivity()
        isRunning = false
        runTimer.stop()
        EmergencyStop.shared.activeStateChanged()
    }

    private func run() {
        isRunning = true
        switch mode {
        case .press:
            timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
                self?.sendKeyPress()
            }
        case .hold:
            pressKeyDown()
        case .cycle:
            beginHoldPhase()
        }
    }

    private func beginHoldPhase() {
        pressKeyDown()
        timer = Timer.scheduledTimer(withTimeInterval: holdSeconds, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.releaseHeldKey()
            self.timer = Timer.scheduledTimer(withTimeInterval: self.pauseSeconds, repeats: false) { [weak self] _ in
                self?.beginHoldPhase()
            }
        }
    }

    private func haltActivity() {
        timer?.invalidate()
        timer = nil
        releaseHeldKey()
    }

    // Laufende Aktivitaet mit neuen Einstellungen fortsetzen; vor der ersten
    // Ausfuehrung (Countdown) gibt es nichts neu zu starten.
    private func restartIfRunning() {
        guard isRunning else { return }
        haltActivity()
        run()
    }

    var heldModifierFlags: NSEvent.ModifierFlags {
        switch heldKeyCode {
        case 0x38, 0x3C: return .shift
        case 0x3B, 0x3E: return .control
        case 0x3A, 0x3D: return .option
        case 0x37, 0x36: return .command
        default: return []
        }
    }

    private func pressKeyDown() {
        releaseHeldKey()
        let keyCode = selectedKey.keyCode
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)?.post(tap: .cghidEventTap)
        heldKeyCode = keyCode
    }

    private func releaseHeldKey() {
        guard let keyCode = heldKeyCode else { return }
        heldKeyCode = nil
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)?.post(tap: .cghidEventTap)
    }

    // Ein Frame-genaues Loslassen (keyDown und keyUp im selben Tick) übersehen manche
    // Spiele, die den Tastaturstatus nur einmal pro Frame abfragen statt auf das
    // Down/Up-Event zu reagieren. Deshalb wird die Taste kurz "gehalten".
    private static let holdDuration: TimeInterval = 0.08

    private func sendKeyPress() {
        let keyCode = selectedKey.keyCode
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)?.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDuration) {
            CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)?.post(tap: .cghidEventTap)
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    deinit {
        timer?.invalidate()
        countdownTimer?.invalidate()
        releaseHeldKey()
        if let terminateObserver { NotificationCenter.default.removeObserver(terminateObserver) }
    }
}
