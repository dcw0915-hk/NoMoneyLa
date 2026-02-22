import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Entry
struct RecentTransactionEntry: TimelineEntry {
    let date: Date
    let transactionDate: Date?
    let categoryPath: String
    let amount: Decimal
    let currencyCode: String
    let note: String?
    let hasTransaction: Bool
}

// MARK: - Provider
struct RecentTransactionProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentTransactionEntry {
        RecentTransactionEntry(
            date: Date(),
            transactionDate: Date(),
            categoryPath: "Food / Restaurant",
            amount: 150,
            currencyCode: "HKD",
            note: "Lunch",
            hasTransaction: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentTransactionEntry) -> Void) {
        Task { @MainActor in
            let entry = loadCurrentEntry()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentTransactionEntry>) -> Void) {
        Task { @MainActor in
            let entry = loadCurrentEntry()
            let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    @MainActor
    private func loadCurrentEntry() -> RecentTransactionEntry {
        let context = sharedModelContainer.mainContext

        var descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let latest = try? context.fetch(descriptor).first else {
            return RecentTransactionEntry(
                date: Date(),
                transactionDate: nil,
                categoryPath: "",
                amount: 0,
                currencyCode: "HKD",
                note: nil,
                hasTransaction: false
            )
        }

        let allSubs = (try? context.fetch(FetchDescriptor<Subcategory>())) ?? []
        let allCats = (try? context.fetch(FetchDescriptor<Category>())) ?? []

        let uncat = widgetLocalizedString("uncategorized_label")
        var categoryPath = uncat
        if let subID = latest.subcategoryID,
           let sub = allSubs.first(where: { $0.id == subID }),
           let parent = allCats.first(where: { $0.id == sub.parentID }) {
            let parentName = parent.isDefault ? uncat : parent.name
            let subName = sub.isUncategorized ? uncat : sub.name
            categoryPath = "\(parentName) / \(subName)"
        }

        return RecentTransactionEntry(
            date: Date(),
            transactionDate: latest.date,
            categoryPath: categoryPath,
            amount: latest.totalAmount,
            currencyCode: latest.currencyCode,
            note: latest.note,
            hasTransaction: true
        )
    }
}

// MARK: - Widget View
struct RecentTransactionWidgetEntryView: View {
    var entry: RecentTransactionEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if entry.hasTransaction {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                    Text(widgetLocalizedString("recent_transaction_title"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if let txDate = entry.transactionDate {
                        Text(txDate, style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Text(entry.categoryPath)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack {
                    if let note = entry.note, !note.isEmpty {
                        Text(note)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(widgetLocalizedString("form_none"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .opacity(0.6)
                    }
                    Spacer()
                    Text(formatAmount(entry.amount, code: entry.currencyCode))
                        .font(family == .systemSmall ? .title3 : .title2)
                        .bold()
                        .foregroundColor(.red)
                }
            }
            .padding()
        } else {
            VStack {
                Image(systemName: "tray")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text(widgetLocalizedString("no_transactions_yet"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }

    private func formatAmount(_ amount: Decimal, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}

// MARK: - Widget Configuration
struct RecentTransactionWidget: Widget {
    let kind: String = "RecentTransactionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentTransactionProvider()) { entry in
            RecentTransactionWidgetEntryView(entry: entry)
                .modelContainer(sharedModelContainer)
                .containerBackground(Color(UIColor.systemBackground), for: .widget)
        }
        .configurationDisplayName(widgetLocalizedString("widget_recent_display_name"))
        .description(widgetLocalizedString("widget_recent_description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
