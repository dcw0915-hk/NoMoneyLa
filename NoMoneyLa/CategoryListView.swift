import SwiftUI
import SwiftData

struct CategoryListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.order) private var allCategories: [Category]
    @Query(sort: \Subcategory.order) private var allSubcategories: [Subcategory]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @State private var newName: String = ""
    @State private var showDeleteAlert = false
    @State private var categoryToDelete: Category?

    // Inline edit state
    @State private var editingCategoryID: UUID?
    @State private var inlineEditedName: String = ""
    @FocusState private var isInlineFocused: Bool

    private var categories: [Category] {
        allCategories.sorted(by: { $0.order < $1.order })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("新增分類") {
                    HStack {
                        TextField("輸入名稱", text: $newName)
                        Button("新增") { addCategory() }
                    }
                }

                Section("已建立的分類") {
                    ForEach(categories) { category in
                        HStack(spacing: 12) {
                            if editingCategoryID == category.id {
                                HStack(spacing: 8) {
                                    TextField("名稱", text: $inlineEditedName)
                                        .focused($isInlineFocused)
                                        .submitLabel(.done)
                                        .onSubmit { commitInlineEdit(for: category) }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(UIColor.secondarySystemBackground))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color(UIColor.separator), lineWidth: 0.5)
                                        )
                                        .frame(minWidth: 100)
                                        .lineLimit(1)

                                    Button {
                                        commitInlineEdit(for: category)
                                    } label: {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                    .frame(width: 36, height: 36)

                                    Button {
                                        cancelInlineEdit()
                                    } label: {
                                        Image(systemName: "xmark")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                    .frame(width: 36, height: 36)
                                }
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        isInlineFocused = true
                                    }
                                }
                            } else {
                                Text(category.name)
                                    .font(.body)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }

                            Spacer()

                            HStack(spacing: 10) {
                                Button {
                                    startInlineEdit(for: category)
                                } label: {
                                    Image(systemName: "pencil")
                                        .imageScale(.large)
                                        .foregroundColor(.primary)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())

                                NavigationLink {
                                    SubcategoryManagerView(parentCategory: category)
                                } label: {
                                    Image(systemName: "list.bullet")
                                        .imageScale(.large)
                                        .foregroundColor(.primary)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())

                                Button(role: .destructive) {
                                    categoryToDelete = category
                                    showDeleteAlert = true
                                } label: {
                                    Image(systemName: "trash")
                                        .imageScale(.large)
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onMove(perform: moveCategory)
                }
            }
            .navigationTitle("分類管理")
            .alert("刪除分類", isPresented: $showDeleteAlert, presenting: categoryToDelete) { category in
                Button("取消", role: .cancel) {}
                Button("刪除", role: .destructive) { safeDelete(category) }
            } message: { category in
                Text("刪除分類「\(category.name)」會同時刪除其子分類，並讓相關交易失去連結，確定要刪除嗎？")
            }
        }
    }

    // Inline edit helpers
    private func startInlineEdit(for category: Category) {
        editingCategoryID = category.id
        inlineEditedName = category.name
    }

    private func commitInlineEdit(for category: Category) {
        let trimmed = inlineEditedName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            category.name = trimmed
            do {
                try context.save()
                reorderCategories()
            } catch {
                print("儲存分類名稱失敗：\(error.localizedDescription)")
            }
        }
        editingCategoryID = nil
        inlineEditedName = ""
        isInlineFocused = false
    }

    private func cancelInlineEdit() {
        editingCategoryID = nil
        inlineEditedName = ""
        isInlineFocused = false
    }

    // CRUD
    private func addCategory() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let maxOrder = categories.map { $0.order }.max() ?? 0
        let newCategory = Category(name: trimmed, order: maxOrder + 1)
        context.insert(newCategory)
        do {
            try context.save()
            reorderCategories()
        } catch {
            print("新增分類失敗：\(error.localizedDescription)")
        }
        newName = ""
    }

    private func moveCategory(from source: IndexSet, to destination: Int) {
        var revised = categories
        revised.move(fromOffsets: source, toOffset: destination)
        for (index, cat) in revised.enumerated() { cat.order = index }
        try? context.save()
    }

    private func safeDelete(_ category: Category) {
        // 解除交易與子分類的關聯，刪除子分類
        let subs = allSubcategories.filter { $0.parentID == category.id }
        for sub in subs {
            for tx in transactions where tx.subcategoryID == sub.id {
                tx.subcategoryID = nil
            }
            context.delete(sub)
        }
        // 若你同時在 transaction 儲存 categoryID，這裡也要處理（本範例沒有 categoryID）
        context.delete(category)
        do {
            try context.save()
            reorderCategories()
        } catch {
            print("刪除分類失敗：\(error.localizedDescription)")
        }
    }

    // 排序
    private func reorderCategories() {
        let topCategories = allCategories.sorted(by: { $0.order < $1.order })
        for (index, cat) in topCategories.enumerated() {
            cat.order = index
        }
        // 子分類排序
        for parent in topCategories {
            let subs = allSubcategories.filter { $0.parentID == parent.id }
                                        .sorted(by: { $0.order < $1.order })
            for (index, sub) in subs.enumerated() {
                sub.order = index
            }
        }
        try? context.save()
    }
}
