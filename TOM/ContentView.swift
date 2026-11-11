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

private struct IntervalRow: View {
    var title: LocalizedStringKey = "Interval"
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(value: $value, format: .number) { EmptyView() }
                    .frame(width: 50)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                Stepper(title, value: $value, in: range, step: step)
                    .labelsHidden()
                Text("Seconds")
            }
        }
    }
}

// Ein Ende am Folgetag mit Datum, sonst nur die Uhrzeit.
private func formattedTimerEnd(_ date: Date) -> String {
    Calendar.current.isDateInToday(date)
        ? date.formatted(date: .omitted, time: .shortened)
        : date.formatted(date: .abbreviated, time: .shortened)
}

private struct ActiveBadge: View {
    var until: Date?

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
            if let until {
                Text("Active until \(formattedTimerEnd(until))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// Section(isExpanded:) gibt es erst ab macOS 14 – deshalb eine DisclosureGroup
// als erste Zeile des Abschnitts. Läuft eine Funktion im zugeklappten
// Zustand, zeigt die Titelzeile das an.
private struct CollapsibleSection<Content: View, Footer: View>: View {
    let title: LocalizedStringKey
    @Binding var isExpanded: Bool
    var isActive = false
    var activeUntil: Date?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                content()
            } label: {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    if isActive && !isExpanded {
                        ActiveBadge(until: activeUntil)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { isExpanded.toggle() }
            }
        } footer: {
            footer()
        }
    }
}

// Luft zwischen Titel und erster Zeile. Sitzt an der ersten Zeile statt an der
// Titelzeile, sonst rutscht der Aufklapp-Pfeil aus der Titelmitte.
enum CollapsibleSectionMetrics {
    static let titleSpacing: CGFloat = 10
}

extension CollapsibleSection where Footer == EmptyView {
    init(
        title: LocalizedStringKey,
        isExpanded: Binding<Bool>,
        isActive: Bool = false,
        activeUntil: Date? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title,
            isExpanded: isExpanded,
            isActive: isActive,
            activeUntil: activeUntil,
            content: content,
            footer: { EmptyView() }
        )
    }
}

private struct DurationRow: View {
    @Binding var totalMinutes: Int

    private var hours: Binding<Int> {
        Binding(
            get: { totalMinutes / 60 },
            set: { totalMinutes = min(max($0, 0), 99) * 60 + totalMinutes % 60 }
        )
    }

    private var minutes: Binding<Int> {
        Binding(
            get: { totalMinutes % 60 },
            set: { totalMinutes = (totalMinutes / 60) * 60 + min(max($0, 0), 59) }
        )
    }

    var body: some View {
        LabeledContent("Ends after") {
            HStack(spacing: 6) {
                numberField(hours)
                Text("h")
                numberField(minutes)
                    .padding(.leading, 6)
                Text("min")
            }
        }
    }

    private func numberField(_ value: Binding<Int>) -> some View {
        TextField(value: value, format: .number) { EmptyView() }
            .frame(width: 40)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
    }
}

private struct UntilRow: View {
    @Binding var minutesSinceMidnight: Int

    private var time: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: minutesSinceMidnight / 60,
                    minute: minutesSinceMidnight % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutesSinceMidnight = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    var body: some View {
        DatePicker("Ends at", selection: time, displayedComponents: .hourAndMinute)
    }
}

// Timer-Auswahl und je nach Modus Dauer oder Uhrzeit; optional das Ende als Zeile.
private struct TimerRows: View {
    @ObservedObject var timer: RunTimer
    var showsEnd = false

    var body: some View {
        Picker("Timer", selection: $timer.mode) {
            ForEach(TimerMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        }

        switch timer.mode {
        case .continuous:
            EmptyView()
        case .duration:
            DurationRow(totalMinutes: $timer.durationMinutes)
        case .until:
            UntilRow(minutesSinceMidnight: $timer.untilMinutes)
        }

        if showsEnd, let endDate = timer.endDate {
            Text("Active until \(formattedTimerEnd(endDate))")
                .font(.caption.bold())
                .foregroundStyle(.green)
        }
    }
}

private struct ModePicker: View {
    @Binding var mode: PressMode

    var body: some View {
        Picker("Mode", selection: $mode) {
            ForEach(PressMode.allCases) { choice in
                Text(choice.displayName).tag(choice)
            }
        }
    }
}

// Je nach Modus: Intervall, nichts (dauerhaft gehalten) oder Halte- und Pausenzeit.
private struct ModeTimingRows: View {
    let mode: PressMode
    @Binding var interval: Double
    let intervalRange: ClosedRange<Double>
    let intervalStep: Double
    @Binding var hold: Double
    @Binding var pause: Double

