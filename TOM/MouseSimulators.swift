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
import CoreGraphics

// Not-Aus: ⌃⌥⌘K stoppt Mausklick und Mausbewegung sofort, egal welche App
// im Vordergrund ist. Der globale Monitor laeuft nur, solange eine der beiden
// Funktionen aktiv ist.
final class MouseSafety {
    static let shared = MouseSafety()
    static let shortcutDescription = "⌃⌥⌘K"

    var isAnyActive: (() -> Bool)?
    var stopAll: (() -> Void)?

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
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard event.keyCode == 0x28, mods == [.command, .option, .control] else { return }
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
    private var timer: Timer?
    private var countdownTimer: Timer?

    init(intervalSeconds: Double) {
        self.isEnabled = false
        self.intervalSeconds = intervalSeconds
    }

    private func start() {
        guard checkAccessibility() else {
            accessibilityDenied = true
            isEnabled = false
            return
        }
        accessibilityDenied = false
        beginCountdown()
        MouseSafety.shared.activeStateChanged()
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
        MouseSafety.shared.activeStateChanged()
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
    @Published var buttonChoice: MouseButtonChoice
    @Published var intervalSeconds: Double {
        didSet {
            let clamped = min(max(intervalSeconds, 0.1), 600)
            if clamped != intervalSeconds {
                intervalSeconds = clamped
                return
            }
            if clickTimer != nil { scheduleClickTimer() }
        }
    }
    @Published private(set) var countdownRemaining = 0
    @Published private(set) var accessibilityDenied = false

    weak var counterpart: MouseMoveSimulator?
    private var countdownTimer: Timer?
    private var clickTimer: Timer?
    private var autoOffWorkItem: DispatchWorkItem?

    init(buttonChoice: MouseButtonChoice, intervalSeconds: Double) {
        self.isEnabled = false
        self.buttonChoice = buttonChoice
        self.intervalSeconds = intervalSeconds
    }

    // Startverzoegerung, damit der Zeiger in Ruhe positioniert werden kann.
    private func beginCountdown() {
        guard checkAccessibility() else {
            accessibilityDenied = true
            isEnabled = false
            return
        }
        accessibilityDenied = false
        countdownRemaining = Self.startDelaySeconds
        MouseSafety.shared.activeStateChanged()
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
        scheduleClickTimer()
        let workItem = DispatchWorkItem { [weak self] in
            self?.isEnabled = false
        }
        autoOffWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoOffSeconds, execute: workItem)
    }

    private func scheduleClickTimer() {
        clickTimer?.invalidate()
        clickTimer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            self?.click()
        }
    }

    // Klickt an der aktuellen Zeigerposition, ohne den Zeiger zu bewegen.
    private func click() {
        guard let position = CGEvent(source: nil)?.location,
              let source = CGEventSource(stateID: .hidSystemState) else { return }
        let (downType, upType, button): (CGEventType, CGEventType, CGMouseButton) = buttonChoice == .left
            ? (.leftMouseDown, .leftMouseUp, .left)
            : (.rightMouseDown, .rightMouseUp, .right)
        CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: position, mouseButton: button)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: position, mouseButton: button)?.post(tap: .cghidEventTap)
    }

    private func cancelAll() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        clickTimer?.invalidate()
        clickTimer = nil
        autoOffWorkItem?.cancel()
        autoOffWorkItem = nil
        countdownRemaining = 0
        MouseSafety.shared.activeStateChanged()
    }

    deinit {
        countdownTimer?.invalidate()
        clickTimer?.invalidate()
        autoOffWorkItem?.cancel()
    }
}
