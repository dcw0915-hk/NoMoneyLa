import SwiftUI
import SwiftData

struct TransactionListView: View {
    @EnvironmentObject var langManager: LanguageManager
    @Environment(\.modelContext) private var context

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Category.order) private var categories: [Category]

    var body: some View {
        NavigationStack {
            List {
                ForEach(transactions) { tx in
                    NavigationLink(
                        destination: TransactionFormView(transaction: tx, isEditing: false)
                    ) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(categoryName(for: tx.categoryID))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(tx.date, format: .dateTime.year().month().day())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(format(amount: tx.amount, code: tx.currencyCode))
                                .foregroundColor(tx.type == .expense ? .red : .green)
                                .font(.headline)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .navigationTitle(langManager.localized("transactions_title"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(
                        destination: TransactionFormView(isEditing: true)
                    ) {
                        Label(langManager.localized("form_add_title"), systemImage: "plus.circle.fill")
                    }
                }
            }
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let tx = transactions[index]
            context.delete(tx)
        }
        try? context.save()
    }

    private func categoryName(for id: UUID?) -> String {
        guard let id = id else { return langManager.localized("form_none") }
        return categories.first(where: { $0.id == id })?.name ?? langManager.localized("form_none")
    }

    private func format(amount: Decimal, code: String = "HKD") -> String {
        let ns = amount as NSDecimalNumber
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.string(from: ns) ?? "\(amount)"
    }
}
