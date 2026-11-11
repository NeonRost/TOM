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

// Im Modus .common laufen Timer auch weiter, solange in TOM ein Menue offen
// ist; die Toleranz laesst macOS Weckvorgaenge buendeln.
@discardableResult
func scheduleTimer(
    after interval: TimeInterval,
    repeats: Bool,
    tolerance: TimeInterval? = nil,
    _ block: @escaping () -> Void
) -> Timer {
    let timer = Timer(timeInterval: interval, repeats: repeats) { _ in block() }
    timer.tolerance = tolerance ?? min(interval * 0.1, 1)
    RunLoop.main.add(timer, forMode: .common)
    return timer
}

// Gemeinsamer Ablauf fuer Tastendruck und Mausklick: kurz druecken im
// Intervall, dauerhaft halten oder abwechselnd halten und pausieren.
final class PressDriver {
    var mode: PressMode = .press
    var interval: TimeInterval = 30
    var hold: TimeInterval = PressTiming.defaultHoldSeconds
    var pause: TimeInterval = PressTiming.defaultPauseSeconds

    var tap: () -> Void = {}
    var press: () -> Void = {}
    // Muss auch ohne vorheriges press() harmlos sein.
    var release: () -> Void = {}

    private(set) var isRunning = false
    private var timer: Timer?

    func start() {
        stopTimer()
        isRunning = true
        switch mode {
        case .press:
            timer = scheduleTimer(after: interval, repeats: true) { [weak self] in self?.tap() }
        case .hold:
            press()
        case .cycle:
            holdPhase()
        }
    }

    func stop() {
        isRunning = false
        stopTimer()
        release()
    }

    // Laufenden Ablauf mit neuen Werten fortsetzen; vor dem ersten Start
    // (Countdown) gibt es nichts neu zu starten.
    func restartIfRunning() {
        guard isRunning else { return }
        stop()
        start()
    }

    private func holdPhase() {
        press()
        timer = scheduleTimer(after: hold, repeats: false) { [weak self] in
            guard let self else { return }
            self.release()
            self.timer = scheduleTimer(after: self.pause, repeats: false) { [weak self] in
                self?.holdPhase()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}

// Startverzoegerung, damit Zielfenster oder Zeiger in Ruhe vorbereitet
// werden koennen, bevor die erste Eingabe kommt.
final class StartCountdown {
    static let seconds = 5

    private var timer: Timer?
    private var remaining = 0

    func start(onTick: @escaping (Int) -> Void, onFinish: @escaping () -> Void) {
        cancel()
        remaining = Self.seconds
        onTick(remaining)
        timer = scheduleTimer(after: 1, repeats: true, tolerance: 0.05) { [weak self] in
            guard let self else { return }
            self.remaining -= 1
            onTick(self.remaining)
            if self.remaining <= 0 {
                self.cancel()
                onFinish()
            }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        remaining = 0
    }

    deinit {
        timer?.invalidate()
    }
}

// Bedienungshilfen-Berechtigung: Ohne sie verwirft macOS simulierte Eingaben
// stillschweigend. Der Status wird beim Aktivieren der App neu gelesen, damit
// ein Hinweis verschwindet, sobald die Berechtigung erteilt wurde.
final class AccessibilityAccess: ObservableObject {
    static let shared = AccessibilityAccess()

    @Published private(set) var isTrusted = AXIsProcessTrusted()

    private var activationObserver: NSObjectProtocol?

    private init() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted { isTrusted = trusted }
    }

    // Beim Einschalten: fragt bei fehlender Berechtigung einmal mit dem
    // Systemdialog nach.
    func requestIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted != isTrusted { isTrusted = trusted }
        return trusted
    }

    func openSettings() {
        // Neue Adresse seit den Systemeinstellungen von macOS 13, die alte als Rueckfall.
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }
}
