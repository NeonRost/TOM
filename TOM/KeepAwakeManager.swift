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

final class KeepAwakeManager: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled {
                enable()
                runTimer.start()
            } else {
                disable()
                runTimer.stop()
            }
        }
    }

    let runTimer = RunTimer(keyPrefix: "keepAwake")

    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    private var timerChange: AnyCancellable?

    init(initiallyEnabled: Bool) {
        self.isEnabled = false
        timerChange = runTimer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        runTimer.onExpire = { [weak self] in
            self?.isEnabled = false
            // Der Schalter wird sonst nur über die Oberfläche gespeichert, die bei
            // geschlossenem Fenster nicht mitläuft.
            UserDefaults.standard.set(false, forKey: SettingsKeys.keepAwakeEnabled)
        }
        if initiallyEnabled && runTimer.resume() {
            self.isEnabled = true
            enable()
        }
    }

    private func enable() {
        guard !hasAssertion else { return }
        let reason = String(localized: "TOM is keeping the Mac awake") as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        hasAssertion = (result == kIOReturnSuccess)
    }

    private func disable() {
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
