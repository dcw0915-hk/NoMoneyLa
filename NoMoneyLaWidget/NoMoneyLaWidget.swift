import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Provider
struct Provider: TimelineProvider {
    typealias Entry = SimpleEntry

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), todayTotal: 12345, transactionCount: 3)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        Task { @MainActor in
            let entry = loadCurrentEntry()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        Task { @MainActor in
            let entry = loadCurrentEntry()
            let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    @MainActor
    private func loadCurrentEntry() -> SimpleEntry {
        let todayTotal = calculateTotalExpense(for: Date())
        let count = fetchTransactionCount(for: Date())
        return SimpleEntry(date: Date(), todayTotal: todayTotal, transactionCount: count)
    }

    @MainActor
    private func calculateTotalExpense(for date: Date) -> Decimal {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let context = sharedModelContainer.mainContext

        let descriptor = FetchDescriptor<Transaction>()
        do {
            let all = try context.fetch(descriptor)
            let filtered = all.filter { $0.date >= start && $0.date < end && $0.type == .expense }
            return filtered.reduce(Decimal(0)) { $0 + $1.totalAmount }
        } catch {
            return 0
        }
    }

    @MainActor
    private func fetchTransactionCount(for date: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let context = sharedModelContainer.mainContext

        let descriptor = FetchDescriptor<Transaction>()
        do {
            let all = try context.fetch(descriptor)
            return all.filter { $0.date >= start && $0.date < end && $0.type == .expense }.count
        } catch {
            return 0
        }
    }
}

// MARK: - Entry
struct SimpleEntry: TimelineEntry {
    let date: Date
    let todayTotal: Decimal
    let transactionCount: Int
}

// MARK: - Widget View
struct NoMoneyLaWidgetEntryView: View {
    var entry: SimpleEntry
    @Environment(\.widgetFamily) var family

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter.string(from: entry.todayTotal as NSDecimalNumber) ?? "0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text(widgetLocalizedString("widget_today_expense"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(widgetLocalizedString("widget_currency_symbol"))
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.secondary)

                Text(formattedAmount)
                    .font(.system(size: 42, weight: .bold))
                    .minimumScaleFactor(0.3)
                    .lineLimit(1)
                    .foregroundColor(.red)
            }

            Spacer(minLength: 0)

            HStack {
                Label(
                    title: {
                        Text(String(format: widgetLocalizedString("widget_transactions_count"), entry.transactionCount))
                            .font(.system(size: 12, weight: .medium))
                    },
                    icon: {
                        Image(systemName: "list.bullet.rectangle.portrait")
                            .font(.system(size: 12))
                    }
                )
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Rectangle()
                        .fill(.regularMaterial)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
    }
}

// MARK: - Widget
struct NoMoneyLaWidget: Widget {
    let kind: String = "NoMoneyLaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            NoMoneyLaWidgetEntryView(entry: entry)
                .modelContainer(sharedModelContainer)
                .containerBackground(Color(UIColor.systemBackground), for: .widget)
        }
        .configurationDisplayName(widgetLocalizedString("widget_display_name"))
        .description(widgetLocalizedString("widget_description"))
        .supportedFamilies([.systemSmall])
    }
}
