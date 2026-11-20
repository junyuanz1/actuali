import Foundation
import Testing
@testable import Actuali

struct TransactionInsightSectionsTests {
    private let locale = Locale(identifier: "en_US")

    @Test func namesTheBillingRhythmsPeopleRecognize() {
        #expect(TransactionHistorySections.frequency(days: 1, locale: locale) == "Daily")
        #expect(TransactionHistorySections.frequency(days: 7, locale: locale) == "About weekly")
        #expect(TransactionHistorySections.frequency(days: 14, locale: locale) == "About every two weeks")
        #expect(TransactionHistorySections.frequency(days: 31, locale: locale) == "About monthly")
        #expect(TransactionHistorySections.frequency(days: 91, locale: locale) == "About quarterly")
        #expect(TransactionHistorySections.frequency(days: 365, locale: locale) == "About yearly")
    }

    @Test func fallsBackToTheDayCount() {
        #expect(TransactionHistorySections.frequency(days: 45, locale: locale) == "About every 45 days")
    }
}
