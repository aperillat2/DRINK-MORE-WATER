//
//  DRINK_MORE_WATERUITests.swift
//  DRINK MORE WATERUITests
//
//  Created by AARON PERILLAT on 10/22/25.
//

import XCTest

final class DRINK_MORE_WATERUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testTapToFillReachesGoal() throws {
        let app = makeApp(resetState: true)
        app.launch()

        let glass = app.descendants(matching: .any)["waterGlass"]
        XCTAssertTrue(glass.waitForExistence(timeout: 3), "waterGlass element did not appear")

        let intakeLabel = app.staticTexts["intakeLabel"]
        XCTAssertTrue(intakeLabel.waitForExistence(timeout: 3), "intakeLabel element did not appear")
        XCTAssertTrue(intakeLabel.waitForLabel("0 / 80 oz"), "Initial intake label not reset to 0 / 80 oz")

        let totalSteps = 8
        for step in 1...totalSteps {
            glass.tap()
            let expected = "\(min(step * 10, 80)) / 80 oz"
            XCTAssertTrue(intakeLabel.waitForLabel(expected, timeout: 3), "Expected intake label to update to \(expected)")
        }

        glass.tap()
        XCTAssertTrue(intakeLabel.waitForLabel("80 / 80 oz", timeout: 3), "Intake label should stay capped at goal after extra tap")
    }

}

private extension DRINK_MORE_WATERUITests {
    func makeApp(resetState: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-UITestsSkipSplash")
        app.launchArguments.append("-UITestsForceButton")
        if resetState {
            app.launchArguments.append("-UITestsResetState")
        }
        return app
    }
}

private extension XCUIElement {
    func waitForLabel(_ value: String, timeout: TimeInterval = 2.0) -> Bool {
        let predicate = NSPredicate(format: "label == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
