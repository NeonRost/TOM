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
import SwiftUI

private struct KeyButton: View {
    let key: SimulatedKey
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(key.displayName)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 23, height: 23)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor : Color(nsColor: .quaternaryLabelColor))
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct IntervalRow: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        LabeledContent("Intervall") {
            HStack(spacing: 6) {
                TextField("", value: $value, format: .number)
                    .frame(width: 50)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                Stepper("Intervall", value: $value, in: range, step: step)
                    .labelsHidden()
                Text("Sekunden")
            }
        }
    }
}

private struct AccessibilityHint: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bedienungshilfen-Berechtigung fehlt.")
                .font(.caption)
                .foregroundStyle(.red)
            Button("Systemeinstellungen öffnen", action: openSettings)
                .font(.caption)
        }
    }
}

// Schreibt Einstellungsaenderungen nach UserDefaults; als eigener Modifier,
// damit der View-Body fuer den Type-Checker klein bleibt.
private struct PersistenceModifier: ViewModifier {
    @ObservedObject var keepAwake: KeepAwakeManager
    @ObservedObject var keySimulator: KeyPressSimulator
    @ObservedObject var mouseMove: MouseMoveSimulator
    @ObservedObject var mouseClick: MouseClickSimulator

    func body(content: Content) -> some View {
        content
            .onChange(of: keepAwake.isEnabled) { (newValue: Bool) in
                UserDefaults.standard.set(newValue, forKey: SettingsKeys.keepAwakeEnabled)
            }
            .onChange(of: keySimulator.isEnabled) { (newValue: Bool) in
                UserDefaults.standard.set(newValue, forKey: SettingsKeys.keySimEnabled)
            }
            .onChange(of: keySimulator.selectedKey) { (newValue: SimulatedKey) in
                UserDefaults.standard.set(Int(newValue.keyCode), forKey: SettingsKeys.selectedKeyCode)
            }
            .onChange(of: keySimulator.intervalSeconds) { (newValue: Double) in
                UserDefaults.standard.set(newValue, forKey: SettingsKeys.intervalSeconds)
            }
            .onChange(of: mouseMove.intervalSeconds) { (newValue: Double) in
                UserDefaults.standard.set(newValue, forKey: SettingsKeys.mouseMoveInterval)
            }
            .onChange(of: mouseClick.intervalSeconds) { (newValue: Double) in
                UserDefaults.standard.set(newValue, forKey: SettingsKeys.mouseClickInterval)
            }
            .onChange(of: mouseClick.buttonChoice) { (newValue: MouseButtonChoice) in
                UserDefaults.standard.set(newValue.rawValue, forKey: SettingsKeys.mouseClickButton)
            }
    }
}

struct ContentView: View {
    @ObservedObject var keepAwake: KeepAwakeManager
    @ObservedObject var keySimulator: KeyPressSimulator
    @ObservedObject var mouseMove: MouseMoveSimulator
    @ObservedObject var mouseClick: MouseClickSimulator
    @AppStorage(SettingsKeys.showMenuBarIcon) private var showMenuBarIcon = false

    private var anyMouseActive: Bool {
        mouseMove.isEnabled || mouseClick.isEnabled
    }

    var body: some View {
        mainStack
            .modifier(PersistenceModifier(
                keepAwake: keepAwake,
                keySimulator: keySimulator,
                mouseMove: mouseMove,
                mouseClick: mouseClick
            ))
    }

    private var mainStack: some View {
        VStack(spacing: 0) {
            settingsForm
            quitRow
        }
        .frame(width: 380, height: contentHeight)
    }

    private var settingsForm: some View {
        Form {
            Section {
                Toggle("Computer wachhalten", isOn: $keepAwake.isEnabled)
                    .toggleStyle(.switch)
            }

            keyPressSection
            mouseMoveSection
            mouseClickSection

            Section {
                Toggle("TOM in der Menüleiste anzeigen", isOn: $showMenuBarIcon)
                    .toggleStyle(.switch)
            }
        }
        .formStyle(.grouped)
    }

