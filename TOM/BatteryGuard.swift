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
import IOKit.ps

// Akkuschutz: Faellt der Ladestand im Akkubetrieb auf die eingestellte Grenze,
// schaltet TOM alles ab. Ausgeloest wird nur beim Unterschreiten – wer danach
// bewusst wieder etwas einschaltet, wird nicht bei jedem Prozentpunkt erneut
// ausgebremst.
final class BatteryGuard {
    static let shared = BatteryGuard()
    static let thresholdChoices = [5, 10, 15, 20, 25, 30, 40, 50]
    static let defaultThreshold = 20

    var stopAll: (() -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var defaultsObserver: NSObjectProtocol?
    private var wasLow = false
    private var lastEnabled: Bool?
    private var lastThreshold: Int?

    static var hasBattery: Bool { currentStatus() != nil }

    static var threshold: Int {
        let stored = UserDefaults.standard.integer(forKey: SettingsKeys.batteryProtectionThreshold)
        return stored == 0 ? defaultThreshold : stored
    }

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.batteryProtectionEnabled)
    }

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<BatteryGuard>.fromOpaque(context).takeUnretainedValue().evaluate()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.settingsMaybeChanged()
        }
        settingsMaybeChanged()
    }

    // Neu eingeschaltet oder Grenze geändert: sofort prüfen, auch wenn der
    // Ladestand schon darunter liegt.
    private func settingsMaybeChanged() {
        let enabled = isEnabled
        let threshold = Self.threshold
        guard enabled != lastEnabled || threshold != lastThreshold else { return }
        lastEnabled = enabled
        lastThreshold = threshold
        wasLow = false
        evaluate()
    }

    private func evaluate() {
        guard isEnabled, let status = Self.currentStatus() else {
            wasLow = false
            return
        }
        let isLow = status.onBattery && status.percent <= Self.threshold
        if isLow && !wasLow {
            stopAll?()
        }
        wasLow = isLow
    }

    static func currentStatus() -> (percent: Int, onBattery: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0 else { continue }
            let onBattery = description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            return (current * 100 / maximum, onBattery)
        }
        return nil
    }
}
