import Foundation
import GRDB
import Testing
@testable import Actuali

@MainActor
struct BudgetDatabasePayeeHistoryTests {
    @Test func listsAPayeesChargesNewestFirstWithNames() async throws {
        let (db, url) = try await makeTestDatabase(TestSchema.core)
        defer { cleanup(url) }
        try await db.dbQueueForTesting.write { conn in
            try conn.execute(sql: """
                INSERT INTO accounts (id, name) VALUES ('acct-1', 'Checking');
                INSERT INTO categories (id, name) VALUES ('cat-1', 'Streaming');
                INSERT INTO transactions (id, acct, category, amount, description, date, sort_order) VALUES
                    ('old', 'acct-1', 'cat-1', -1549, 'payee-1', 20260105, 1.0),
                    ('new', 'acct-1', NULL,    -1999, 'payee-1', 20260205, 1.0),
                    ('other', 'acct-1', 'cat-1', -500, 'payee-2', 20260301, 1.0);
            """)
        }

        let history = try await db.fetchPayeeHistory(payeeId: "payee-1")

        #expect(history == [
            .init(id: "new", date: 20_260_205, amount: -1999, accountName: "Checking", categoryName: nil),
            .init(id: "old", date: 20_260_105, amount: -1549, accountName: "Checking", categoryName: "Streaming"),
        ])
    }

    @Test func aSplitCountsOnceAndDeletedChargesNotAtAll() async throws {
        let (db, url) = try await makeTestDatabase(TestSchema.core)
        defer { cleanup(url) }
        try await db.dbQueueForTesting.write { conn in
            try conn.execute(sql: """
                INSERT INTO transactions
                    (id, amount, description, date, isParent, isChild, parent_id, tombstone) VALUES
                    ('parent',  -3000, 'payee-1', 20260105, 1, 0, NULL, 0),
                    ('child-a', -1000, 'payee-1', 20260105, 0, 1, 'parent', 0),
                    ('child-b', -2000, 'payee-1', 20260105, 0, 1, 'parent', 0),
                    ('deleted', -4000, 'payee-1', 20260205, 0, 0, NULL, 1);
            """)
        }

        let history = try await db.fetchPayeeHistory(payeeId: "payee-1")

        #expect(history.map(\.id) == ["parent"])
        #expect(history.first?.amount == -3000)
    }

    @Test func followsPayeesMergedIntoThisOne() async throws {
        let (db, url) = try await makeTestDatabase(TestSchema.core)
        defer { cleanup(url) }
        try await db.dbQueueForTesting.write { conn in
            try conn.execute(sql: """
                INSERT INTO payee_mapping (id, targetId) VALUES
                    ('payee-1', 'payee-1'), ('payee-merged', 'payee-1');
                INSERT INTO transactions (id, amount, description, date) VALUES
                    ('direct', -100, 'payee-1', 20260105),
                    ('merged', -200, 'payee-merged', 20260205);
            """)
        }

        // Asked for by either id, the history is the surviving payee's.
        #expect(try await db.fetchPayeeHistory(payeeId: "payee-1").map(\.id) == ["merged", "direct"])
        #expect(try await db.fetchPayeeHistory(payeeId: "payee-merged").map(\.id) == ["merged", "direct"])
    }
}