    private var quitRow: some View {
        HStack {
            Spacer()
            Button("Beenden") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    // MARK: - Abschnitte

    private var keyPressSection: some View {
        Section("Tastendruck simulieren") {
            Toggle("Tastendruck aktiv", isOn: $keySimulator.isEnabled)
                .toggleStyle(.switch)

            keyPad
                .disabled(!keySimulator.isEnabled)

            otherKeysPicker
                .disabled(!keySimulator.isEnabled)

            IntervalRow(value: $keySimulator.intervalSeconds, range: 1...600, step: 1)
                .disabled(!keySimulator.isEnabled)

            if keySimulator.accessibilityDenied {
                AccessibilityHint { keySimulator.openAccessibilitySettings() }
            }
        }
    }

    private var mouseMoveSection: some View {
        Section("Mausbewegung simulieren") {
            Toggle("Mausbewegung aktiv", isOn: $mouseMove.isEnabled)
                .toggleStyle(.switch)

            IntervalRow(value: $mouseMove.intervalSeconds, range: 1...600, step: 1)
                .disabled(!mouseMove.isEnabled)

            if mouseMove.accessibilityDenied {
                AccessibilityHint { keySimulator.openAccessibilitySettings() }
            }
        }
    }

    private var mouseClickSection: some View {
        Section {
            Toggle("Mausklick aktiv", isOn: $mouseClick.isEnabled)
                .toggleStyle(.switch)

            Picker("Maustaste", selection: $mouseClick.buttonChoice) {
                ForEach(MouseButtonChoice.allCases) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!mouseClick.isEnabled)

            IntervalRow(value: $mouseClick.intervalSeconds, range: 0.1...600, step: 0.1)
                .disabled(!mouseClick.isEnabled)

            if mouseClick.countdownRemaining > 0 {
                Text("Klick startet in \(mouseClick.countdownRemaining) s – Zeiger jetzt positionieren …")
                    .font(.callout.bold())
                    .foregroundStyle(.orange)
            }

            if mouseClick.accessibilityDenied {
                AccessibilityHint { keySimulator.openAccessibilitySettings() }
            }
        } header: {
            Text("Mausklick simulieren")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Geklickt wird dort, wo der Zeiger gerade steht. \(MouseSafety.shortcutDescription) beendet Mausklick und Mausbewegung jederzeit sofort.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if anyMouseActive {
                    Text("Not-Aus aktiv: \(MouseSafety.shortcutDescription)")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Tastenauswahl

    // Buchstabentasten in drei Reihen mit dem Versatz einer echten Tastatur;
    // Beschriftung kommt aus dem aktiven Tastaturlayout.
    private var keyPad: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(SimulatedKey.letterRows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 3) {
                    ForEach(row) { key in
                        KeyButton(key: key, isSelected: keySimulator.selectedKey == key) {
                            keySimulator.selectedKey = key
                        }
                    }
                }
                .padding(.leading, CGFloat(rowIndex) * 13)
            }
        }
        .padding(.vertical, 4)
    }

    // Bindet die Zusatzliste nur an Nicht-Buchstaben-Tasten; ist eine
    // Buchstabentaste gewaehlt, zeigt die Liste keine Auswahl ("–").
    private var otherKeyBinding: Binding<SimulatedKey?> {
        Binding(
            get: {
                SimulatedKey.others.contains(keySimulator.selectedKey) ? keySimulator.selectedKey : nil
            },
            set: { newValue in
                if let newValue {
                    keySimulator.selectedKey = newValue
                }
            }
        )
    }

    private var otherKeysPicker: some View {
        Picker("Weitere Tasten", selection: otherKeyBinding) {
            Text("–").tag(SimulatedKey?.none)
            Section("Zahlen") {
                ForEach(SimulatedKey.numbers) { key in
                    Text(key.displayName).tag(Optional(key))
                }
            }
            Section("Pfeiltasten") {
                ForEach(SimulatedKey.arrows) { key in
                    Text(key.displayName).tag(Optional(key))
                }
            }
            Section("Sondertasten") {
                ForEach(SimulatedKey.special) { key in
                    Text(key.displayName).tag(Optional(key))
                }
            }
            Section("Funktionstasten") {
                ForEach(SimulatedKey.functionKeys) { key in
                    Text(key.displayName).tag(Optional(key))
                }
            }
        }
    }

    // Eine gruppierte Form meldet keine Eigenhöhe; die Fensterhöhe wird deshalb
    // aus dem sichtbaren Inhalt berechnet.
    private var contentHeight: CGFloat {
        var height: CGFloat = 872
        if keySimulator.accessibilityDenied { height += 72 }
        if mouseMove.accessibilityDenied { height += 72 }
        if mouseClick.accessibilityDenied { height += 72 }
        if mouseClick.countdownRemaining > 0 { height += 40 }
        if anyMouseActive { height += 22 }
        // Nicht hoeher als der sichtbare Bildschirm – dann scrollt die Form,
        // statt hinter Dock/Menueleiste abgeschnitten zu werden.
        let maxHeight = (NSScreen.main?.visibleFrame.height ?? 900) - 60
        return min(height, maxHeight)
    }
}
