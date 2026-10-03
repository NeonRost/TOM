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
import ApplicationServices
import Combine
import CoreGraphics

// Not-Aus: ⌃⌥⌘K stoppt Tastendruck, Mausklick und Mausbewegung sofort, egal
// welche App im Vordergrund ist. Der globale Monitor laeuft nur, solange eine
// der Funktionen aktiv ist.
final class EmergencyStop {
    static let shared = EmergencyStop()
    static let shortcutDescription = "⌃⌥⌘K"
    private static let requiredModifiers: NSEvent.ModifierFlags = [.command, .option, .control]

    var isAnyActive: (() -> Bool)?
    var stopAll: (() -> Void)?
    // Von TOM selbst gehaltene Modifier (etwa eine dauerhaft gedrueckte
    // Shift-Taste) duerfen den Not-Aus nicht blockieren.
    var heldModifiers: (() -> NSEvent.ModifierFlags)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    func activeStateChanged() {
        if isAnyActive?() ?? false {
            install()
        } else {
            remove()
        }
    }

    private func handle(_ event: NSEvent) {
        let ignored = (heldModifiers?() ?? []).subtracting(Self.requiredModifiers)
        let mods = event.modifierFlags
            .intersection([.command, .option, .control, .shift])
            .subtracting(ignored)
        guard event.keyCode == 0x28, mods == Self.requiredModifiers else { return }
        DispatchQueue.main.async { self.stopAll?() }
    }

    private func install() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func remove() {
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}

private func checkAccessibility() -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

final class MouseMoveSimulator: ObservableObject {
    @Published var isEnabled: Bool {
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
            if timer != nil { scheduleTimer() }
        }
    }
    @Published private(set) var accessibilityDenied = false
    @Published private(set) var countdownRemaining = 0

    static let startDelaySeconds = 5

    weak var counterpart: MouseClickSimulator?
    let runTimer = RunTimer(keyPrefix: "mouseMove")
    private var timer: Timer?
    private var countdownTimer: Timer?
    private var timerChange: AnyCancellable?

    init(intervalSeconds: Double) {
        self.isEnabled = false
        self.intervalSeconds = intervalSeconds
        timerChange = runTimer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        runTimer.onExpire = { [weak self] in self?.isEnabled = false }
    }

    private func start() {
        guard checkAccessibility() else {
            accessibilityDenied = true
            isEnabled = false
            return
        }
        accessibilityDenied = false
        runTimer.start()
        beginCountdown()
        EmergencyStop.shared.activeStateChanged()
    }

