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

import Foundation
import IOKit.pwr_mgt

final class KeepAwakeManager: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? enable() : disable()
        }
    }

    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false

    init(initiallyEnabled: Bool) {
        self.isEnabled = initiallyEnabled
        if initiallyEnabled {
            enable()
        }
    }

    private func enable() {
        guard !hasAssertion else { return }
        let reason = "TOM hält den Rechner wach" as CFString
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
