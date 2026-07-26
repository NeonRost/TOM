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

import CoreGraphics

struct SimulatedKey: Identifiable, Hashable {
    let id: String
    let displayName: String
    let keyCode: CGKeyCode

    private static let letterKeyCodes: [Character: CGKeyCode] = [
        "A": 0x00, "B": 0x0B, "C": 0x08, "D": 0x02, "E": 0x0E, "F": 0x03, "G": 0x05, "H": 0x04,
        "I": 0x22, "J": 0x26, "K": 0x28, "L": 0x25, "M": 0x2E, "N": 0x2D, "O": 0x1F, "P": 0x23,
        "Q": 0x0C, "R": 0x0F, "S": 0x01, "T": 0x11, "U": 0x20, "V": 0x09, "W": 0x0D, "X": 0x07,
        "Y": 0x10, "Z": 0x06
    ]

    static let letters: [SimulatedKey] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { letter in
        SimulatedKey(id: String(letter), displayName: String(letter), keyCode: letterKeyCodes[letter]!)
    }

    static let numbers: [SimulatedKey] = [
        SimulatedKey(id: "0", displayName: "0", keyCode: 0x1D),
        SimulatedKey(id: "1", displayName: "1", keyCode: 0x12),
        SimulatedKey(id: "2", displayName: "2", keyCode: 0x13),
        SimulatedKey(id: "3", displayName: "3", keyCode: 0x14),
        SimulatedKey(id: "4", displayName: "4", keyCode: 0x15),
        SimulatedKey(id: "5", displayName: "5", keyCode: 0x17),
        SimulatedKey(id: "6", displayName: "6", keyCode: 0x16),
        SimulatedKey(id: "7", displayName: "7", keyCode: 0x1A),
        SimulatedKey(id: "8", displayName: "8", keyCode: 0x1C),
        SimulatedKey(id: "9", displayName: "9", keyCode: 0x19)
    ]

    static let arrows: [SimulatedKey] = [
        SimulatedKey(id: "left", displayName: "◀ Pfeil links", keyCode: 0x7B),
        SimulatedKey(id: "right", displayName: "▶ Pfeil rechts", keyCode: 0x7C),
        SimulatedKey(id: "down", displayName: "▼ Pfeil runter", keyCode: 0x7D),
        SimulatedKey(id: "up", displayName: "▲ Pfeil hoch", keyCode: 0x7E)
    ]

    static let special: [SimulatedKey] = [
        SimulatedKey(id: "space", displayName: "Leertaste", keyCode: 0x31),
        SimulatedKey(id: "return", displayName: "Enter", keyCode: 0x24),
        SimulatedKey(id: "tab", displayName: "Tab", keyCode: 0x30),
        SimulatedKey(id: "escape", displayName: "Esc", keyCode: 0x35),
        SimulatedKey(id: "delete", displayName: "Löschen", keyCode: 0x33),
        SimulatedKey(id: "control", displayName: "Strg", keyCode: 0x3B),
        SimulatedKey(id: "shift", displayName: "Umschalt", keyCode: 0x38),
        SimulatedKey(id: "option", displayName: "Alt", keyCode: 0x3A),
        SimulatedKey(id: "command", displayName: "Cmd", keyCode: 0x37)
    ]

    // "Unsichtbare" Funktionstasten ohne Standardbelegung – praktisch, wenn keine
    // sichtbare Aktion in der jeweiligen Anwendung ausgelöst werden soll.
    static let functionKeys: [SimulatedKey] = [
        SimulatedKey(id: "f13", displayName: "F13", keyCode: 0x69),
        SimulatedKey(id: "f14", displayName: "F14", keyCode: 0x6B),
        SimulatedKey(id: "f15", displayName: "F15", keyCode: 0x71),
        SimulatedKey(id: "f16", displayName: "F16", keyCode: 0x6A),
        SimulatedKey(id: "f17", displayName: "F17", keyCode: 0x40),
        SimulatedKey(id: "f18", displayName: "F18", keyCode: 0x4F),
        SimulatedKey(id: "f19", displayName: "F19", keyCode: 0x50)
    ]

    static let all: [SimulatedKey] = letters + numbers + arrows + special + functionKeys

    static let `default`: SimulatedKey = letters.first(where: { $0.id == "W" })!
}
