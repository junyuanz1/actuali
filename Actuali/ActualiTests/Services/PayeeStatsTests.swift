import Testing
@testable import Actuali

struct PayeeStatsTests {
    @Test func aMonthlyChargeAtOnePriceIsASteadyBill() {
        let stats = PayeeStats(
            amounts: [-1549, -1549, -1549, -1549],
            dates: [20_260_105, 20_260_205, 20_260_305, 20_260_405]
        )
        #expect(stats.usual == -1549)
        #expect(stats.interval == 31)
        #expect(stats.steady)
    }

    @Test func aShopWithVaryingAmountsIsNotSteady() {
        let stats = PayeeStats(
            amounts: [-1200, -4800, -2300, -9100],
            dates: [20_260_105, 20_260_205, 20_260_305, 20_260_405]
        )
        #expect(!stats.steady)
        #expect(stats.priceChange(of: -9100) == nil)
    }

    @Test func aSteadyPriceOffItsBillingCycleIsNotSteady() {
        let stats = PayeeStats(
            amounts: [-350, -350, -350, -350],
            dates: [20_260_105, 20_260_107, 20_260_109, 20_260_111]
        )
        #expect(stats.interval == 2)
        #expect(!stats.steady)
    }

    @Test func threeChargesAreTooFewToCallABill() {
        let stats = PayeeStats(amounts: [-1549, -1549, -1549], dates: [20_260_105, 20_260_205, 20_260_305])
        #expect(!stats.steady)
    }

    @Test func aSteadyBillReportsAChargeFarFromItsUsual() throws {
        let stats = PayeeStats(
            amounts: [-1999, -1549, -1549, -1549, -1549],
            dates: [20_260_505, 20_260_405, 20_260_305, 20_260_205, 20_260_105]
        )
        #expect(stats.steady)
        let change = try #require(stats.priceChange(of: -1999))
        #expect(abs(change - 0.29) < 0.01)
        #expect(stats.priceChange(of: -1549) == nil)
        // Under the 25% threshold.
        #expect(stats.priceChange(of: -1800) == nil)
    }

    @Test func theUsualAmountIsTheMedianNotTheAverage() {
        let stats = PayeeStats(amounts: [-1000, -1200, -90000], dates: [20_260_101, 20_260_102, 20_260_103])
        #expect(stats.usual == -1200)
    }

    @Test func theIntervalNeedsThreeDistinctDays() {
        #expect(PayeeStats(amounts: [-1, -1, -1], dates: [20_260_101, 20_260_101, 20_260_201]).interval == nil)
        #expect(PayeeStats(amounts: [], dates: []).usual == 0)
    }
}
