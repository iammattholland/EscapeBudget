//
//  EscapeBudgetUITests.swift
//  EscapeBudgetUITests
//
//  Created by Admin on 2025-12-01.
//

import XCTest

final class EscapeBudgetUITests: XCTestCase {

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
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testAutoRuleExceptionStopsApplying() throws {
        let app = XCUIApplication()
        app.launchArguments = ["ui_testing"]
        app.launch()

        if app.tabBars.buttons["Manage"].waitForExistence(timeout: 3) {
            app.tabBars.buttons["Manage"].tap()
        }

        let menuButton = app.buttons["transactions.menu"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 8))
        menuButton.tap()

        let autoRulesButton = app.buttons["transactions.menu.autoRules"]
        XCTAssertTrue(autoRulesButton.waitForExistence(timeout: 5))
        autoRulesButton.tap()

        let addRuleButton = app.buttons["autoRules.addRule"]
        XCTAssertTrue(addRuleButton.waitForExistence(timeout: 5))
        addRuleButton.tap()

        let nameField = app.textFields["autoRuleEditor.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Rename AMZN")
        app.dismissKeyboardIfPresent()

        app.staticTexts["Match Payee"].tap()
        let matchPayeeValue = app.textFields["autoRuleEditor.matchPayeeValue"]
        XCTAssertTrue(matchPayeeValue.waitForExistence(timeout: 5))
        matchPayeeValue.focusAndType(app: app, text: "amzn")
        app.dismissKeyboardIfPresent()

        app.staticTexts["Rename Payee"].tap()
        let renameField = app.textFields["autoRuleEditor.actionRenamePayee"]
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        renameField.focusAndType(app: app, text: "Amazon")
        app.dismissKeyboardIfPresent()

        app.buttons["Create"].tap()
        app.buttons["Done"].tap()