    var body: some View {
        switch mode {
        case .press:
            IntervalRow(value: $interval, range: intervalRange, step: intervalStep)
        case .hold:
            EmptyView()
        case .cycle:
            IntervalRow(title: "Hold Time", value: $hold, range: PressTiming.range, step: PressTiming.step)
            IntervalRow(title: "Pause", value: $pause, range: PressTiming.range, step: PressTiming.step)
        }
    }

    static func rowCount(for mode: PressMode) -> Int {
        switch mode {
        case .press: return 1
        case .hold: return 0
        case .cycle: return 2
        }
    }
}

private struct AccessibilityHint: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Accessibility permission is missing.")
                .font(.caption)
                .foregroundStyle(.red)
            Button("Open System Settings", action: openSettings)
                .font(.caption)
        }
    }
}

// Ersetzt den Fensterinhalt statt eines Sheets – Sheets funktionieren im
// Menüleisten-Fenster nicht zuverlässig. Änderungen greifen erst mit
// "Übernehmen".
private struct SetupView: View {
    let onClose: () -> Void

    @AppStorage(SettingsKeys.showMenuBarIcon) private var showMenuBarIcon = false
    @AppStorage(SettingsKeys.hideFromDock) private var hideFromDock = false
    @AppStorage(SettingsKeys.mouseClickAutoOff) private var mouseClickAutoOff = false
    @AppStorage(SettingsKeys.batteryProtectionEnabled) private var batteryProtection = false
    @AppStorage(SettingsKeys.batteryProtectionThreshold) private var batteryThreshold = BatteryGuard.defaultThreshold
    @ObservedObject private var launchAtLogin = LaunchAtLogin.shared
    @Environment(\.openWindow) private var openWindow

    @State private var formHeight: CGFloat = 300
    @State private var draftShowMenuBarIcon = false
    @State private var draftHideFromDock = false
    @State private var draftLaunchAtLogin = false
    @State private var draftMouseClickAutoOff = false
    @State private var draftBatteryProtection = false
    @State private var draftBatteryThreshold = BatteryGuard.defaultThreshold

