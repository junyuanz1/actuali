import XCTest

/// The transaction editor shows the payee's past charges under the form.
final class TransactionInsightUITests: XCTestCase {
    @MainActor
    func testEditingATransactionShowsThePayeesHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["-loadDemoData", "-resetStatusFilterState", "-transactionDisplayMode", "flat"]
        app.launch()

        app.tabBars.buttons["Accounts"].tap()
        let allAccounts = app.staticTexts["All Accounts"].firstMatch
        XCTAssertTrue(allAccounts.waitForExistence(timeout: 10))
        allAccounts.tap()

        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'transactionRow.' AND label CONTAINS 'Chipotle'")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the demo budget has a Chipotle transaction")
        row.tap()

        let history = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'transactionInsight.history.'")
        ).firstMatch
        scrollUntilHittable(history, in: app, maxSwipes: 10)
        XCTAssertTrue(history.exists, "the demo budget has more than one Chipotle charge")
        XCTAssertTrue(app.staticTexts["Usual amount"].exists)
    }
}