        // Edit a transaction to match and trigger the rule.
        let firstRow = app.descendants(matching: .any).matching(identifier: "transactions.row").firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 12))
        app.openTransactionRow(firstRow)

        let payeeField = app.textFields["transactionForm.payee"]
        XCTAssertTrue(payeeField.waitForExistence(timeout: 8))
        payeeField.tap()
        payeeField.clearAndEnterText("AMZN*123")

        app.buttons["transactionForm.save"].tap()

        if app.buttons["Done"].waitForExistence(timeout: 5) {
            app.buttons["Done"].tap()
        }

        // Re-open the transaction and exclude this payee from the rule.
        XCTAssertTrue(firstRow.waitForExistence(timeout: 12))
        app.openTransactionRow(firstRow)

        let actionsButton = app.buttons["Actions"].firstMatch
        app.scrollToMakeVisible(actionsButton)
        XCTAssertTrue(actionsButton.waitForExistence(timeout: 8))
        actionsButton.tap()

        let stopApplyingButton = app.buttons["Stop applying to this payee"]
        XCTAssertTrue(stopApplyingButton.waitForExistence(timeout: 5))
        stopApplyingButton.tap()

        let confirmStop = app.buttons["transactionForm.confirmStopApplying"].firstMatch
        XCTAssertTrue(confirmStop.waitForExistence(timeout: 5))
        confirmStop.tap()

        // Set payee again; rule should NOT rename it this time.
        app.scrollToTop()
        XCTAssertTrue(payeeField.waitForExistence(timeout: 8))
        payeeField.tap()
        payeeField.clearAndEnterText("AMZN*123")
        app.buttons["transactionForm.save"].tap()

        if app.buttons["Done"].waitForExistence(timeout: 5) {
            app.buttons["Done"].tap()
        }

        // Verify the payee was not renamed to "Amazon".
        let firstRowAfterSave = app.descendants(matching: .any).matching(identifier: "transactions.row").firstMatch
        XCTAssertTrue(firstRowAfterSave.waitForExistence(timeout: 12))
        app.openTransactionRow(firstRowAfterSave)

        let payeeFieldAfterSave = app.textFields["transactionForm.payee"]
        XCTAssertTrue(payeeFieldAfterSave.waitForExistence(timeout: 8))
        XCTAssertEqual(payeeFieldAfterSave.stringValue, "AMZN*123")
    }

    @MainActor
    func testAutoRuleEditorAddAndRemoveException() throws {
        let app = XCUIApplication()
        app.launchArguments = ["ui_testing"]
        app.launch()

        if app.tabBars.buttons["Manage"].waitForExistence(timeout: 3) {
            app.tabBars.buttons["Manage"].tap()
        }

        let menuButton = app.buttons["transactions.menu"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 8))
        menuButton.tap()

        let autoRulesButton = app.buttons["transactions.menu.autoRules"]
        XCTAssertTrue(autoRulesButton.waitForExistence(timeout: 5))
        autoRulesButton.tap()

        let addRuleButton = app.buttons["autoRules.addRule"]
        XCTAssertTrue(addRuleButton.waitForExistence(timeout: 5))
        addRuleButton.tap()

        let nameField = app.textFields["autoRuleEditor.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Exception Editor Test")
        app.dismissKeyboardIfPresent()

        app.staticTexts["Match Payee"].tap()
        let matchPayeeValue = app.textFields["autoRuleEditor.matchPayeeValue"]
        XCTAssertTrue(matchPayeeValue.waitForExistence(timeout: 5))
        matchPayeeValue.focusAndType(app: app, text: "amzn")
        app.dismissKeyboardIfPresent()

        app.staticTexts["Rename Payee"].tap()
        let renameField = app.textFields["autoRuleEditor.actionRenamePayee"]
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        renameField.focusAndType(app: app, text: "Amazon")
        app.dismissKeyboardIfPresent()

        // Add exception
        let exceptionInput = app.textFields["autoRuleEditor.exceptionPayeeInput"]
        app.scrollToMakeHittable(exceptionInput)
        XCTAssertTrue(exceptionInput.waitForExistence(timeout: 8))
        exceptionInput.tap()
        exceptionInput.typeText("AMZN*123")
        app.dismissKeyboardIfPresent()

        let addExceptionButton = app.buttons["autoRuleEditor.addExceptionButton"]
        XCTAssertTrue(addExceptionButton.waitForExistence(timeout: 5))
        addExceptionButton.tap()

        // Persist the rule
        app.buttons["Create"].tap()

        // Re-open the rule and confirm exception exists
        let ruleRow = app.staticTexts["Exception Editor Test"].firstMatch
        XCTAssertTrue(ruleRow.waitForExistence(timeout: 8))
        ruleRow.tap()

        let removeExceptionButton = app.buttons["autoRuleEditor.exceptionRemoveButton.amzn_123"].firstMatch
        app.scrollToMakeHittable(removeExceptionButton)
        XCTAssertTrue(removeExceptionButton.waitForExistence(timeout: 8))

        // Remove exception (tap minus)
        removeExceptionButton.tap()

        let removeButton = app.buttons["Remove"].firstMatch
        XCTAssertTrue(removeButton.waitForExistence(timeout: 5))
        removeButton.tap()

        app.buttons["Save"].tap()

        // Re-open and confirm exception is gone
        XCTAssertTrue(ruleRow.waitForExistence(timeout: 8))
        ruleRow.tap()
        XCTAssertFalse(app.buttons["autoRuleEditor.exceptionRemoveButton.amzn_123"].exists)
    }

    @MainActor
    func testHomeInsightFixUncategorizedOpensCategorizeSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["ui_testing"]
        app.launch()

        app.selectAppTab(named: "Home")

        let row = app.otherElements["overviewInsight.row.uncategorized"].firstMatch
        app.scrollToTop()
        app.scrollToMakeHittable(row)
        XCTAssertTrue(row.waitForExistence(timeout: 25))

        let fixButton = row.buttons["overviewInsight.action.uncategorized"].firstMatch
        XCTAssertTrue(fixButton.waitForExistence(timeout: 5))
        fixButton.tap()

        XCTAssertTrue(app.navigationBars["Categorize"].waitForExistence(timeout: 12))
    }

    @MainActor
    func testHomeInsightFixRecurringExpenseOpensPayeeAndPrefillsRule() throws {
        let app = XCUIApplication()
        app.launchArguments = ["ui_testing", "ui_seed_recurring"]
        app.launch()

        app.selectAppTab(named: "Home")

        let row = app.otherElements["overviewInsight.row.recurringExpenseDetected__payee_netflix"].firstMatch
        app.scrollToTop()
        app.scrollToMakeHittable(row)
        XCTAssertTrue(row.waitForExistence(timeout: 25))

        let fixButton = row.buttons["overviewInsight.action.recurringExpenseDetected__payee_netflix"].firstMatch
        XCTAssertTrue(fixButton.waitForExistence(timeout: 5))
        fixButton.tap()

        XCTAssertTrue(app.navigationBars["Netflix"].waitForExistence(timeout: 12))
        let createRule = app.buttons["Create Rule"].firstMatch
        XCTAssertTrue(createRule.waitForExistence(timeout: 5))
        createRule.tap()

        XCTAssertTrue(app.navigationBars["New Rule"].waitForExistence(timeout: 12))

        let payeeField = app.textFields["autoRuleEditor.matchPayeeValue"].firstMatch
        XCTAssertTrue(payeeField.waitForExistence(timeout: 5))
        XCTAssertEqual(payeeField.value as? String, "netflix")

        let nameField = app.textFields["autoRuleEditor.name"].firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertEqual(nameField.value as? String, "Rule for Netflix")
    }

    @MainActor
    func testHomeInsightReviewSpendingTrendOpensExpensesDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["ui_testing", "ui_seed_trend"]
        app.launch()

        app.selectAppTab(named: "Home")

        let row = app.otherElements["overviewInsight.row.spendingTrend"].firstMatch
        app.scrollToTop()
        app.scrollToMakeHittable(row)
        XCTAssertTrue(row.waitForExistence(timeout: 25))

        let reviewButton = row.buttons["overviewInsight.action.spendingTrend"].firstMatch
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 5))
        reviewButton.tap()

        XCTAssertTrue(app.navigationBars["Expenses"].waitForExistence(timeout: 12))
    }

    @MainActor
    func testHomeInsightReviewIncomeVariationOpensIncomeDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["ui_testing", "ui_seed_income_variation"]
        app.launch()

        app.selectAppTab(named: "Home")

        let row = app.otherElements["overviewInsight.row.incomeVariation"].firstMatch
        app.scrollToTop()
        app.scrollToMakeHittable(row)
        XCTAssertTrue(row.waitForExistence(timeout: 25))

        let reviewButton = row.buttons["overviewInsight.action.incomeVariation"].firstMatch
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 5))
        reviewButton.tap()

        XCTAssertTrue(app.navigationBars["Income"].waitForExistence(timeout: 12))
    }

    @MainActor
    func testHomeInsightFixBudgetProjectionOpensBudgetFixSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["ui_testing", "ui_seed_budget_projection"]
        app.launch()

        app.selectAppTab(named: "Home")

        let row = app.otherElements["overviewInsight.row.budgetProjection__cat_Groceries"].firstMatch
        app.scrollToTop()
        app.scrollToMakeHittable(row)
        XCTAssertTrue(row.waitForExistence(timeout: 25))

        let fixButton = row.buttons["overviewInsight.action.budgetProjection__cat_Groceries"].firstMatch
        XCTAssertTrue(fixButton.waitForExistence(timeout: 5))
        fixButton.tap()

        XCTAssertTrue(app.navigationBars["Groceries"].waitForExistence(timeout: 12))
    }

    @MainActor
    func testHomeInsightFixUnusualSpendingOpensCategoryTransactions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["ui_testing", "ui_seed_unusual_spending"]
        app.launch()

        app.selectAppTab(named: "Home")

        let row = app.otherElements.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "overviewInsight.row.unusualSpending")
        ).firstMatch
        app.scrollToTop()
        app.scrollToMakeHittable(row)
        XCTAssertTrue(row.waitForExistence(timeout: 60))

        let fixButton = row.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "overviewInsight.action.unusualSpending")
        ).firstMatch
        XCTAssertTrue(fixButton.waitForExistence(timeout: 5))
        fixButton.tap()

        XCTAssertTrue(app.navigationBars["Groceries"].waitForExistence(timeout: 12))
    }

    @MainActor
    func testHomeInsightReviewSavingsOpportunityOpensExpensesDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["ui_testing", "ui_seed_savings_opportunity"]
        app.launch()

        app.selectAppTab(named: "Home")

        let row = app.otherElements["overviewInsight.row.savingsOpportunity"].firstMatch
        app.scrollToTop()
        app.scrollToMakeHittable(row)
        XCTAssertTrue(row.waitForExistence(timeout: 25))

        let reviewButton = row.buttons["overviewInsight.action.savingsOpportunity"].firstMatch
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 5))
        reviewButton.tap()

        XCTAssertTrue(app.navigationBars["Expenses"].waitForExistence(timeout: 12))
    }

    @MainActor
    func testHomeInsightReviewUpcomingBillOpensPayeeTransactions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["ui_testing", "ui_seed_upcoming_bill"]
        app.launch()

        app.selectAppTab(named: "Home")

        let row = app.otherElements["overviewInsight.row.upcomingBill__payee_upcoming_seed"].firstMatch
        app.scrollToTop()
        app.scrollToMakeHittable(row)
        XCTAssertTrue(row.waitForExistence(timeout: 25))

        let reviewButton = row.buttons["overviewInsight.action.upcomingBill__payee_upcoming_seed"].firstMatch
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 5))
        reviewButton.tap()

        XCTAssertTrue(app.navigationBars["Upcoming Seed"].waitForExistence(timeout: 12))
    }

    @MainActor
    func testHomeInsightUpcomingBillCreateRulePrefillsEditor() throws {
        let app = XCUIApplication()
        app.launchArguments = ["ui_testing", "ui_seed_upcoming_bill"]
        app.launch()

        app.selectAppTab(named: "Home")

        let row = app.otherElements["overviewInsight.row.upcomingBill__payee_upcoming_seed"].firstMatch
        app.scrollToTop()
        app.scrollToMakeHittable(row)
        XCTAssertTrue(row.waitForExistence(timeout: 25))

        let reviewButton = row.buttons["overviewInsight.action.upcomingBill__payee_upcoming_seed"].firstMatch
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 5))
        reviewButton.tap()

        XCTAssertTrue(app.navigationBars["Upcoming Seed"].waitForExistence(timeout: 12))

        let createRule = app.buttons["Create Rule"].firstMatch
        XCTAssertTrue(createRule.waitForExistence(timeout: 5))
        createRule.tap()

        XCTAssertTrue(app.navigationBars["New Rule"].waitForExistence(timeout: 12))

        let payeeField = app.textFields["autoRuleEditor.matchPayeeValue"].firstMatch
        XCTAssertTrue(payeeField.waitForExistence(timeout: 5))
        XCTAssertEqual(payeeField.value as? String, "upcoming seed")

        let nameField = app.textFields["autoRuleEditor.name"].firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertEqual(nameField.value as? String, "Rule for Upcoming Seed")
    }

    @MainActor
    func testHomeInsightUncategorizedWorksOnIPadLayout() throws {
        let app = XCUIApplication()
        app.launchArguments = ["ui_testing"]
        app.launch()

        app.selectAppTab(named: "Home")

        let row = app.otherElements["overviewInsight.row.uncategorized"].firstMatch
        app.scrollToTop()
        app.scrollToMakeHittable(row)
        XCTAssertTrue(row.waitForExistence(timeout: 25))

        let fixButton = row.buttons["overviewInsight.action.uncategorized"].firstMatch
        XCTAssertTrue(fixButton.waitForExistence(timeout: 5))
        fixButton.tap()

        XCTAssertTrue(app.navigationBars["Categorize"].waitForExistence(timeout: 12))
    }
}

