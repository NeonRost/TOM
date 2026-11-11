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
import Carbon.HIToolbox

// Not-Aus: ⌃⌥⌘K stoppt alle Simulationen sofort, egal welche App vorne ist.
// Als systemweiter Hotkey registriert, nur solange eine Simulation laeuft:
// Er braucht keine Bedienungshilfen und wird verschluckt, statt zusaetzlich
// in der vorderen App anzukommen. Bei aktivem "Secure Input" (Passwortfelder)
// stellt macOS ihn – wie jede Tastenueberwachung – nicht zu.
final class EmergencyStop {
    static let shared = EmergencyStop()
    static let shortcutDescription = "⌃⌥⌘K"

    var isAnyActive: (() -> Bool)?
    var stopAll: (() -> Void)?

    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var activity: NSObjectProtocol?

    func activeStateChanged() {
        let active = isAnyActive?() ?? false
        if active {
            install()
        } else {
            remove()
        }
        updateActivity(active)
    }

    private func install() {
        guard hotKeys.isEmpty else { return }
        installHandlerIfNeeded()
        let base = UInt32(cmdKey | optionKey | controlKey)
        // Zusaetzlich mit Shift: Haelt TOM selbst gerade Shift gedrueckt,
        // kommt das Kuerzel mit diesem Modifier an.
        for (index, modifiers) in [base, base | UInt32(shiftKey)].enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x544F_4D21), id: UInt32(index + 1)) // "TOM!"
            let status = RegisterEventHotKey(
                UInt32(kVK_ANSI_K), modifiers, id, GetApplicationEventTarget(), 0, &ref
            )
            if status == noErr, let ref { hotKeys.append(ref) }
        }
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let emergencyStop = Unmanaged<EmergencyStop>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { emergencyStop.stopAll?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    private func remove() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
    }

    // Ohne sichtbares Fenster darf macOS TOM per App Nap drosseln – Intervalle
    // und Haltezeiten wuerden dann unregelmaessig. Den Ruhezustand des Macs
    // verhindert das bewusst nicht; dafuer ist "Mac wachhalten" da.
    private func updateActivity(_ active: Bool) {
        if active, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "TOM is simulating input"
            )
        } else if !active, let current = activity {
            ProcessInfo.processInfo.endActivity(current)
            activity = nil
        }
    }
}
