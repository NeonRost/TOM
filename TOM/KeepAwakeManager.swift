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

import Combine
import Foundation
import IOKit.pwr_mgt

// Haelt den Mac per IOKit-Assertion wach. Beim Beenden oder Absturz gibt
// macOS die Assertion mit dem Prozess frei; sie kann also nicht haengen bleiben.
final class KeepAwakeManager: ObservableObject {
    @Published var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled {
                guard createAssertion() else {
                    isEnabled = false
                    return
                }
                runTimer.start()
            } else {
                releaseAssertion()
                runTimer.stop()
            }
            UserDefaults.standard.set(isEnabled, forKey: SettingsKeys.keepAwakeEnabled)
        }
    }
    // Nur den Ruhezustand des Macs verhindern; der Bildschirm darf ausgehen.
    @Published var allowDisplaySleep: Bool {
        didSet {
            guard allowDisplaySleep != oldValue else { return }
            UserDefaults.standard.set(allowDisplaySleep, forKey: SettingsKeys.keepAwakeAllowDisplaySleep)
            // Laufende Assertion durch eine der neuen Art ersetzen.
            if hasAssertion {
                releaseAssertion()
                if !createAssertion() { isEnabled = false }
            }
        }
    }
    @Published private(set) var assertionFailed = false

    let runTimer = RunTimer(keyPrefix: "keepAwake")

    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    private var timerChange: AnyCancellable?

    init(initiallyEnabled: Bool) {
        allowDisplaySleep = UserDefaults.standard.bool(forKey: SettingsKeys.keepAwakeAllowDisplaySleep)
        timerChange = runTimer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        runTimer.onExpire = { [weak self] in self?.isEnabled = false }
        guard initiallyEnabled else { return }
        // Mit Timer nur fortsetzen, solange das gespeicherte Ende noch nicht
        // erreicht ist; sonst den gespeicherten Zustand berichtigen.
        if runTimer.resume(), createAssertion() {
            isEnabled = true
        } else {
            runTimer.stop()
            UserDefaults.standard.set(false, forKey: SettingsKeys.keepAwakeEnabled)
        }
    }

    private func createAssertion() -> Bool {
        guard !hasAssertion else { return true }
        let type = allowDisplaySleep ? kIOPMAssertionTypePreventUserIdleSystemSleep : kIOPMAssertionTypePreventUserIdleDisplaySleep
        let reason = String(localized: "TOM is keeping the Mac awake") as CFString
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &assertionID)
        hasAssertion = (result == kIOReturnSuccess)
        assertionFailed = !hasAssertion
        return hasAssertion
    }

    private func releaseAssertion() {
        guard hasAssertion else { return }
        IOPMAssertionRelease(assertionID)
        hasAssertion = false
    }

    deinit {
        if hasAssertion {
            IOPMAssertionRelease(assertionID)
        }
    }
}
