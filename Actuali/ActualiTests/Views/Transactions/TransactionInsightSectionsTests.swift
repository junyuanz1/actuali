import Foundation
import Testing
@testable import Actuali

struct TransactionInsightSectionsTests {
    private let locale = Locale(identifier: "en_US")

    @Test func namesTheBillingRhythmsPeopleRecognize() {
        #expect(PayeeHistoryView.frequency(days: 1, locale: locale) == "Daily")
        #expect(PayeeHistoryView.frequency(days: 7, locale: locale) == "About weekly")
        #expect(PayeeHistoryView.frequency(days: 14, locale: locale) == "About every two weeks")
        #expect(PayeeHistoryView.frequency(days: 31, locale: locale) == "About monthly")
        #expect(PayeeHistoryView.frequency(days: 91, locale: locale) == "About quarterly")
        #expect(PayeeHistoryView.frequency(days: 365, locale: locale) == "About yearly")
    }

    @Test func theBankDescriptionShowsOnlyWhenItAddsSomething() {
        func transaction(payee: String?, imported: String?) -> Transaction {
            Transaction(
                id: "tx", accountId: "acct", date: 20_260_505, amount: -100, payeeId: nil, payeeName: payee,
                categoryId: nil, categoryName: nil, notes: nil, cleared: false, reconciled: false,
                transferId: nil, isParent: false, parentId: nil, tombstone: false, sortOrder: nil,
                importedPayee: imported
            )
        }
        #expect(PayeeHistoryView.bankDescription(of: transaction(payee: "Netflix", imported: "NETFLIX.COM CA"))
            == "NETFLIX.COM CA")
        // Entered by hand, the imported text is just the payee name again.
        #expect(PayeeHistoryView.bankDescription(of: transaction(payee: "Netflix", imported: "Netflix")) == nil)
        #expect(PayeeHistoryView.bankDescription(of: transaction(payee: "Netflix", imported: nil)) == nil)
    }

    @Test func fallsBackToTheDayCount() {
        #expect(PayeeHistoryView.frequency(days: 45, locale: locale) == "About every 45 days")
    }
}
