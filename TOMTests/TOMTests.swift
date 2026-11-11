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

import XCTest

final class RunTimerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "TOMTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeTimer() -> RunTimer {
        RunTimer(keyPrefix: "test", defaults: defaults)
    }

    func testNextOccurrenceIsTodayWhenTheTimeIsStillAhead() {
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        let end = RunTimer.nextOccurrence(ofMinutes: 18 * 60, after: now)
        XCTAssertTrue(calendar.isDate(end, inSameDayAs: now))
        XCTAssertEqual(calendar.component(.hour, from: end), 18)
    }

    func testNextOccurrenceMovesToTomorrowWhenTheTimeHasPassed() {
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: Date())!
        let end = RunTimer.nextOccurrence(ofMinutes: 18 * 60, after: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertTrue(calendar.isDate(end, inSameDayAs: tomorrow))
    }

    func testContinuousModeHasNoEnd() {
        let timer = makeTimer()
        timer.mode = .continuous
        timer.start()
        XCTAssertNil(timer.endDate)
    }

    func testDurationSetsAndStoresTheEnd() {
        let timer = makeTimer()
        timer.mode = .duration
        timer.durationMinutes = 90
        let before = Date()
        timer.start()
        let end = try! XCTUnwrap(timer.endDate)
        XCTAssertEqual(end.timeIntervalSince(before), 90 * 60, accuracy: 2)
        XCTAssertEqual(defaults.object(forKey: "testEndDate") as? Date, end)
        timer.stop()
        XCTAssertNil(timer.endDate)
        XCTAssertNil(defaults.object(forKey: "testEndDate"))
    }

    func testDurationIsClamped() {
        let timer = makeTimer()
        timer.durationMinutes = 0
        XCTAssertEqual(timer.durationMinutes, 1)
        timer.durationMinutes = 1_000_000
        XCTAssertEqual(timer.durationMinutes, RunTimer.maxDurationMinutes)
    }

    func testResumeWithoutTimerAlwaysContinues() {
        defaults.set(TimerMode.continuous.rawValue, forKey: "testTimerMode")
        XCTAssertTrue(makeTimer().resume())
    }

    // Nach einem Neustart darf ein abgelaufenes Ende nicht wieder anspringen.
    func testResumeRefusesAnExpiredEnd() {
        defaults.set(TimerMode.until.rawValue, forKey: "testTimerMode")
        defaults.set(Date().addingTimeInterval(-60), forKey: "testEndDate")
        let timer = makeTimer()
        XCTAssertFalse(timer.resume())
        XCTAssertNil(defaults.object(forKey: "testEndDate"))
    }

    func testResumeKeepsAFutureEnd() {
        let end = Date().addingTimeInterval(600)
        defaults.set(TimerMode.duration.rawValue, forKey: "testTimerMode")
        defaults.set(end, forKey: "testEndDate")
        let timer = makeTimer()
        XCTAssertTrue(timer.resume())
        XCTAssertEqual(timer.endDate, end)
    }

    func testExpiryCallsBack() {
        defaults.set(TimerMode.duration.rawValue, forKey: "testTimerMode")
        defaults.set(Date().addingTimeInterval(0.3), forKey: "testEndDate")
        let timer = makeTimer()
        let expired = expectation(description: "expired")
        timer.onExpire = { expired.fulfill() }
        XCTAssertTrue(timer.resume())
        wait(for: [expired], timeout: 3)
        XCTAssertNil(timer.endDate)
    }
}

final class PressDriverTests: XCTestCase {
    func testPressModeTapsRepeatedly() {
        let driver = PressDriver()
        driver.mode = .press
        driver.interval = 0.1
        var taps = 0
        driver.tap = { taps += 1 }
        driver.start()
        RunLoop.main.run(until: Date().addingTimeInterval(0.55))
        driver.stop()
        XCTAssertGreaterThanOrEqual(taps, 3)
    }

    func testHoldModePressesOnceAndReleasesOnStop() {
        let driver = PressDriver()
        driver.mode = .hold
        var log: [String] = []
        driver.press = { log.append("down") }
        driver.release = { log.append("up") }
        driver.start()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(log, ["down"])
        driver.stop()
        XCTAssertEqual(log, ["down", "up"])
    }

    func testCycleModeAlternatesHoldAndPause() {
        let driver = PressDriver()
        driver.mode = .cycle
        driver.hold = 0.1
        driver.pause = 0.1
        var log: [String] = []
        driver.press = { log.append("down") }
        driver.release = { log.append("up") }
        driver.start()
        RunLoop.main.run(until: Date().addingTimeInterval(0.75))
        driver.stop()
        XCTAssertGreaterThanOrEqual(log.filter { $0 == "down" }.count, 2)
        // Streng abwechselnd: nie zweimal hintereinander gedrueckt.
        for (first, second) in zip(log, log.dropFirst()) where first == "down" {
            XCTAssertEqual(second, "up")
        }
    }

    func testRestartOnlyWhenRunning() {
        let driver = PressDriver()
        driver.mode = .hold
        var presses = 0
        driver.press = { presses += 1 }
        driver.restartIfRunning()
        XCTAssertEqual(presses, 0)
        driver.start()
        driver.restartIfRunning()
        XCTAssertEqual(presses, 2)
        driver.stop()
    }

    func testTimingIsClamped() {
        XCTAssertEqual(PressTiming.clamp(0), 0.1)
        XCTAssertEqual(PressTiming.clamp(5), 5)
        XCTAssertEqual(PressTiming.clamp(10_000), 600)
    }
}
