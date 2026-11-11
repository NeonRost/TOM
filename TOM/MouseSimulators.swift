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
import Combine
import CoreGraphics

// Wird die Berechtigung im Betrieb entzogen, verwirft macOS jedes Ereignis
// stillschweigend – dann lieber sichtbar ausschalten.
private func hasAccess(orElse revoke: @escaping () -> Void) -> Bool {
    guard AXIsProcessTrusted() else {
        DispatchQueue.main.async(execute: revoke)
        return false
    }
    return true
}

final class MouseMoveSimulator: ObservableObject {
    @Published var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled {
                counterpart?.isEnabled = false
                start()
            } else {
                stop()
            }
        }
    }
    @Published var intervalSeconds: Double {
        didSet {
            let clamped = min(max(intervalSeconds, 1), 600)
            if clamped != intervalSeconds {
                intervalSeconds = clamped
                return
            }
            UserDefaults.standard.set(intervalSeconds, forKey: SettingsKeys.mouseMoveInterval)
            if timer != nil { scheduleTimer() }
        }
    }
    @Published private(set) var accessibilityDenied = false
    @Published private(set) var countdownRemaining = 0

    weak var counterpart: MouseClickSimulator?
    let runTimer = RunTimer(keyPrefix: "mouseMove")

    private let countdown = StartCountdown()
    private var timer: Timer?
    private var subscriptions = Set<AnyCancellable>()

    init(intervalSeconds: Double) {
        self.intervalSeconds = intervalSeconds
        runTimer.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        runTimer.onExpire = { [weak self] in self?.isEnabled = false }
        AccessibilityAccess.shared.$isTrusted
            .sink { [weak self] trusted in if trusted { self?.accessibilityDenied = false } }
            .store(in: &subscriptions)
    }

    private func start() {
        guard AccessibilityAccess.shared.requestIfNeeded() else {
            accessibilityDenied = true
            isEnabled = false
            return
        }
        accessibilityDenied = false
        runTimer.start()
        countdown.start(
            onTick: { [weak self] in self?.countdownRemaining = $0 },
            onFinish: { [weak self] in self?.scheduleTimer() }
        )
        EmergencyStop.shared.activeStateChanged()
    }

    private func stop() {
        countdown.cancel()
        countdownRemaining = 0
        timer?.invalidate()
        timer = nil
        runTimer.stop()
        EmergencyStop.shared.activeStateChanged()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = TOM.scheduleTimer(after: intervalSeconds, repeats: true) { [weak self] in self?.jiggle() }
    }

    // Zeiger ein Pixel verschieben und sofort zurueck – kein Klick, praktisch
    // unsichtbar, zaehlt fuer das System aber als Mausaktivitaet.
    private func jiggle() {
        guard hasAccess(orElse: { [weak self] in
            self?.accessibilityDenied = true
            self?.isEnabled = false
        }) else { return }
        guard let position = CGEvent(source: nil)?.location,
              let source = CGEventSource(stateID: .hidSystemState) else { return }
        let offset = CGPoint(x: position.x + 1, y: position.y)
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: offset, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: position, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    deinit {
        timer?.invalidate()
    }
}

enum MouseButtonChoice: String, CaseIterable, Identifiable {
    case left, right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left: return String(localized: "Left")
        case .right: return String(localized: "Right")
        }
    }
}

final class MouseClickSimulator: ObservableObject {
    static let autoOffSeconds: TimeInterval = 8 * 60 * 60