    private let hasBattery = BatteryGuard.hasBattery

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Setup") {
                    Toggle("Show TOM in the menu bar", isOn: $draftShowMenuBarIcon)
                        .toggleStyle(.switch)
                    // Ohne Menüleistensymbol wäre TOM ohne Dock-Symbol unerreichbar.
                    Toggle("Hide TOM from the Dock", isOn: $draftHideFromDock)
                        .toggleStyle(.switch)
                        .disabled(!draftShowMenuBarIcon)
                    Toggle("Launch TOM at login", isOn: $draftLaunchAtLogin)
                        .toggleStyle(.switch)
                    if launchAtLogin.needsApproval {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Allow TOM under Login Items in System Settings.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Button("Open System Settings") { launchAtLogin.openLoginItemsSettings() }
                                .font(.caption)
                        }
                    }
                    Toggle("Stop mouse click after 8 hours", isOn: $draftMouseClickAutoOff)
                        .toggleStyle(.switch)
                }

                // Macs ohne Akku brauchen den Abschnitt nicht.
                if hasBattery {
                    batterySection
                }
            }
            .formStyle(.grouped)
            .background(FormHeightReader(height: $formHeight))
            .frame(height: formHeight)

            HStack {
                // Im Nur-Menüleisten-Modus gibt es kein App-Menü mit "Über TOM".
                Button("About TOM") {
                    openWindow(id: "about")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.link)
                Spacer()
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Apply", action: apply)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)
        }
        .frame(width: 380)
        .onAppear {
            draftShowMenuBarIcon = showMenuBarIcon
            draftHideFromDock = hideFromDock
            draftLaunchAtLogin = launchAtLogin.isEnabled
            draftMouseClickAutoOff = mouseClickAutoOff
            draftBatteryProtection = batteryProtection
            draftBatteryThreshold = BatteryGuard.thresholdChoices.contains(batteryThreshold)
                ? batteryThreshold
                : BatteryGuard.defaultThreshold
        }
    }

    private var batterySection: some View {
        Section {
            Toggle("Battery protection", isOn: $draftBatteryProtection)
                .toggleStyle(.switch)
            if draftBatteryProtection {
                Picker("Switch off at", selection: $draftBatteryThreshold) {
                    ForEach(BatteryGuard.thresholdChoices, id: \.self) { percent in
                        Text(verbatim: (Double(percent) / 100).formatted(.percent)).tag(percent)
                    }
                }
            }
        } footer: {
            Text("On battery power, TOM switches off everything it is doing once the charge drops to this level. Nothing happens while the Mac is charging.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func apply() {
        showMenuBarIcon = draftShowMenuBarIcon
        hideFromDock = draftHideFromDock
        mouseClickAutoOff = draftMouseClickAutoOff
        batteryThreshold = draftBatteryThreshold
        batteryProtection = draftBatteryProtection
        if draftLaunchAtLogin != launchAtLogin.isEnabled {
            launchAtLogin.setEnabled(draftLaunchAtLogin)
        }
        // Verlangt macOS eine Freigabe, bleibt die Seite offen, damit der
        // Hinweis dazu sichtbar ist.
        if draftLaunchAtLogin && launchAtLogin.needsApproval { return }
        onClose()
    }
}

struct ContentView: View {
    @ObservedObject var keepAwake: KeepAwakeManager
    @ObservedObject var keySimulator: KeyPressSimulator
    @ObservedObject var mouseMove: MouseMoveSimulator
    @ObservedObject var mouseClick: MouseClickSimulator
    @AppStorage(SettingsKeys.keyPressSectionExpanded) private var keyPressExpanded = false
    @AppStorage(SettingsKeys.mouseMoveSectionExpanded) private var mouseMoveExpanded = false
    @AppStorage(SettingsKeys.mouseClickSectionExpanded) private var mouseClickExpanded = false
    @State private var showingSetup = false
    @State private var formHeight: CGFloat = 400

    private var anySimulationActive: Bool {
        keySimulator.isEnabled || mouseMove.isEnabled || mouseClick.isEnabled
    }

    var body: some View {
        if showingSetup {
            SetupView { showingSetup = false }
        } else {
            mainStack
        }
    }

    private var mainStack: some View {
        VStack(spacing: 0) {
            settingsForm
                .frame(height: min(formHeight, maxFormHeight))
            if anySimulationActive {
                Text("Emergency stop active: \(EmergencyStop.shortcutDescription)")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 30)
            }
            bottomRow
        }
        .frame(width: 380)
    }

    // Nicht hoeher als der sichtbare Bildschirm – dann scrollt die Form,
    // statt hinter Dock/Menueleiste abgeschnitten zu werden. Abgezogen werden
    // Titelleiste (32), Buttonzeile (58), etwas Luft und, solange er zu sehen
    // ist, der Notstopp-Hinweis.
    private var maxFormHeight: CGFloat {
        let reserve: CGFloat = anySimulationActive ? 114 : 94
        return (NSScreen.main?.visibleFrame.height ?? 900) - reserve
    }

    private var settingsForm: some View {
        Form {
            keepAwakeSection
            keyPressSection
            mouseMoveSection
            mouseClickSection
        }
        .formStyle(.grouped)
        .background(FormHeightReader(height: $formHeight))
    }

    private var bottomRow: some View {
        HStack {
            Button {
                showingSetup = true
            } label: {
                Label {
                    Text("Setup")
                } icon: {
                    Image(systemName: "wrench.and.screwdriver")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 20)
        // Gleicher Abstand wie zwischen den Abschnitten, damit der Button
        // nicht am letzten Kasten klebt.
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    // MARK: - Abschnitte

    private var keepAwakeSection: some View {
        Section {
            Toggle("Active", isOn: $keepAwake.isEnabled)
                .toggleStyle(.switch)

            Toggle("Let the display sleep", isOn: $keepAwake.allowDisplaySleep)
                .toggleStyle(.switch)

            TimerRows(timer: keepAwake.runTimer)
        } header: {
            Text("Keep Mac Awake")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if keepAwake.allowDisplaySleep {
                        Text("Keeps the Mac awake; the display may still turn off.")
                    } else {
                        Text("Keeps the display and the Mac awake.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if keepAwake.assertionFailed {
                    Text("macOS refused to keep the Mac awake.")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                }
                if let endDate = keepAwake.runTimer.endDate {
                    Text("Active until \(formattedTimerEnd(endDate))")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var keyPressSection: some View {
        CollapsibleSection(
            title: "Simulate Key Press",
            isExpanded: $keyPressExpanded,
            isActive: keySimulator.isEnabled,
            activeUntil: keySimulator.runTimer.endDate
        ) {
            Toggle("Active", isOn: $keySimulator.isEnabled)
                .toggleStyle(.switch)
                .padding(.top, CollapsibleSectionMetrics.titleSpacing)

            keyPicker

            if keySimulator.selectedKey.mayTriggerActions {
                Text("This key can trigger an action in the app in front or in macOS.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ModePicker(mode: $keySimulator.mode)

            ModeTimingRows(
                mode: keySimulator.mode,
                interval: $keySimulator.intervalSeconds,
                intervalRange: 1...600,
                intervalStep: 1,
                hold: $keySimulator.holdSeconds,
                pause: $keySimulator.pauseSeconds
            )

            TimerRows(timer: keySimulator.runTimer, showsEnd: true)

            if keySimulator.countdownRemaining > 0 {
                keyCountdownText
            }

            if keySimulator.accessibilityDenied {
                AccessibilityHint { AccessibilityAccess.shared.openSettings() }
            }
        }
    }

    private var mouseMoveSection: some View {
        CollapsibleSection(
            title: "Simulate Mouse Movement",
            isExpanded: $mouseMoveExpanded,
            isActive: mouseMove.isEnabled,
            activeUntil: mouseMove.runTimer.endDate
        ) {
            Toggle("Active", isOn: $mouseMove.isEnabled)
                .toggleStyle(.switch)
                .padding(.top, CollapsibleSectionMetrics.titleSpacing)

            if mouseClick.isEnabled {
                Text("Switching this on stops Simulate Mouse Click.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            IntervalRow(value: $mouseMove.intervalSeconds, range: 1...600, step: 1)

            TimerRows(timer: mouseMove.runTimer, showsEnd: true)

            if mouseMove.countdownRemaining > 0 {
                mouseMoveCountdownText
            }

            if mouseMove.accessibilityDenied {
                AccessibilityHint { AccessibilityAccess.shared.openSettings() }
            }
        }
    }

    private var mouseClickSection: some View {
        CollapsibleSection(
            title: "Simulate Mouse Click",
            isExpanded: $mouseClickExpanded,
            isActive: mouseClick.isEnabled,
            activeUntil: mouseClick.runTimer.endDate
        ) {
            Toggle("Active", isOn: $mouseClick.isEnabled)
                .toggleStyle(.switch)
                .padding(.top, CollapsibleSectionMetrics.titleSpacing)

            if mouseMove.isEnabled {
                Text("Switching this on stops Simulate Mouse Movement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Mouse Button", selection: $mouseClick.buttonChoice) {
                ForEach(MouseButtonChoice.allCases) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
            .pickerStyle(.segmented)

            ModePicker(mode: $mouseClick.mode)

            ModeTimingRows(
                mode: mouseClick.mode,
                interval: $mouseClick.intervalSeconds,
                intervalRange: 0.1...600,
                intervalStep: 0.1,
                hold: $mouseClick.holdSeconds,
                pause: $mouseClick.pauseSeconds
            )

            TimerRows(timer: mouseClick.runTimer, showsEnd: true)

            if mouseClick.countdownRemaining > 0 {
                mouseClickCountdownText
            }

            if mouseClick.accessibilityDenied {
                AccessibilityHint { AccessibilityAccess.shared.openSettings() }
            }
        } footer: {
            if mouseClickExpanded {
                Text("Clicks happen wherever the pointer is. \(EmergencyStop.shortcutDescription) stops all simulations immediately, at any time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Countdown-Hinweise

    // Bewusst außerhalb der generischen Abschnitts-Closures: dort wird die
    // Int-Interpolation sonst als %@ statt %lld extrahiert, und die vorhandenen
    // Übersetzungen greifen nicht mehr.
    private var keyCountdownText: some View {
        Text("Key press starts in \(keySimulator.countdownRemaining) s – bring the target window to the front now …")
            .font(.callout.bold())
            .foregroundStyle(.orange)
    }

    private var mouseMoveCountdownText: some View {
        Text("Mouse movement starts in \(mouseMove.countdownRemaining) s …")
            .font(.callout.bold())
            .foregroundStyle(.orange)
    }

    private var mouseClickCountdownText: some View {
        Text("Click starts in \(mouseClick.countdownRemaining) s – position the pointer now …")
            .font(.callout.bold())
            .foregroundStyle(.orange)
    }

    // MARK: - Tastenauswahl

    // Beschriftungen kommen aus dem aktiven Tastaturlayout, gespeichert wird
    // der Keycode (Tastenposition).
    private var keyPicker: some View {
        Picker("Key", selection: $keySimulator.selectedKey) {
            Section("Letters") {
                ForEach(SimulatedKey.letters) { key in
                    Text(key.displayName).tag(key)
                }
            }
            Section("Numbers") {
                ForEach(SimulatedKey.numbers) { key in
                    Text(key.displayName).tag(key)
                }
            }
            Section("Arrow Keys") {
                ForEach(SimulatedKey.arrows) { key in
                    Text(key.displayName).tag(key)
                }
            }
            Section("Special Keys") {
                ForEach(SimulatedKey.special) { key in
                    Text(key.displayName).tag(key)
                }
            }
            Section("Function Keys") {
                ForEach(SimulatedKey.functionKeys) { key in
                    Text(key.displayName).tag(key)
                }
            }
        }
    }

}
