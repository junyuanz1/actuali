import Foundation

/// What a payee's past charges say about it: the usual amount, how often it
/// is paid, and whether it behaves like a bill. The heuristic and its
/// thresholds follow Actual Budget Tweaks' `payee-stats.ts`.
struct PayeeStats: Equatable, Sendable {
    /// Charges a payee needs before it can count as a steady bill.
    static let minimumHistory = 4
    /// A payee whose charges sit this close to their median is a steady bill.
    static let steadySpread = 0.1
    /// How far from a steady bill's usual a charge has to be to count as a
    /// price change.
    static let priceChange = 0.25
    /// Billing rhythms a steady bill keeps, as days between charges: monthly,
    /// quarterly, yearly.
    private static let billCycles = [27...32, 85...95, 350...380]

    /// The median, in cents: one odd charge doesn't drag it the way it drags
    /// an average.
    let usual: Int
    /// Typical days between charges, when there are enough to tell.
    let interval: Int?
    /// Keeps both its price and a billing rhythm, as a bill does; a shop's
    /// amounts vary too much.
    let steady: Bool

    /// One payee's amounts (cents) and dates (YYYYMMDD), in any order.
    init(amounts: [Int], dates: [Int]) {
        let usual = Self.median(amounts.map(Double.init))
        let interval = Self.typicalInterval(dates)
        let onCycle = interval.map { days in Self.billCycles.contains { $0.contains(days) } } ?? false
        let spread = Self.median(amounts.map { abs(Double($0) - usual) })
        self.usual = Int(usual.rounded())
        self.interval = interval
        steady = amounts.count >= Self.minimumHistory
            && usual != 0
            && onCycle
            && spread / abs(usual) <= Self.steadySpread
    }

    /// How far `amount` is from a steady bill's usual, as a signed fraction
    /// (0.3 is 30% more), or nil when the payee isn't a steady bill or the
    /// charge is within the usual range.
    func priceChange(of amount: Int) -> Double? {
        guard steady else { return nil }
        let ratio = Double(amount) / Double(usual) - 1
        return abs(ratio) >= Self.priceChange ? ratio : nil
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// The median gap in days between distinct dates; nil with fewer than three.
    private static func typicalInterval(_ dates: [Int]) -> Int? {
        let days = Set(dates).compactMap { DayDate(yyyymmdd: $0)?.dayNumber }.sorted()
        guard days.count >= 3 else { return nil }
        let gaps = zip(days.dropFirst(), days).map { $0 - $1 }.sorted()
        return gaps[gaps.count / 2]
    }
}
