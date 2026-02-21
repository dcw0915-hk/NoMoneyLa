import WidgetKit
import SwiftUI
import SwiftData

struct Provider: TimelineProvider {
    typealias Entry = SimpleEntry

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), todayTotal: 0, yesterdayTotal: 0, changePercent: 0, transactionCount: 0, currencyCode: "HKD")
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
        let yesterdayTotal = calculateTotalExpense(for: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        let changePercent: Double = yesterdayTotal > 0 ? (Double(truncating: (todayTotal - yesterdayTotal) as NSDecimalNumber) / Double(truncating: yesterdayTotal as NSDecimalNumber) * 100) : 0
        let count = fetchTransactionCount(for: Date())
        print("Widget Data - Today: \(todayTotal), Yesterday: \(yesterdayTotal), Count: \(count)")
        return SimpleEntry(date: Date(), todayTotal: todayTotal, yesterdayTotal: yesterdayTotal, changePercent: changePercent, transactionCount: count, currencyCode: "HKD")
    }

    @MainActor
    private func calculateTotalExpense(for date: Date) -> Decimal {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let context = sharedModelContainer.mainContext
        
        // 獲取默認付款人
        let payerDescriptor = FetchDescriptor<Payer>(predicate: #Predicate { $0.isDefault == true })
        guard let defaultPayer = try? context.fetch(payerDescriptor).first else {
            return 0
        }
        
        let transactionDescriptor = FetchDescriptor<Transaction>()
        do {
            let all = try context.fetch(transactionDescriptor)
            let filtered = all.filter { $0.date >= start && $0.date < end && $0.type == .expense }
            // 加總默認付款人的貢獻
            let total = filtered.reduce(Decimal(0)) { sum, tx in
                let contributions = tx.contributions.filter { $0.payer.id == defaultPayer.id }
                return sum + contributions.reduce(0) { $0 + $1.amount }
            }
            return total
        } catch {
            print("Fetch error: \(error)")
            return 0
        }
    }

    @MainActor
    private func fetchTransactionCount(for date: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let context = sharedModelContainer.mainContext
        
        // 獲取默認付款人
        let payerDescriptor = FetchDescriptor<Payer>(predicate: #Predicate { $0.isDefault == true })
        guard let defaultPayer = try? context.fetch(payerDescriptor).first else {
            return 0
        }
        
        let transactionDescriptor = FetchDescriptor<Transaction>()
        do {
            let all = try context.fetch(transactionDescriptor)
            return all.filter { transaction in
                transaction.date >= start && transaction.date < end && transaction.type == .expense &&
                transaction.contributions.contains { $0.payer.id == defaultPayer.id }
            }.count
        } catch {
            return 0
        }
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let todayTotal: Decimal
    let yesterdayTotal: Decimal
    let changePercent: Double
    let transactionCount: Int
    let currencyCode: String
}

// 共享 ModelContainer（需與主 App 相同配置）
let appGroupID = "group.Ricky.NoMoneyLa" // 請換成你的 App Group ID
let storeURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)!
    .appendingPathComponent("DataModel.sqlite")

let sharedModelContainer: ModelContainer = {
    let config = ModelConfiguration(url: storeURL)
    return try! ModelContainer(
        for: Transaction.self,
        Category.self,
        Subcategory.self,
        Payer.self,
        PaymentContribution.self,
        configurations: config
    )
}()

struct NoMoneyLaWidgetEntryView: View {
    var entry: SimpleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("今日支出")
                .font(.headline)
                .foregroundColor(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formatCurrency(entry.todayTotal))
                    .font(.title)
                    .bold()
                    .foregroundColor(.primary)
                Text(entry.currencyCode)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if entry.yesterdayTotal > 0 {
                HStack(spacing: 4) {
                    Image(systemName: entry.changePercent >= 0 ? "arrow.up" : "arrow.down")
                        .font(.caption)
                        .foregroundColor(entry.changePercent >= 0 ? .red : .green)
                    Text("\(abs(entry.changePercent), specifier: "%.1f")%")
                        .font(.caption)
                        .bold()
                        .foregroundColor(entry.changePercent >= 0 ? .red : .green)
                    Text("vs 昨日")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Image(systemName: "list.bullet")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(entry.transactionCount) 筆交易")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if entry.todayTotal == 0 && entry.transactionCount == 0 {
                Text("今日尚無支出")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }

    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "HKD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}

struct NoMoneyLaWidget: Widget {
    let kind: String = "NoMoneyLaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            NoMoneyLaWidgetEntryView(entry: entry)
                .modelContainer(sharedModelContainer)
                .containerBackground(Color(UIColor.systemBackground), for: .widget)
        }
        .configurationDisplayName("今日支出")
        .description("快速查看今日總支出")
        .supportedFamilies([.systemSmall])
    }
}
