import Foundation
import GRDB
import Testing
@testable import Actuali

@MainActor
struct BudgetStoreInspectTransactionTests {
    private func transaction(
        id: String = "tx-5", amount: Int = -1999, categoryId: String? = nil, transferId: String? = nil
    ) -> Transaction {
        Transaction(
            id: id, accountId: "acct-1", date: 20_260_505, amount: amount,
            payeeId: "payee-cafe", payeeName: "Cafe", categoryId: categoryId, categoryName: nil,
            notes: nil, cleared: false, reconciled: false, transferId: transferId,
            isParent: false, parentId: nil, tombstone: false, sortOrder: nil, importedPayee: "CAFE 123"
        )
    }

    /// A store whose payee has four monthly charges at one price, a fifth
    /// well above it, and a rule that categorizes the payee.
    private func makeStore() async throws -> (BudgetStore, URL) {
        let (database, path) = try await makeTestDatabase(TestSchema.core + [TestSchema.rules])
        let store = try await makeTestStore(database: database)
        store.payees = [Payee(id: "payee-cafe", name: "Cafe", transferAccountId: nil, tombstone: false)]
        try await database.dbQueueForTesting.write { db in
            try db.execute(sql: """
            INSERT INTO payees (id, name) VALUES ('payee-cafe', 'Cafe');
            INSERT INTO transactions (id, acct, amount, description, date, tombstone) VALUES
                ('tx-1', 'acct-1', -1549, 'payee-cafe', 20260105, 0),
                ('tx-2', 'acct-1', -1549, 'payee-cafe', 20260205, 0),
                ('tx-3', 'acct-1', -1549, 'payee-cafe', 20260305, 0),
                ('tx-4', 'acct-1', -1549, 'payee-cafe', 20260405, 0),
                ('tx-5', 'acct-1', -1999, 'payee-cafe', 20260505, 0);
            INSERT INTO rules (id, conditions_op, conditions, actions)
            VALUES ('cafe-category', 'and',
                '[{"op":"is","field":"description","value":"payee-cafe"}]',
                '[{"op":"set","field":"category","value":"cat-dining"}]');
            """)
        }
        return (store, path)
    }

    @Test func reportsThePayeesHistoryAndWhatTheRulesWouldSet() async throws {
        let (store, path) = try await makeStore()
        defer { cleanup(path) }

        let inspection = await store.inspectTransaction(transaction())

        #expect(inspection.history.map(\.id) == ["tx-5", "tx-4", "tx-3", "tx-2", "tx-1"])
        let stats = try #require(inspection.stats)
        #expect(stats.usual == -1549)
        #expect(stats.steady)
        #expect(stats.priceChange(of: -1999) != nil)
        #expect(inspection.suggestions.map(\.field) == [.category])
        #expect(inspection.suggestions.first?.categoryId == "cat-dining")
        // The suggestion names the rule it came from.
        guard case .rule(let rule) = inspection.suggestions.first?.source else {
            Issue.record("expected a rule-sourced suggestion")
            return
        }
        #expect(rule.id == "cafe-category")
    }

    @Test func withNoRuleTheCategoryComesFromThePayeesLastTransaction() async throws {
        let (store, path) = try await makeStore()
        defer { cleanup(path) }
        let key = "suggestCategoryFromPayeeHistory"
        let original = UserDefaults.standard.object(forKey: key)
        defer { restoreUserDefault(key, to: original) }
        store.suggestCategoryFromPayeeHistory = true
        try await store.databaseForLogger?.dbQueueForTesting.write { db in
            try db.execute(sql: """
            DELETE FROM rules;
            UPDATE transactions SET category = 'cat-coffee' WHERE id = 'tx-4';
            """)
        }

        let inspection = await store.inspectTransaction(transaction())

        #expect(inspection.suggestions.map(\.categoryId) == ["cat-coffee"])
        #expect(inspection.suggestions.first?.source == .payeeHistory)
    }

    @Test func aTransactionTheRulesAgreeWithHasNoChanges() async throws {
        let (store, path) = try await makeStore()
        defer { cleanup(path) }

        let inspection = await store.inspectTransaction(transaction(categoryId: "cat-dining"))

        #expect(inspection.suggestions.isEmpty)
    }

    @Test func aCategoryPickedByHandIsNotOverruled() async throws {
        let (store, path) = try await makeStore()
        defer { cleanup(path) }

        // The rule says cat-dining; this one was deliberately filed elsewhere.
        let inspection = await store.inspectTransaction(transaction(categoryId: "cat-gifts"))

        #expect(inspection.suggestions.isEmpty)
    }

    @Test func aTransferInspectsAsEmpty() async throws {
        let (store, path) = try await makeStore()
        defer { cleanup(path) }

        let inspection = await store.inspectTransaction(transaction(transferId: "other-leg"))

        #expect(inspection == BudgetStore.TransactionInspection())
    }

    @Test func onlyASteadyBillOffItsUsualGetsAUsualAmountForTheNotification() async throws {
        let (store, path) = try await makeStore()
        defer { cleanup(path) }

        let usual = await store.usualAmountsForPriceChanges(in: [
            transaction(id: "tx-5", amount: -1999),
            transaction(id: "tx-4", amount: -1549),
        ])

        #expect(usual == ["tx-5": -1549])
    }
}