    // Startverzoegerung wie bei Tastendruck und Mausklick.
    private func beginCountdown() {
        countdownRemaining = Self.startDelaySeconds
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.countdownRemaining -= 1
            if self.countdownRemaining <= 0 {
                self.countdownTimer?.invalidate()
                self.countdownTimer = nil
                self.scheduleTimer()
            }
        }
    }

    private func stop() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownRemaining = 0
        timer?.invalidate()
        timer = nil
        runTimer.stop()
        EmergencyStop.shared.activeStateChanged()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            self?.jiggle()
        }
    }

    // Zeiger ein Pixel verschieben und sofort zurueck – kein Klick, praktisch
    // unsichtbar, zaehlt fuer das System aber als Mausaktivitaet.
    private func jiggle() {
        guard let position = CGEvent(source: nil)?.location,
              let source = CGEventSource(stateID: .hidSystemState) else { return }
        let offset = CGPoint(x: position.x + 1, y: position.y)
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: offset, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: position, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    deinit {
        timer?.invalidate()
        countdownTimer?.invalidate()
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
    static let startDelaySeconds = 5
    static let autoOffSeconds: TimeInterval = 8 * 60 * 60

    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled {
                counterpart?.isEnabled = false
                beginCountdown()
            } else {
                cancelAll()
            }
        }
    }
    // Im Klick-Modus liest click() die Taste bei jedem Klick neu; nur eine
    // gehaltene Taste muss gewechselt werden.
    @Published var buttonChoice: MouseButtonChoice {
        didSet { if buttonChoice != oldValue, mode != .press { restartIfRunning() } }
    }
    @Published var mode: PressMode {
        didSet { if mode != oldValue { restartIfRunning() } }
    }
    @Published var intervalSeconds: Double {
        didSet {
            let clamped = min(max(intervalSeconds, 0.1), 600)
            if clamped != intervalSeconds {
                intervalSeconds = clamped
                return
            }
            if mode == .press { restartIfRunning() }
        }
    }
    @Published var holdSeconds: Double {
        didSet {
            let clamped = PressTiming.clamp(holdSeconds)
            if clamped != holdSeconds {
                holdSeconds = clamped
                return
            }
            if mode == .cycle { restartIfRunning() }
        }
    }
    @Published var pauseSeconds: Double {
        didSet {
            let clamped = PressTiming.clamp(pauseSeconds)
            if clamped != pauseSeconds {
                pauseSeconds = clamped
                return
            }
            if mode == .cycle { restartIfRunning() }
        }
    }
    @Published private(set) var countdownRemaining = 0
    @Published private(set) var accessibilityDenied = false

    weak var counterpart: MouseMoveSimulator?
    let runTimer = RunTimer(keyPrefix: "mouseClick")
    private var timerChange: AnyCancellable?
    private var countdownTimer: Timer?
    private var activityTimer: Timer?
    private var autoOffWorkItem: DispatchWorkItem?
    private var isRunning = false
    private var heldButton: MouseButtonChoice?
    private var terminateObserver: NSObjectProtocol?

    init(
        buttonChoice: MouseButtonChoice,
        mode: PressMode,
        intervalSeconds: Double,
        holdSeconds: Double,
        pauseSeconds: Double
    ) {
        self.isEnabled = false
        self.buttonChoice = buttonChoice
        self.mode = mode
        self.intervalSeconds = intervalSeconds
        self.holdSeconds = holdSeconds
        self.pauseSeconds = pauseSeconds
        timerChange = runTimer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        runTimer.onExpire = { [weak self] in self?.isEnabled = false }
        // Eine beim Beenden noch gehaltene Maustaste bliebe sonst "gedrueckt".
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.releaseHeldButton()
        }
    }

    // Startverzoegerung, damit der Zeiger in Ruhe positioniert werden kann.
    private func beginCountdown() {
        guard checkAccessibility() else {
            accessibilityDenied = true
            isEnabled = false
            return
        }
        accessibilityDenied = false
        runTimer.start()
        countdownRemaining = Self.startDelaySeconds
        EmergencyStop.shared.activeStateChanged()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.countdownRemaining -= 1
            if self.countdownRemaining <= 0 {
                self.countdownTimer?.invalidate()
                self.countdownTimer = nil
                self.startClicking()
            }
        }
    }

    private func startClicking() {
        run()
        // Optionale Sicherheitsabschaltung (Setup). Erst beim Auslösen geprüft,
        // damit ein nachträgliches Einschalten auch für den laufenden Klick gilt.
        let workItem = DispatchWorkItem { [weak self] in
            guard UserDefaults.standard.bool(forKey: SettingsKeys.mouseClickAutoOff) else { return }
            self?.isEnabled = false
        }
        autoOffWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoOffSeconds, execute: workItem)
    }

    private func run() {
        isRunning = true
        switch mode {
        case .press:
            activityTimer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
                self?.click()
            }
        case .hold:
            pressButtonDown()
        case .cycle:
            beginHoldPhase()
        }
    }

    private func beginHoldPhase() {
        pressButtonDown()
        activityTimer = Timer.scheduledTimer(withTimeInterval: holdSeconds, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.releaseHeldButton()
            self.activityTimer = Timer.scheduledTimer(withTimeInterval: self.pauseSeconds, repeats: false) { [weak self] _ in
                self?.beginHoldPhase()
            }
        }
    }

    private func haltActivity() {
        activityTimer?.invalidate()
        activityTimer = nil
        releaseHeldButton()
    }

    private func restartIfRunning() {
        guard isRunning else { return }
        haltActivity()
        run()
    }

    private static func eventTypes(for choice: MouseButtonChoice) -> (down: CGEventType, up: CGEventType, button: CGMouseButton) {
        choice == .left
            ? (.leftMouseDown, .leftMouseUp, .left)
            : (.rightMouseDown, .rightMouseUp, .right)
    }

    // Klickt an der aktuellen Zeigerposition, ohne den Zeiger zu bewegen.
    private func click() {
        guard let position = CGEvent(source: nil)?.location,
              let source = CGEventSource(stateID: .hidSystemState) else { return }
        let types = Self.eventTypes(for: buttonChoice)
        CGEvent(mouseEventSource: source, mouseType: types.down, mouseCursorPosition: position, mouseButton: types.button)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: source, mouseType: types.up, mouseCursorPosition: position, mouseButton: types.button)?.post(tap: .cghidEventTap)
    }

    private func pressButtonDown() {
        releaseHeldButton()
        guard let position = CGEvent(source: nil)?.location,
              let source = CGEventSource(stateID: .hidSystemState) else { return }
        let types = Self.eventTypes(for: buttonChoice)
        CGEvent(mouseEventSource: source, mouseType: types.down, mouseCursorPosition: position, mouseButton: types.button)?.post(tap: .cghidEventTap)
        heldButton = buttonChoice
    }

    // Losgelassen wird dort, wo der Zeiger inzwischen steht.
    private func releaseHeldButton() {
        guard let choice = heldButton else { return }
        heldButton = nil
        guard let position = CGEvent(source: nil)?.location,
              let source = CGEventSource(stateID: .hidSystemState) else { return }
        let types = Self.eventTypes(for: choice)
        CGEvent(mouseEventSource: source, mouseType: types.up, mouseCursorPosition: position, mouseButton: types.button)?.post(tap: .cghidEventTap)
    }

    private func cancelAll() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        haltActivity()
        isRunning = false
        runTimer.stop()
        autoOffWorkItem?.cancel()
        autoOffWorkItem = nil
        countdownRemaining = 0
        EmergencyStop.shared.activeStateChanged()
    }

    deinit {
        countdownTimer?.invalidate()
        activityTimer?.invalidate()
        autoOffWorkItem?.cancel()
        releaseHeldButton()
        if let terminateObserver { NotificationCenter.default.removeObserver(terminateObserver) }
    }
}
