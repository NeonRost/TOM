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

import Carbon.HIToolbox
import CoreGraphics

// Keycodes bezeichnen Tastenpositionen, keine Buchstaben. Das Zeichen einer
// Position haengt vom aktiven Tastaturlayout ab (QWERTY/QWERTZ/AZERTY …) und
// wird deshalb zur Laufzeit ueber das aktuelle Layout aufgeloest.
enum KeyboardLayout {
    static func label(for keyCode: CGKeyCode) -> String {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "?"
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(rawLayoutData).takeUnretainedValue() as Data
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        var deadKeyState: UInt32 = 0
        let status = layoutData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

struct SimulatedKey: Identifiable, Hashable {
    let keyCode: CGKeyCode
    // nil = Beschriftung kommt zur Laufzeit aus dem aktiven Tastaturlayout.
    let fixedLabel: String?

    var id: CGKeyCode { keyCode }

    // SwiftUI lokalisiert nur String-Literale, keine Variablen – die
    // Uebersetzung wird deshalb hier selbst nachgeschlagen.
    var displayName: String {
        guard let fixedLabel else { return KeyboardLayout.label(for: keyCode) }
        return String(localized: String.LocalizationValue(fixedLabel))
    }

    private static func layoutKeys(_ codes: [CGKeyCode]) -> [SimulatedKey] {
        codes.map { SimulatedKey(keyCode: $0, fixedLabel: nil) }
    }

    // Die drei Buchstabenreihen als physische Tastenpositionen (ANSI),
    // von oben nach unten – auf US-Layout Q…P, A…L, Z…M.
    static let letterRows: [[SimulatedKey]] = [
        layoutKeys([0x0C, 0x0D, 0x0E, 0x0F, 0x11, 0x10, 0x20, 0x22, 0x1F, 0x23]),
        layoutKeys([0x00, 0x01, 0x02, 0x03, 0x05, 0x04, 0x26, 0x28, 0x25]),
        layoutKeys([0x06, 0x07, 0x08, 0x09, 0x0B, 0x2D, 0x2E])
    ]

    static let numbers: [SimulatedKey] = [
        SimulatedKey(keyCode: 0x1D, fixedLabel: "0"),
        SimulatedKey(keyCode: 0x12, fixedLabel: "1"),
        SimulatedKey(keyCode: 0x13, fixedLabel: "2"),
        SimulatedKey(keyCode: 0x14, fixedLabel: "3"),
        SimulatedKey(keyCode: 0x15, fixedLabel: "4"),
        SimulatedKey(keyCode: 0x17, fixedLabel: "5"),
        SimulatedKey(keyCode: 0x16, fixedLabel: "6"),
        SimulatedKey(keyCode: 0x1A, fixedLabel: "7"),
        SimulatedKey(keyCode: 0x1C, fixedLabel: "8"),
        SimulatedKey(keyCode: 0x19, fixedLabel: "9")
    ]

    static let arrows: [SimulatedKey] = [
        SimulatedKey(keyCode: 0x7B, fixedLabel: "◀ Arrow Left"),
        SimulatedKey(keyCode: 0x7C, fixedLabel: "▶ Arrow Right"),
        SimulatedKey(keyCode: 0x7D, fixedLabel: "▼ Arrow Down"),
        SimulatedKey(keyCode: 0x7E, fixedLabel: "▲ Arrow Up")
    ]

    static let special: [SimulatedKey] = [
        SimulatedKey(keyCode: 0x31, fixedLabel: "Space"),
        SimulatedKey(keyCode: 0x24, fixedLabel: "Return"),
        SimulatedKey(keyCode: 0x30, fixedLabel: "Tab"),
        SimulatedKey(keyCode: 0x35, fixedLabel: "Esc"),
        SimulatedKey(keyCode: 0x33, fixedLabel: "Delete"),
        SimulatedKey(keyCode: 0x3B, fixedLabel: "Control"),
        SimulatedKey(keyCode: 0x38, fixedLabel: "Shift"),
        SimulatedKey(keyCode: 0x3A, fixedLabel: "Option"),
        SimulatedKey(keyCode: 0x37, fixedLabel: "Command")
    ]

    // "Unsichtbare" Funktionstasten ohne Standardbelegung – praktisch, wenn keine
    // sichtbare Aktion in der jeweiligen Anwendung ausgelöst werden soll.
    static let functionKeys: [SimulatedKey] = [
        SimulatedKey(keyCode: 0x69, fixedLabel: "F13"),
        SimulatedKey(keyCode: 0x6B, fixedLabel: "F14"),
        SimulatedKey(keyCode: 0x71, fixedLabel: "F15"),
        SimulatedKey(keyCode: 0x6A, fixedLabel: "F16"),
        SimulatedKey(keyCode: 0x40, fixedLabel: "F17"),
        SimulatedKey(keyCode: 0x4F, fixedLabel: "F18"),
        SimulatedKey(keyCode: 0x50, fixedLabel: "F19")
    ]

    // Fuer die Auswahlliste alphabetisch nach der Beschriftung im aktiven
    // Layout – auf QWERTZ steht damit Z an der richtigen Stelle.
    static var letters: [SimulatedKey] {
        letterRows.flatMap { $0 }.sorted { $0.displayName < $1.displayName }
    }

    static let others: [SimulatedKey] = numbers + arrows + special + functionKeys

    static let all: [SimulatedKey] = letterRows.flatMap { $0 } + others

    static func byCode(_ code: CGKeyCode) -> SimulatedKey? {
        all.first { $0.keyCode == code }
    }

    // Position der Taste "T" – auf QWERTZ, QWERTY und AZERTY dieselbe Stelle.
    static let `default` = SimulatedKey(keyCode: 0x11, fixedLabel: nil)
}
