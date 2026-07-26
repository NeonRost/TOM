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
import CoreGraphics

final class KeyPressSimulator: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? start() : stop()
        }
    }
    @Published var selectedKey: SimulatedKey {
        didSet { rescheduleIfRunning() }
    }
    @Published var intervalSeconds: Double {
        didSet {
            let clamped = min(max(intervalSeconds, 5), 600)
            if clamped != intervalSeconds {
                intervalSeconds = clamped
                return
            }
            rescheduleIfRunning()
        }
    }
    @Published private(set) var accessibilityDenied = false

    private var timer: Timer?

    init(initiallyEnabled: Bool, selectedKey: SimulatedKey, intervalSeconds: Double) {
        self.isEnabled = false
        self.selectedKey = selectedKey
        self.intervalSeconds = intervalSeconds
        if initiallyEnabled {
            self.isEnabled = true
            start()
        }
    }

    private func start() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            accessibilityDenied = true
            isEnabled = false
            return
        }
        accessibilityDenied = false
        scheduleTimer()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func rescheduleIfRunning() {
        guard timer != nil else { return }
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            self?.sendKeyPress()
        }
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
    }
}