    @Published var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled {
                counterpart?.isEnabled = false
                start()
            } else {
                stop()
            }
        }
    }
    // Im Klick-Modus liest click() die Taste bei jedem Klick neu; nur eine
    // gehaltene Taste muss gewechselt werden.
    @Published var buttonChoice: MouseButtonChoice {
        didSet {
            guard buttonChoice != oldValue else { return }
            UserDefaults.standard.set(buttonChoice.rawValue, forKey: SettingsKeys.mouseClickButton)
            if mode != .press { driver.restartIfRunning() }
        }
    }
    @Published var mode: PressMode {
        didSet {
            guard mode != oldValue else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: SettingsKeys.mouseClickMode)
            driver.mode = mode
            driver.restartIfRunning()
        }
    }
    @Published var intervalSeconds: Double {
        didSet {
            let clamped = min(max(intervalSeconds, 0.1), 600)
            if clamped != intervalSeconds {
                intervalSeconds = clamped
                return
            }
            UserDefaults.standard.set(intervalSeconds, forKey: SettingsKeys.mouseClickInterval)
            driver.interval = intervalSeconds
            if mode == .press { driver.restartIfRunning() }
        }
    }
    @Published var holdSeconds: Double {
        didSet {
            let clamped = PressTiming.clamp(holdSeconds)
            if clamped != holdSeconds {
                holdSeconds = clamped
                return
            }
            UserDefaults.standard.set(holdSeconds, forKey: SettingsKeys.mouseHoldSeconds)
            driver.hold = holdSeconds
            if mode == .cycle { driver.restartIfRunning() }
        }
    }
    @Published var pauseSeconds: Double {
        didSet {
            let clamped = PressTiming.clamp(pauseSeconds)
            if clamped != pauseSeconds {
                pauseSeconds = clamped
                return
            }
            UserDefaults.standard.set(pauseSeconds, forKey: SettingsKeys.mousePauseSeconds)
            driver.pause = pauseSeconds
            if mode == .cycle { driver.restartIfRunning() }
        }
    }
    @Published private(set) var countdownRemaining = 0
    @Published private(set) var accessibilityDenied = false

    weak var counterpart: MouseMoveSimulator?
    let runTimer = RunTimer(keyPrefix: "mouseClick")

    private let driver = PressDriver()
    private let countdown = StartCountdown()
    private var heldButton: MouseButtonChoice?
    private var autoOffDate: Date?
    private var autoOffTimer: Timer?
    private var terminateObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var subscriptions = Set<AnyCancellable>()

    init(buttonChoice: MouseButtonChoice, mode: PressMode, intervalSeconds: Double, holdSeconds: Double, pauseSeconds: Double) {
        self.buttonChoice = buttonChoice
        self.mode = mode
        self.intervalSeconds = intervalSeconds
        self.holdSeconds = holdSeconds
        self.pauseSeconds = pauseSeconds

        driver.mode = mode
        driver.interval = intervalSeconds
        driver.hold = holdSeconds
        driver.pause = pauseSeconds
        driver.tap = { [weak self] in self?.click() }
        driver.press = { [weak self] in self?.pressButtonDown() }
        driver.release = { [weak self] in self?.releaseHeldButton() }

        runTimer.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        runTimer.onExpire = { [weak self] in self?.isEnabled = false }
        AccessibilityAccess.shared.$isTrusted
            .sink { [weak self] trusted in if trusted { self?.accessibilityDenied = false } }
            .store(in: &subscriptions)
        // Eine beim Beenden noch gehaltene Maustaste bliebe sonst "gedrueckt".
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.releaseHeldButton()
        }
        // Timer zaehlen waehrend des Ruhezustands nicht weiter.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.autoOffIfDue()
        }
    }

    private func start() {
        guard AccessibilityAccess.shared.requestIfNeeded() else {
            accessibilityDenied = true
            isEnabled = false
            return
        }
        accessibilityDenied = false
        runTimer.start()
        countdown.start(
            onTick: { [weak self] in self?.countdownRemaining = $0 },
            onFinish: { [weak self] in self?.startClicking() }
        )
        EmergencyStop.shared.activeStateChanged()
    }

    private func startClicking() {
        driver.start()
        // Optionale Sicherheitsabschaltung (Setup), nach Uhrzeit gerechnet und
        // erst beim Ausloesen geprueft, damit ein nachtraegliches Einschalten
        // auch fuer den laufenden Klick gilt.
        let date = Date().addingTimeInterval(Self.autoOffSeconds)
        autoOffDate = date
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in self?.autoOffIfDue() }
        RunLoop.main.add(timer, forMode: .common)
        autoOffTimer = timer
    }

    private func autoOffIfDue() {
        guard isEnabled, let autoOffDate, autoOffDate <= Date(),
              UserDefaults.standard.bool(forKey: SettingsKeys.mouseClickAutoOff) else { return }
        isEnabled = false
    }

    private func stop() {
        countdown.cancel()
        countdownRemaining = 0
        driver.stop()
        runTimer.stop()
        autoOffTimer?.invalidate()
        autoOffTimer = nil
        autoOffDate = nil
        EmergencyStop.shared.activeStateChanged()
    }

    private func revokeAccess() {
        accessibilityDenied = true
        isEnabled = false
    }

    private static func eventTypes(for choice: MouseButtonChoice) -> (down: CGEventType, up: CGEventType, button: CGMouseButton) {
        choice == .left
            ? (.leftMouseDown, .leftMouseUp, .left)
            : (.rightMouseDown, .rightMouseUp, .right)
    }

    private static func post(_ type: CGEventType, button: CGMouseButton) {
        guard let position = CGEvent(source: nil)?.location,
              let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: position, mouseButton: button) else { return }
        // Ein gerade gehaltenes ⌘ des Nutzers soll keinen ⌘-Klick daraus machen.
        event.flags = []
        event.post(tap: .cghidEventTap)
    }

    // Klickt an der aktuellen Zeigerposition, ohne den Zeiger zu bewegen.
    private func click() {
        guard hasAccess(orElse: { [weak self] in self?.revokeAccess() }) else { return }
        let types = Self.eventTypes(for: buttonChoice)
        Self.post(types.down, button: types.button)
        Self.post(types.up, button: types.button)
    }

    private func pressButtonDown() {
        guard hasAccess(orElse: { [weak self] in self?.revokeAccess() }) else { return }
        releaseHeldButton()
        let types = Self.eventTypes(for: buttonChoice)
        Self.post(types.down, button: types.button)
        heldButton = buttonChoice
    }

    // Losgelassen wird dort, wo der Zeiger inzwischen steht.
    private func releaseHeldButton() {
        guard let choice = heldButton else { return }
        heldButton = nil
        let types = Self.eventTypes(for: choice)
        Self.post(types.up, button: types.button)
    }

    deinit {
        autoOffTimer?.invalidate()
        releaseHeldButton()
        if let terminateObserver { NotificationCenter.default.removeObserver(terminateObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
