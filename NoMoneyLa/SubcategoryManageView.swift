import SwiftUI
import SwiftData

struct SubcategoryManagerView: View {
    @EnvironmentObject var langManager: LanguageManager
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.order) private var categories: [Category]
    @Query(sort: \Subcategory.order) private var allSubcategories: [Subcategory]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    let parentCategory: Category

    @State private var newName: String = ""
    @State private var newColorHex: String = "#FF6B6B"
    @State private var showDeleteAlert = false
    @State private var subcategoryToDelete: Subcategory?

    @State private var editingSubcategoryID: UUID?
    @State private var inlineEditedName: String = ""
    @FocusState private var isInlineFocused: Bool

    private var subcategories: [Subcategory] {
        allSubcategories.filter { $0.parentID == parentCategory.id }
                        .sorted(by: {
                            if $0.name == "未分類" && $1.name != "未分類" {
                                return true
                            } else if $0.name != "未分類" && $1.name == "未分類" {
                                return false
                            } else {
                                return $0.order < $1.order
                            }
                        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(langManager.localized("subcategory_add_section")) {
                    HStack(spacing: 12) {
                        TextField(langManager.localized("subcategory_name_placeholder"), text: $newName)
                            .submitLabel(.done)
                            .onSubmit { addSubcategory() }
                        
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: newColorHex) },
                            set: { newColorHex = $0.toHex() ?? "#FF6B6B" }
                        ))
                        .labelsHidden()
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                        
                        Button(langManager.localized("subcategory_add_button")) { addSubcategory() }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .frame(height: 44)
                }

                Section(langManager.localized("subcategory_list_section")) {
                    ForEach(subcategories) { sub in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: sub.colorHex ?? "#A8A8A8"))
                                .frame(width: 18, height: 18)

                            if editingSubcategoryID == sub.id {
                                inlineEditView(for: sub)
                            } else {
                                Text(sub.name)
                                    .font(.body)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }

                            Spacer()

                            // 編輯模式時隱藏顏色選擇器和操作按鈕
                            if editingSubcategoryID != sub.id {
                                ColorPicker("", selection: Binding(
                                    get: { Color(hex: sub.colorHex ?? "#A8A8A8") },
                                    set: { newColor in
                                        sub.colorHex = newColor.toHex() ?? "#A8A8A8"
                                        try? context.save()
                                    }
                                ))
                                .labelsHidden()
                                .frame(width: 30, height: 30)
                                .clipShape(Circle())
                                
                                // 未分類子分類不顯示編輯按鈕
                                if sub.name != "未分類" {
                                    Button {
                                        startInlineEdit(for: sub)
                                    } label: {
                                        Image(systemName: "pencil")
                                            .imageScale(.medium)
                                            .foregroundColor(.primary)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                    .frame(width: 32, height: 32)
                                } else {
                                    // 未分類子分類佔位空間
                                    Spacer()
                                        .frame(width: 32)
                                }
                            }
                        }
                        .frame(height: 44)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        // 添加左滑刪除功能（未分類除外）
                        .swipeActions(edge: .trailing, allowsFullSwipe: sub.name != "未分類") {
                            if sub.name != "未分類" {
                                Button(role: .destructive) {
                                    deleteSubcategory(sub)
                                } label: {
                                    Label("刪除", systemImage: "trash")
                                }
                            }
                        }
                        .disabled(sub.name == "未分類") // 未分類不可編輯
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
            .onAppear {
                ensureUncategorizedExists()
            }
        }
    }

    // MARK: - 子視圖
    private func inlineEditView(for sub: Subcategory) -> some View {
        HStack(spacing: 8) {
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
                .frame(maxWidth: .infinity)
                .lineLimit(1)

            Button {
                commitInlineEdit(for: sub)
            } label: {
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(BorderlessButtonStyle())

            Button {
                cancelInlineEdit()
            } label: {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isInlineFocused = true
            }
        }
    }

    // MARK: - 方法
    private func ensureUncategorizedExists() {
        let hasUncategorized = subcategories.contains { $0.name == "未分類" }
        
        if !hasUncategorized {
            let uncategorized = Subcategory(
                name: "未分類",
                parentID: parentCategory.id,
                order: -1,
                colorHex: "#A8A8A8"
            )
            context.insert(uncategorized)
            try? context.save()
            reorderSubcategories()
        }
    }

    private func startInlineEdit(for sub: Subcategory) {
        if sub.name == "未分類" { return } // 未分類不可編輯
        editingSubcategoryID = sub.id
        inlineEditedName = sub.name
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isInlineFocused = true
        }
    }

    private func commitInlineEdit(for sub: Subcategory) {
        if sub.name == "未分類" { return } // 未分類不可編輯
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

    private func cancelInlineEdit() {
        editingSubcategoryID = nil
        inlineEditedName = ""
        isInlineFocused = false
    }

    private func addSubcategory() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard trimmed != "未分類" else { return } // 防止建立重複的未分類
        
        let maxOrder = subcategories.map { $0.order }.max() ?? 0
        let newSub = Subcategory(name: trimmed,
                                 parentID: parentCategory.id,
                                 order: maxOrder + 1,
                                 colorHex: newColorHex)
        context.insert(newSub)
        try? context.save()
        newName = ""
        reorderSubcategories()
    }

    private func moveSubcategory(from source: IndexSet, to destination: Int) {
        var revised = subcategories
        revised.move(fromOffsets: source, toOffset: destination)
        
        // 確保未分類永遠在第一位
        if let uncategorizedIndex = revised.firstIndex(where: { $0.name == "未分類" }) {
            if uncategorizedIndex != 0 {
                revised.move(fromOffsets: IndexSet(integer: uncategorizedIndex), toOffset: 0)
            }
        }
        
        for (index, sub) in revised.enumerated() {
            sub.order = index
        }
        try? context.save()
    }

    // 左滑刪除觸發的方法
    private func deleteSubcategory(_ sub: Subcategory) {
        if sub.name == "未分類" { return } // 未分類不可刪除
        subcategoryToDelete = sub
        showDeleteAlert = true
    }

    // 實際執行刪除的方法
    private func safeDelete(_ sub: Subcategory) {
        if sub.name == "未分類" { return } // 未分類不可刪除
        
        for tx in transactions where tx.subcategoryID == sub.id {
            tx.subcategoryID = nil
        }
        context.delete(sub)
        try? context.save()
        reorderSubcategories()
    }

    private func reorderSubcategories() {
        var subs = allSubcategories.filter { $0.parentID == parentCategory.id }
                                   .sorted(by: {
                                       if $0.name == "未分類" && $1.name != "未分類" {
                                           return true
                                       } else if $0.name != "未分類" && $1.name == "未分類" {
                                           return false
                                       } else {
                                           return $0.order < $1.order
                                       }
                                   })
        
        for (index, sub) in subs.enumerated() {
            sub.order = index
        }
        try? context.save()
    }
}