private extension XCUIElement {
    func clearAndEnterText(_ text: String) {
        guard let stringValue = self.value as? String else {
            self.tap()
            self.typeText(text)
            return
        }

        self.tap()
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
        self.typeText(deleteString)
        self.typeText(text)
    }

    func focusAndType(app: XCUIApplication, text: String) {
        // Ensure focus is on this field before typing (SwiftUI Forms can keep focus on the previous field).
        for _ in 0..<3 {
            self.tap()
            if app.keyboards.firstMatch.exists { break }
            self.doubleTap()
            if app.keyboards.firstMatch.exists { break }
        }
        self.typeText(text)
    }

    var stringValue: String? {
        self.value as? String
    }
}

private extension XCUIApplication {
    func selectAppTab(named name: String) {
        if self.tabBars.buttons[name].waitForExistence(timeout: 3) {
            self.tabBars.buttons[name].tap()
            return
        }

        let candidate = self.tables.cells.staticTexts[name].firstMatch
        if candidate.waitForExistence(timeout: 5) {
            candidate.tap()
        }
    }

    func dismissKeyboardIfPresent() {
        guard self.keyboards.firstMatch.exists else { return }

        // Prefer the keyboard toolbar done button if present.
        if self.keyboards.buttons["Done"].exists {
            self.keyboards.buttons["Done"].tap()
            return
        }
        if self.toolbars.buttons["Done"].exists {
            self.toolbars.buttons["Done"].tap()
            return
        }

        // Fallback: tap outside.
        self.windows.firstMatch.tap()
    }

    func scrollToMakeVisible(_ element: XCUIElement, maxSwipes: Int = 8) {
        if element.exists { return }
        for _ in 0..<maxSwipes {
            self.swipeUp()
            if element.exists { return }
        }
    }

    func scrollToMakeHittable(_ element: XCUIElement, maxSwipes: Int = 10) {
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable { return }
            self.swipeUp()
        }
    }

    func scrollToTop(maxSwipes: Int = 10) {
        for _ in 0..<maxSwipes {
            self.swipeDown()
        }
    }

    func openTransactionRow(_ row: XCUIElement) {
        let payeeField = self.textFields["transactionForm.payee"]
        for _ in 0..<3 {
            if row.exists {
                row.tap()
            }
            if payeeField.waitForExistence(timeout: 6) {
                return
            }
            // If the tap didn't open the sheet (or it was dismissed), try again after a small scroll.
            self.swipeDown()
        }
        XCTFail("Failed to open TransactionFormView from transactions list.")
    }
}
