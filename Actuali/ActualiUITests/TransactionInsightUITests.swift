import XCTest

/// The transaction editor links to the payee's past charges.
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

        let link = app.buttons["transactionInsight.history"]
        XCTAssertTrue(link.waitForExistence(timeout: 10), "the demo budget has more than one Chipotle charge")
        link.tap()

        XCTAssertTrue(app.staticTexts["Usual amount"].waitForExistence(timeout: 5))
        let charge = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'transactionInsight.history.'")
        ).firstMatch
        XCTAssertTrue(charge.exists)
    }
}
