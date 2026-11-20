import Charts
import SwiftUI

/// A payee or category for a transaction that has none, one tap to take it,
/// and an offer to turn a category picked by hand into a rule.
struct TransactionRuleSections: View {
    @EnvironmentObject private var budgetStore: BudgetStore

    let transaction: Transaction
    let inspection: BudgetStore.TransactionInspection
    /// The form's current payee and category: a suggestion the form already
    /// holds goes away, and a new rule is built from what the form shows.
    let payee: Payee?
    let payeeName: String
    let categoryId: String?
    let onApply: (BudgetStore.TransactionInspection.Suggestion) -> Void

    @State private var ruleDraft: Rule?
    @State private var viewedRule: Rule?

    private var pendingSuggestions: [BudgetStore.TransactionInspection.Suggestion] {
        // Suggestions fill an empty field: once the form holds a value, taken
        // from here or picked by hand, there is nothing left to offer. Nor is
        // there without a name to show.
        inspection.suggestions.filter { suggestion in
            guard suggestion.to != nil else { return false }
            return switch suggestion.field {
            case .payee: payeeName.isEmpty
            case .category: categoryId == nil
            }
        }
    }

    /// The category picked in the form, when it is a change the rules
    /// wouldn't have made themselves.
    private var pickedCategory: Category? {
        guard budgetStore.rulesSupported, let categoryId, categoryId != transaction.categoryId,
              !inspection.suggestions.contains(where: { $0.categoryId == categoryId && $0.source != .payeeHistory })
        else { return nil }
        return budgetStore.categoryGroups.flatMap(\.categories).first { $0.id == categoryId }
    }

    var body: some View {
        ForEach(pendingSuggestions) { suggestion in
            Section {
                Button {
                    onApply(suggestion)
                } label: {
                    let name = suggestion.to ?? ""
                    switch suggestion.field {
                    case .payee:
                        Label("Set payee to \(name)", systemImage: "wand.and.stars")
                    case .category:
                        Label("Set category to \(name)", systemImage: "wand.and.stars")
                    }
                }
                .accessibilityIdentifier("transactionInsight.apply.\(suggestion.field)")

                if case .rule(let rule) = suggestion.source {
                    Button {
                        viewedRule = rule
                    } label: {
                        Label("View Rule", systemImage: "list.bullet.rectangle")
                    }
                    .accessibilityIdentifier("transactionInsight.viewRule.\(suggestion.field)")
                }
            } footer: {
                switch suggestion.source {
                case .rule:
                    Text("Suggested by your rules.")
                case .payeeHistory:
                    Text("Suggested from past \(payeeName) transactions.")
                }
            }
        }
        .sheet(item: $viewedRule) { rule in
            NavigationStack { RuleEditorView(rule: rule) }
                .environmentObject(budgetStore)
        }

        if let payee, let category = pickedCategory {
            Section {
                Button {
                    ruleDraft = Rule(
                        id: UUID().uuidString, stage: .default, conditionsOp: .and,
                        conditions: [.init(op: "is", field: "payee", value: .string(payee.id))],
                        actions: [.init(op: "set", field: "category", value: .string(category.id))]
                    )
                } label: {
                    Label("Always categorize \(payee.name) as \(category.name)", systemImage: "wand.and.stars")
                }
                .accessibilityIdentifier("transactionInsight.createRule")
                .sheet(item: $ruleDraft) { draft in
                    NavigationStack { RuleEditorView(rule: draft, isNew: true) }
                        .environmentObject(budgetStore)
                }
            }
        }
    }
}

/// The editor's one-line way into a payee's history: the usual amount, or a
/// warning when this charge is off it. Absent when there is nothing behind it.
struct PayeeHistoryLink: View {
    @EnvironmentObject private var budgetStore: BudgetStore
    @Environment(\.locale) private var locale

    let transaction: Transaction
    let inspection: BudgetStore.TransactionInspection

    private var hasBankDescription: Bool {
        PayeeHistoryView.bankDescription(of: transaction) != nil
    }

