import Charts
import SwiftUI

/// What the rules would set on the transaction being edited, with one tap to
/// take it, and an offer to turn a category picked by hand into a rule.
struct TransactionRuleSections: View {
    @EnvironmentObject private var budgetStore: BudgetStore

    let transaction: Transaction
    let inspection: BudgetStore.TransactionInspection
    /// The form's current payee and category: a suggestion the form already
    /// holds goes away, and a new rule is built from what the form shows.
    let payee: Payee?
    let payeeName: String
    let categoryId: String?
    let onApply: (BudgetStore.TransactionInspection.RuleChange) -> Void

    @State private var ruleDraft: Rule?

    private var pendingChanges: [BudgetStore.TransactionInspection.RuleChange] {
        inspection.ruleChanges.filter { change in
            switch change.field {
            case .payee: change.to != payeeName
            case .category: change.categoryId != categoryId
            }
        }
    }

    /// The category picked in the form, when it is a change the rules
    /// wouldn't have made themselves.
    private var pickedCategory: Category? {
        guard budgetStore.rulesSupported, let categoryId, categoryId != transaction.categoryId,
              !inspection.ruleChanges.contains(where: { $0.categoryId == categoryId }) else { return nil }
        return budgetStore.categoryGroups.flatMap(\.categories).first { $0.id == categoryId }
    }

    var body: some View {
        if !pendingChanges.isEmpty {
            Section("Your rules would change") {
                ForEach(pendingChanges) { change in
                    switch change.field {
                    case .payee:
                        let none = String(localized: "No payee")
                        LabeledContent("Payee", value: "\(change.from ?? none) → \(change.to ?? none)")
                    case .category:
                        let none = String(localized: "Uncategorized")
                        LabeledContent("Category", value: "\(change.from ?? none) → \(change.to ?? none)")
                    }
                }
                Button("Apply") {
                    pendingChanges.forEach(onApply)
                }
                .accessibilityIdentifier("transactionInsight.applyRules")
            }
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

/// Read-only context under the transaction editor: how this charge compares
/// with the payee's past ones, its schedule, and the bank's own text.
struct TransactionHistorySections: View {
    @EnvironmentObject private var budgetStore: BudgetStore
    @Environment(\.locale) private var locale

    let transaction: Transaction
    let inspection: BudgetStore.TransactionInspection

    /// Rows listed under the summary; the chart covers a longer run.
    private static let recentCount = 5
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

    private var linkedSchedule: ScheduleSummary? {
        budgetStore.schedules.first { $0.id == transaction.schedule }
    }

    /// A steady bill no schedule covers yet.
    private var suggestsSchedule: Bool {
        inspection.stats?.steady == true && transaction.schedule == nil
            && !budgetStore.schedules.contains { $0.payeeId == transaction.payeeId && !$0.completed }
    }

    var body: some View {
        if let stats = inspection.stats {
            Section("Payee History") {
                if let change = stats.priceChange(of: transaction.amount) {
                    let percent = change.formatted(
                        .percent.precision(.fractionLength(0)).sign(strategy: .always()).locale(locale)
                    )
                    Label("\(percent) vs usual", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                LabeledContent("Usual amount", value: budgetStore.displayBalance(stats.usual, locale: locale))
                if let interval = stats.interval {
                    LabeledContent("How often", value: Self.frequency(days: interval, locale: locale))
                }
                if !budgetStore.hideBalances {
                    chart
                }
                ForEach(inspection.history.prefix(Self.recentCount)) { row in
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

        if let imported = transaction.importedPayee, !imported.isEmpty, imported != transaction.payeeName {
            Section {
                LabeledContent("Bank description", value: imported)
            }
        }
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
        .frame(height: 44)
        .accessibilityHidden(true)
    }
}
