import SwiftUI
import SwiftData

struct SubcategoryManagerView: View {
    @EnvironmentObject var langManager: LanguageManager
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.order) private var allCategories: [Category]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    let parentCategory: Category

    @State private var newName: String = ""
    @State private var newColorHex: String = "#FF6B6B"
    @State private var showDeleteAlert = false
    @State private var subcategoryToDelete: Category?

    // Inline edit state
    @State private var editingSubcategoryID: UUID?
    @State private var inlineEditedName: String = ""
    @FocusState private var isInlineFocused: Bool

    private var subcategories: [Category] {
        allCategories.filter { $0.parentID == parentCategory.id }
                     .sorted(by: { $0.order < $1.order })
    }

    var body: some View {
        NavigationStack {
            Form {
                // 新增子分類
                Section(langManager.localized("subcategory_add_section")) {
                    HStack(spacing: 12) {
                        ColorPicker(langManager.localized("subcategory_color_picker"), selection: Binding(
                            get: { Color(hex: newColorHex) },
                            set: { newColorHex = $0.toHex() ?? "#FF6B6B" }
                        ))
                        .labelsHidden()

                        TextField(langManager.localized("subcategory_name_placeholder"), text: $newName)
                            .submitLabel(.done)
                            .onSubmit { addSubcategory() }

                        Button(langManager.localized("subcategory_add_button")) { addSubcategory() }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                // 已建立的子分類
                Section(langManager.localized("subcategory_list_section")) {
                    ForEach(subcategories) { sub in
                        HStack(spacing: 12) {
                            // 顏色圓圈顯示目前顏色
                            Circle()
                                .fill(Color(hex: sub.colorHex ?? "#A8A8A8"))
                                .frame(width: 18, height: 18)

                            if editingSubcategoryID == sub.id {
                                // 編輯名稱模式
                                TextField(langManager.localized("subcategory_name_label"), text: $inlineEditedName)
                                    .focused($isInlineFocused)
                                    .submitLabel(.done)
                                    .onSubmit { commitInlineEdit(for: sub) }
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
                            } else {
                                Text(sub.name)
                                    .font(.body)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }

                            Spacer()

                            // 永遠顯示 ColorPicker
                            ColorPicker("", selection: Binding(
                                get: { Color(hex: sub.colorHex ?? "#A8A8A8") },
                                set: { newColor in
                                    sub.colorHex = newColor.toHex() ?? "#A8A8A8"
                                    try? context.save()
                                }
                            ))
                            .labelsHidden()
                            .frame(width: 40)

                            // 編輯名稱按鈕
                            Button {
                                startInlineEdit(for: sub)
                            } label: {
                                Image(systemName: "pencil")
                                    .imageScale(.large)
                                    .foregroundColor(.primary)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())

                            // 刪除按鈕
                            Button(role: .destructive) {
                                subcategoryToDelete = sub
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
                        .padding(.vertical, 4)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onMove(perform: moveSubcategory)
                }
            }
            .navigationTitle("\(langManager.localized("subcategory_manage_title"))：\(parentCategory.name)")
            .alert(langManager.localized("subcategory_delete_title"), isPresented: $showDeleteAlert, presenting: subcategoryToDelete) { sub in
                Button(langManager.localized("subcategory_cancel"), role: .cancel) {}
                Button(langManager.localized("subcategory_delete"), role: .destructive) { safeDelete(sub) }
            } message: { sub in
                Text("\(langManager.localized("subcategory_delete_message"))「\(sub.name)」")
            }
        }
    }

    // Inline edit helpers
    private func startInlineEdit(for sub: Category) {
        editingSubcategoryID = sub.id
        inlineEditedName = sub.name
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isInlineFocused = true
        }
    }

    private func commitInlineEdit(for sub: Category) {
        let trimmed = inlineEditedName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            sub.name = trimmed
            do {
                try context.save()
                reorderSubcategories()
            } catch {
                print("儲存子分類名稱失敗：\(error.localizedDescription)")
            }
        }
        editingSubcategoryID = nil
        inlineEditedName = ""
        isInlineFocused = false
    }

    // CRUD
    private func addSubcategory() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let maxOrder = subcategories.map { $0.order }.max() ?? 0
        let newSub = Category(name: trimmed,
                              parentID: parentCategory.id,
                              order: maxOrder + 1,
                              colorHex: newColorHex)
        context.insert(newSub)
        try? context.save()
        newName = ""
    }

    private func moveSubcategory(from source: IndexSet, to destination: Int) {
        var revised = subcategories
        revised.move(fromOffsets: source, toOffset: destination)
        for (index, sub) in revised.enumerated() { sub.order = index }
        try? context.save()
    }

    private func safeDelete(_ sub: Category) {
        for tx in transactions where tx.categoryID == sub.id {
            tx.categoryID = nil
        }
        context.delete(sub)
        try? context.save()
    }

    // 排序
    private func reorderSubcategories() {
        let subs = allCategories.filter { $0.parentID == parentCategory.id }
                                .sorted(by: { $0.order < $1.order })
        for (index, sub) in subs.enumerated() {
            sub.order = index
        }
        try? context.save()
    }
}
