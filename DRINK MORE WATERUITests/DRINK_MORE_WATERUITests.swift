//
//  DRINK_MORE_WATERUITests.swift
//  DRINK MORE WATERUITests
//
//  Created by AARON PERILLAT on 10/22/25.
//

import XCTest

final class DRINK_MORE_WATERUITests: XCTestCase {

    override func setUpWithError() throws {
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
    }

    // The intake label's accessibility label is the spoken form, e.g. "20 of 80 ounces"
    // (the screen shows "20 / 80 oz").

    @MainActor
    func testTapToFillReachesGoal() throws {
        let app = launchFreshApp()

        let glass = app.descendants(matching: .any)["waterGlass"]
        XCTAssertTrue(glass.waitForExistence(timeout: 3), "waterGlass element did not appear")

        let intakeLabel = app.staticTexts["intakeLabel"]
        XCTAssertTrue(intakeLabel.waitForExistence(timeout: 3), "intakeLabel element did not appear")
        XCTAssertTrue(intakeLabel.waitForLabel("0 of 80 ounces"), "Initial intake not reset to 0 / 80 oz")

        let totalSteps = 8
        for step in 1...totalSteps {
            glass.tap()
            let expected = "\(min(step * 10, 80)) of 80 ounces"
            XCTAssertTrue(intakeLabel.waitForLabel(expected, timeout: 3), "Expected intake label to update to \(expected)")
        }

        glass.tap()
        XCTAssertTrue(intakeLabel.waitForLabel("80 of 80 ounces", timeout: 3), "Intake should stay capped at goal after extra tap")
    }

    @MainActor
    func testSwitchingToMillilitersConvertsTheGoal() throws {
        let app = launchFreshApp()
        let intakeLabel = app.staticTexts["intakeLabel"]
        XCTAssertTrue(intakeLabel.waitForLabel("0 of 80 ounces", timeout: 3))

        openSettings(in: app)
        // The segment shows "ml" but is labeled in full for VoiceOver.
        let mlSegment = app.segmentedControls["volumeUnitPicker"].buttons["milliliters"]
        XCTAssertTrue(mlSegment.waitForExistence(timeout: 3), "Units picker not found in Settings")
        mlSegment.tap()
        app.buttons["Apply"].tap()

        // Numbers are formatted for the locale, so the goal reads "2,400" in English.
        XCTAssertTrue(intakeLabel.waitForLabel("0 of 2,400 milliliters", timeout: 3), "Goal should convert to 2,400 ml")
    }

    @MainActor
    func testResetTodaysIntake() throws {
        let app = launchFreshApp()
        let glass = app.descendants(matching: .any)["waterGlass"]
        let intakeLabel = app.staticTexts["intakeLabel"]
        XCTAssertTrue(glass.waitForExistence(timeout: 3))

        glass.tap()
        glass.tap()
        XCTAssertTrue(intakeLabel.waitForLabel("20 of 80 ounces", timeout: 3))

        openSettings(in: app)
        // The button is near the bottom of the list, so it may be off-screen at first.
        let reset = app.buttons["Reset today's intake"]
        for _ in 0..<3 where !reset.isHittable {
            app.swipeUp()
        }
        reset.tap()
        let resetButton = app.alerts.buttons["Reset"]
        XCTAssertTrue(resetButton.waitForExistence(timeout: 3), "Reset confirmation did not appear")
        resetButton.tap()

        // The Settings sheet may still be open after confirming; close it if so.
        let cancel = app.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 1) { cancel.tap() }

        XCTAssertTrue(intakeLabel.waitForLabel("0 of 80 ounces", timeout: 3), "Intake should be back to 0")
    }
}

private extension DRINK_MORE_WATERUITests {
    /// Launches with all saved state wiped and the splash/walkthrough skipped.
    /// The app is forced into US English, since these tests check English labels; otherwise they'd
    /// fail whenever the scheme's App Language or the simulator is set to another language.
    func launchFreshApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestsSkipSplash", "-UITestsResetState"]
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        dismissNotificationPermissionAlertIfPresent()
        return app
    }

    func openSettings(in app: XCUIApplication) {
        let gear = app.buttons["settingsButton"]
        XCTAssertTrue(gear.waitForExistence(timeout: 3), "Settings button not found")
        gear.tap()
    }

    /// On a fresh simulator the system asks for notification permission at launch.
    /// That alert belongs to SpringBoard (not the app) and blocks taps until dismissed.
    func dismissNotificationPermissionAlertIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 2) {
            allow.tap()
        }
    }
}

private extension XCUIElement {
    func waitForLabel(_ value: String, timeout: TimeInterval = 2.0) -> Bool {
        let predicate = NSPredicate(format: "label == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
