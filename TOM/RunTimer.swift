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
import Foundation

enum TimerMode: String, CaseIterable, Identifiable {
    case continuous, duration, until

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .continuous: return String(localized: "∞ Continuous")
        case .duration: return String(localized: "Duration")
        case .until: return String(localized: "Until")
        }
    }
}

// Laufzeit einer Funktion: durchgehend, für eine Dauer oder bis zu einer
// Uhrzeit. Speichert sich selbst, damit ein Ende auch ohne offenes Fenster
// greift und nach einem Neustart fortgesetzt werden kann.
final class RunTimer: ObservableObject {
    static let maxDurationMinutes = 99 * 60 + 59

    @Published var mode: TimerMode {
        didSet {
            guard mode != oldValue else { return }
            defaults.set(mode.rawValue, forKey: modeKey)
            updateEndDate()
        }
    }
    @Published var durationMinutes: Int {
        didSet {
            let clamped = min(max(durationMinutes, 1), Self.maxDurationMinutes)
            if clamped != durationMinutes {
                durationMinutes = clamped
                return
            }
            defaults.set(durationMinutes, forKey: durationKey)
            if mode == .duration { updateEndDate() }
        }
    }
    // Uhrzeit als Minuten seit Mitternacht – unabhaengig von Datum und Zeitzone gespeichert.
    @Published var untilMinutes: Int {
        didSet {
            defaults.set(untilMinutes, forKey: untilKey)
            if mode == .until { updateEndDate() }
        }
    }
    @Published private(set) var endDate: Date?

    var onExpire: (() -> Void)?

    private let defaults = UserDefaults.standard
    private let modeKey: String
    private let durationKey: String
    private let untilKey: String
    private let endDateKey: String
    private var isRunning = false
    private var startDate: Date?
    private var endTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(keyPrefix: String) {
        modeKey = keyPrefix + "TimerMode"
        durationKey = keyPrefix + "DurationMinutes"
        untilKey = keyPrefix + "UntilMinutes"
        endDateKey = keyPrefix + "EndDate"

        let defaults = UserDefaults.standard
        mode = defaults.string(forKey: modeKey).flatMap(TimerMode.init(rawValue:)) ?? .continuous
        let storedDuration = defaults.integer(forKey: durationKey)
        durationMinutes = storedDuration == 0 ? 60 : min(max(storedDuration, 1), Self.maxDurationMinutes)
        untilMinutes = defaults.object(forKey: untilKey) as? Int ?? 18 * 60

        // Timer zaehlen waehrend des Ruhezustands nicht weiter; nach dem
        // Aufwachen deshalb pruefen, ob das Ende inzwischen erreicht ist.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.expireIfDue()
        }
    }

    func start() {
        isRunning = true
        startDate = Date()
        updateEndDate()
    }

    // Für den App-Start: Mit Timer nur fortsetzen, solange das gespeicherte
    // Ende noch nicht erreicht ist – sonst bliebe etwa "bis 18:00" nach einem
    // Neustart am Abend bis zum nächsten Tag aktiv.
    func resume() -> Bool {
        if mode == .continuous {
            isRunning = true
            return true
        }
        guard let stored = defaults.object(forKey: endDateKey) as? Date, stored > Date() else {
            defaults.removeObject(forKey: endDateKey)
            return false
        }
        isRunning = true
        if mode == .duration {
            startDate = stored.addingTimeInterval(-TimeInterval(durationMinutes * 60))
        }
        setEndDate(stored)
        return true
    }

    func stop() {
        isRunning = false
        startDate = nil
        setEndDate(nil)
    }

    private func updateEndDate() {
        guard isRunning else { return }
        switch mode {
        case .continuous:
            setEndDate(nil)
        case .duration:
            let start = startDate ?? Date()
            setEndDate(start.addingTimeInterval(TimeInterval(durationMinutes * 60)))
        case .until:
            setEndDate(Self.nextOccurrence(ofMinutes: untilMinutes))
        }
    }

    private func setEndDate(_ date: Date?) {
        endTimer?.invalidate()
        endTimer = nil
        endDate = date
        defaults.set(date, forKey: endDateKey)
        guard let date else { return }
        if date <= Date() {
            // Etwa eine verkürzte Dauer, die schon abgelaufen ist.
            DispatchQueue.main.async { [weak self] in self?.expireIfDue() }
            return
        }
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            self?.expireIfDue()
        }
        RunLoop.main.add(timer, forMode: .common)
        endTimer = timer
    }

    private func expireIfDue() {
        guard isRunning, let endDate, endDate <= Date() else { return }
        stop()
        onExpire?()
    }

    static func nextOccurrence(ofMinutes minutes: Int, after now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let today = calendar.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: now
        ) ?? now
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    deinit {
        endTimer?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
