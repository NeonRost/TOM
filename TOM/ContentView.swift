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

struct ContentView: View {
    @ObservedObject var keepAwake: KeepAwakeManager
    @ObservedObject var keySimulator: KeyPressSimulator
    @AppStorage(SettingsKeys.showMenuBarIcon) private var showMenuBarIcon = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle("Computer wachhalten", isOn: $keepAwake.isEnabled)
                        .toggleStyle(.switch)
                }

                Section("Tastendruck simulieren") {
                    Toggle("Tastendruck aktiv", isOn: $keySimulator.isEnabled)
                        .toggleStyle(.switch)

                    Picker("Taste", selection: $keySimulator.selectedKey) {
                        Section("Buchstaben") {
                            ForEach(SimulatedKey.letters) { key in
                                Text(key.displayName).tag(key)
                            }
                        }
                        Section("Zahlen") {
                            ForEach(SimulatedKey.numbers) { key in
                                Text(key.displayName).tag(key)
                            }
                        }
                        Section("Pfeiltasten") {
                            ForEach(SimulatedKey.arrows) { key in
                                Text(key.displayName).tag(key)
                            }
                        }
                        Section("Sondertasten") {
                            ForEach(SimulatedKey.special) { key in
                                Text(key.displayName).tag(key)
                            }
                        }
                        Section("Funktionstasten") {
                            ForEach(SimulatedKey.functionKeys) { key in
                                Text(key.displayName).tag(key)
                            }
                        }
                    }
                    .disabled(!keySimulator.isEnabled)

                    LabeledContent("Intervall") {
                        HStack(spacing: 6) {
                            TextField("", value: $keySimulator.intervalSeconds, format: .number)
                                .frame(width: 50)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                            Stepper("Intervall", value: $keySimulator.intervalSeconds, in: 1...600, step: 1)
                                .labelsHidden()
                            Text("Sekunden")
                        }
                    }
                    .disabled(!keySimulator.isEnabled)

                    if keySimulator.accessibilityDenied {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Bedienungshilfen-Berechtigung fehlt.")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Button("Systemeinstellungen öffnen") {
                                keySimulator.openAccessibilitySettings()
                            }
                            .font(.caption)
                        }
                    }
                }

                Section {
                    Toggle("TOM in der Menüleiste anzeigen", isOn: $showMenuBarIcon)
                        .toggleStyle(.switch)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Beenden") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        // Feste Höhe, weil eine gruppierte Form keine Eigenhöhe meldet; mit
        // sichtbarem Berechtigungshinweis braucht der mittlere Abschnitt mehr Platz.
        .frame(width: 380, height: keySimulator.accessibilityDenied ? 414 : 342)
        .onChange(of: keepAwake.isEnabled) { newValue in
            UserDefaults.standard.set(newValue, forKey: SettingsKeys.keepAwakeEnabled)
        }
        .onChange(of: keySimulator.isEnabled) { newValue in
            UserDefaults.standard.set(newValue, forKey: SettingsKeys.keySimEnabled)
        }
        .onChange(of: keySimulator.selectedKey) { newValue in
            UserDefaults.standard.set(newValue.id, forKey: SettingsKeys.selectedKey)
        }
        .onChange(of: keySimulator.intervalSeconds) { newValue in
            UserDefaults.standard.set(newValue, forKey: SettingsKeys.intervalSeconds)
        }
    }
}