    var body: some View {
        if inspection.stats != nil || transaction.schedule != nil || hasBankDescription {
            NavigationLink {
                PayeeHistoryView(transaction: transaction, inspection: inspection)
            } label: {
                // An HStack like the form's other rows: LabeledContent grew
                // this row to several times its height.
                HStack {
                    Label("Payee History", systemImage: "clock.arrow.circlepath")
                    Spacer()
                    if let stats = inspection.stats {
                        if let change = stats.priceChange(of: transaction.amount) {
                            PayeeHistoryView.priceChangeLabel(change, locale: locale)
                        } else {
                            Text("Usually \(budgetStore.displayBalance(stats.usual, locale: locale))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .accessibilityIdentifier("transactionInsight.history")
        }
    }
}

/// How a charge compares with the payee's past ones, with its schedule and
/// the bank's own text. Read-only.
struct PayeeHistoryView: View {
    @EnvironmentObject private var budgetStore: BudgetStore
    @Environment(\.locale) private var locale

    let transaction: Transaction
    let inspection: BudgetStore.TransactionInspection

    /// Charges the trend covers, fewer when the payee has fewer.
    private static let chartCount = 12

    /// "About monthly" for a typical gap between charges, in days.
    nonisolated static func frequency(days: Int, locale: Locale, bundle: Bundle = .main) -> String {
        switch days {
        case ...1: ReportStrings.text("Daily", locale: locale, bundle: bundle)
        case 6...8: ReportStrings.text("About weekly", locale: locale, bundle: bundle)
        case 13...16: ReportStrings.text("About every two weeks", locale: locale, bundle: bundle)
        case 27...32: ReportStrings.text("About monthly", locale: locale, bundle: bundle)
        case 85...95: ReportStrings.text("About quarterly", locale: locale, bundle: bundle)
        case 355...375: ReportStrings.text("About yearly", locale: locale, bundle: bundle)
        // The count is always above one here, so it is passed as text and the
        // key needs no plural variants.
        default: String(
                format: ReportStrings.text("About every %@ days", locale: locale, bundle: bundle),
                days.formatted(.number.locale(locale))
            )
        }
    }

    /// The bank's text for an imported transaction, when it says something
    /// the payee name doesn't.
    nonisolated static func bankDescription(of transaction: Transaction) -> String? {
        guard let imported = transaction.importedPayee, !imported.isEmpty,
              imported != transaction.payeeName else { return nil }
        return imported
    }

    /// Icon and text, so the warning doesn't rest on its color.
    static func priceChangeLabel(_ change: Double, locale: Locale) -> some View {
        let percent = change.formatted(
            .percent.precision(.fractionLength(0)).sign(strategy: .always()).locale(locale)
        )
        return Label("\(percent) vs usual", systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
    }

    private var linkedSchedule: ScheduleSummary? {
        budgetStore.schedules.first { $0.id == transaction.schedule }
    }

    /// A steady bill no schedule covers yet.
    private var suggestsSchedule: Bool {
        inspection.stats?.steady == true && transaction.schedule == nil
            && !budgetStore.schedules.contains { $0.payeeId == transaction.payeeId && !$0.completed }
    }

    var body: some View {
        List {
            if let stats = inspection.stats {
                Section {
                    if let change = stats.priceChange(of: transaction.amount) {
                        Self.priceChangeLabel(change, locale: locale)
                    }
                    LabeledContent("Usual amount", value: budgetStore.displayBalance(stats.usual, locale: locale))
                    if let interval = stats.interval {
                        LabeledContent("How often", value: Self.frequency(days: interval, locale: locale))
                    }
                    if !budgetStore.hideBalances {
                        chart
                    }
                }
            }

            if let schedule = linkedSchedule {
                Section("Schedule") {
                    NavigationLink {
                        ScheduleEditView(editing: schedule, budgetStore: budgetStore)
                    } label: {
                        LabeledContent {
                            if let next = schedule.nextDate {
                                Text(Transaction.formattedDate(from: next.yyyymmdd))
                            }
                        } label: {
                            Label(schedule.name ?? transaction.payeeName ?? "", systemImage: "calendar.badge.clock")
                        }
                    }
                    .accessibilityIdentifier("transactionInsight.schedule")
                }
            } else if suggestsSchedule {
                // ponytail: hands over to Find Schedules, which proposes every
                // repeating payee, rather than prefilling a schedule for this one.
                // Give ScheduleEditView a prefill if that proves too indirect.
                Section {
                    NavigationLink {
                        DiscoverSchedulesView()
                    } label: {
                        Label("Find Schedules", systemImage: "sparkle.magnifyingglass")
                    }
                    .accessibilityIdentifier("transactionInsight.findSchedules")
                } footer: {
                    Text("This looks like a recurring bill without a schedule.")
                }
            }

            if let imported = Self.bankDescription(of: transaction) {
                Section {
                    LabeledContent("Bank description", value: imported)
                }
            }

            if !inspection.history.isEmpty {
                Section("Transactions") {
                    ForEach(inspection.history) { row in
                        LabeledContent {
                            Text(budgetStore.displayBalance(row.amount, locale: locale))
                                .monospacedDigit()
                        } label: {
                            Text(Transaction.formattedDate(from: row.date))
                            Text([row.accountName, row.categoryName].compactMap(\.self).joined(separator: " · "))
                        }
                        .fontWeight(row.id == transaction.id ? .semibold : .regular)
                        .accessibilityIdentifier("transactionInsight.history.\(row.id)")
                    }
                }
            }
        }
        .navigationTitle(transaction.payeeName ?? String(localized: "Payee History"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The payee's last charges, oldest to newest, as a trend with no axes:
    /// the rows under it carry the figures.
    private var chart: some View {
        let recent = Array(inspection.history.prefix(Self.chartCount).reversed())
        return Chart(Array(recent.enumerated()), id: \.offset) { index, row in
            LineMark(x: .value(String(localized: "Date"), index), y: .value(String(localized: "Amount"), abs(row.amount)))
            PointMark(x: .value(String(localized: "Date"), index), y: .value(String(localized: "Amount"), abs(row.amount)))
                .symbolSize(row.id == transaction.id ? 60 : 20)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 80)
        .accessibilityHidden(true)
    }
}
