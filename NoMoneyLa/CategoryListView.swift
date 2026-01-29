import SwiftUI
import SwiftData

// AssignPayersView.swift
struct AssignPayersView: View {
    @EnvironmentObject var langManager: LanguageManager
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let categoryID: UUID

    @State private var managedCategory: Category?
    @State private var selectedPayerIDs: Set<UUID> = []
    @State private var allPayers: [Payer] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView(langManager.localized("loading_label"))
                        .padding()
                } else if allPayers.isEmpty {
                    ContentUnavailableView(
                        langManager.localized("no_payers_title"),
                        systemImage: "person.3",
                        description: Text(langManager.localized("create_payers_first"))
                    )
                } else {
                    List {
                        Section(langManager.localized("available_payers_section")) {
                            ForEach(allPayers) { payer in
                                HStack {
                                    Circle()
                                        .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                                        .frame(width: 20, height: 20)

                                    Text(payer.name)
                                        .font(.body)

                                    Spacer()

                                    if selectedPayerIDs.contains(payer.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                            .font(.title3)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.gray)
                                            .font(.title3)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    togglePayerSelection(payer.id)
                                }
                            }
                        }

                        Section {
                            if selectedPayerIDs.isEmpty {
                                Text(langManager.localized("no_payers_selected"))
                                    .foregroundColor(.secondary)
                                    .italic()
                            } else {
                                Text(String(format: langManager.localized("selected_payers_count"), selectedPayerIDs.count))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(managedCategory?.name ?? langManager.localized("assign_payers_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(langManager.localized("cancel_button")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(langManager.localized("save_button")) { saveAssignedPayers() }
                        .disabled(isLoading)
                }
            }
            .onAppear { loadData() }
        }
    }

    // MARK: - Data
    private func loadData() {
        isLoading = true

        DispatchQueue.main.async {
            do {
                // 取得所有付款人
                let payersFetch = FetchDescriptor<Payer>(sortBy: [SortDescriptor(\.order)])
                let payers = try context.fetch(payersFetch)
                self.allPayers = payers
                
                // 取得受管理的 category 實例（以 id 比對）
                let categoriesFetch = FetchDescriptor<Category>()
                let categories = try context.fetch(categoriesFetch)
                if let found = categories.first(where: { $0.id == self.categoryID }) {
                    self.managedCategory = found
                    self.selectedPayerIDs = Set(found.assignedPayerIDs)
                    
                    // 除錯信息
                    print("=== DEBUG [AssignPayersView] ===")
                    print("分類名稱: \(found.name)")
                    print("分類ID: \(found.id)")
                    print("assignedPayerIDs: \(found.assignedPayerIDs)")
                    print("selectedPayerIDs: \(self.selectedPayerIDs)")
                    print("付款人總數: \(payers.count)")
                    
                    // 測試 assignedPayers 函數
                    let assigned = found.assignedPayers(in: self.context)
                    print("assignedPayers 函數返回數量: \(assigned.count)")
                    for payer in assigned {
                        print("  - \(payer.name) (\(payer.id))")
                    }
                    print("======================")
                    
                } else {
                    print("DEBUG [AssignPayersView]: 無法在 ModelContext 中找到 category id: \(self.categoryID)")
                    self.managedCategory = nil
                    self.selectedPayerIDs = []
                }
            } catch {
                print("DEBUG [AssignPayersView]: 載入付款人或分類時出錯：\(error)")
                self.allPayers = []
                self.managedCategory = nil
                self.selectedPayerIDs = []
            }

            self.isLoading = false
        }
    }

    private func togglePayerSelection(_ payerID: UUID) {
        if selectedPayerIDs.contains(payerID) {
            selectedPayerIDs.remove(payerID)
        } else {
            selectedPayerIDs.insert(payerID)
        }
    }

    // MARK: - Save
    private func saveAssignedPayers() {
        guard let category = managedCategory else {
            print("DEBUG [AssignPayersView]: 無受管理的 Category，無法儲存")
            dismiss()
            return
        }

        // 去重並儲存
        let newAssignedIDs = Array(Set(selectedPayerIDs))
        category.assignedPayerIDs = newAssignedIDs
        
        // 除錯信息
        print("=== DEBUG [AssignPayersView - Save] ===")
        print("分類: \(category.name)")
        print("儲存前 assignedPayerIDs: \(category.assignedPayerIDs)")
        
        do {
            try context.save()
            
            // 重新讀取確認儲存
            let categoriesFetch = FetchDescriptor<Category>()
            let categories = try context.fetch(categoriesFetch)
            if let savedCategory = categories.first(where: { $0.id == category.id }) {
                print("儲存後 assignedPayerIDs: \(savedCategory.assignedPayerIDs)")
                print("儲存成功！")
            }
            print("======================")
        } catch {
            print("DEBUG [AssignPayersView]: 儲存 assignedPayerIDs 時發生錯誤：\(error)")
        }

        dismiss()
    }
}

// CategoryListView.swift
struct CategoryListView: View {
    @EnvironmentObject var langManager: LanguageManager
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.order) private var allCategories: [Category]
    @Query(sort: \Subcategory.order) private var allSubcategories: [Subcategory]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @State private var newName: String = ""
    @State private var showDeleteAlert = false
    @State private var categoryToDelete: Category?

    @State private var showingAssignPayersForCategory: Category?

    @State private var editingCategoryID: UUID?
    @State private var inlineEditedName: String = ""
    @FocusState private var isInlineFocused: Bool
    
    @State private var showCannotDeleteAlert = false

    private var categories: [Category] {
        allCategories.sorted(by: { $0.order < $1.order })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(langManager.localized("add_category_section")) {
                    HStack {
                        TextField(langManager.localized("enter_name_placeholder"), text: $newName)
                        Button(langManager.localized("add_button")) { addCategory() }
                    }
                }

                Section(langManager.localized("existing_categories_section")) {
                    ForEach(categories) { category in
                        HStack(spacing: 12) {
                            if editingCategoryID == category.id {
                                inlineEditView(for: category)
                            } else {
                                normalView(for: category)
                            }

                            Spacer()

                            // 編輯模式時隱藏操作按鈕
                            if editingCategoryID != category.id {
                                actionButtons(for: category)
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        // 添加左滑刪除功能（預設分類除外）
                        .swipeActions(edge: .trailing, allowsFullSwipe: !category.isDefault) {
                            if !category.isDefault {
                                Button(role: .destructive) {
                                    deleteCategory(category)
                                } label: {
                                    Label(langManager.localized("delete_button"), systemImage: "trash")
                                }
                            }
                        }
                    }
                    .onMove(perform: moveCategory)
                }
            }
            .navigationTitle(langManager.localized("manage_categories_title"))
            .alert(langManager.localized("delete_category_title"), isPresented: $showDeleteAlert, presenting: categoryToDelete) { category in
                Button(langManager.localized("cancel_button"), role: .cancel) {}
                Button(langManager.localized("delete_button"), role: .destructive) { safeDelete(category) }
            } message: { category in
                Text(String(format: langManager.localized("delete_category_confirmation"), category.name))
            }
            .alert(langManager.localized("cannot_delete_title"), isPresented: $showCannotDeleteAlert) {
                Button(langManager.localized("understand_button"), role: .cancel) { }
            } message: {
                Text(langManager.localized("cannot_delete_default_category"))
            }
            .sheet(item: $showingAssignPayersForCategory) { category in
                AssignPayersView(categoryID: category.id)
                    .environment(\.modelContext, context)
                    .onDisappear {
                        showingAssignPayersForCategory = nil
                        // 在關閉時打印除錯信息
                        print("DEBUG [CategoryListView]: AssignPayersView 已關閉")
                        print("DEBUG [CategoryListView]: 重新檢查分類狀態")
                        
                        // 重新讀取分類數據
                        do {
                            let categoriesFetch = FetchDescriptor<Category>()
                            let categories = try context.fetch(categoriesFetch)
                            if let updatedCategory = categories.first(where: { $0.id == category.id }) {
                                print("分類 \(updatedCategory.name) 的 assignedPayerIDs: \(updatedCategory.assignedPayerIDs)")
                                let assigned = updatedCategory.assignedPayers(in: context)
                                print("assignedPayers 函數返回: \(assigned.map { $0.name })")
                            }
                        } catch {
                            print("重新讀取分類錯誤: \(error)")
                        }
                    }
            }
        }
    }

    // MARK: - 子視圖
    private func inlineEditView(for category: Category) -> some View {
        HStack(spacing: 8) {
            TextField(langManager.localized("name_label"), text: $inlineEditedName)
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
                .frame(maxWidth: .infinity)
                .lineLimit(1)

            Button {
                commitInlineEdit(for: category)
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

    private func normalView(for category: Category) -> some View {
        Text(category.name)
            .font(.body)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func actionButtons(for category: Category) -> some View {
        let assignedPayers = category.assignedPayers(in: context)
        
        return HStack(spacing: 10) {
            Button {
                showingAssignPayersForCategory = category
            } label: {
                let assignedCount = assignedPayers.count
                Image(systemName: assignedCount > 0 ? "person.2.fill" : "person.2")
                    .imageScale(.large)
                    .foregroundColor(assignedCount > 0 ? .blue : .primary)
            }
            .buttonStyle(BorderlessButtonStyle())
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())

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
        }
    }

    // MARK: - 方法
    private func startInlineEdit(for category: Category) {
        // 預設分類唔可以改名
        if category.isDefault { return }
        editingCategoryID = category.id
        inlineEditedName = category.name
    }

    private func commitInlineEdit(for category: Category) {
        // 預設分類唔可以改名
        if category.isDefault {
            editingCategoryID = nil
            return
        }
        
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

    private func addCategory() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // 防止建立重複嘅「未分類」分類
        guard trimmed != langManager.localized("uncategorized_label") else {
            newName = ""
            return
        }
        
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
        
        // 確保預設分類唔可以移動
        let defaultCategoryIndex = revised.firstIndex(where: { $0.isDefault })
        if let defaultIndex = defaultCategoryIndex {
            // 如果嘗試移動預設分類，直接返回
            if source.contains(defaultIndex) {
                return
            }
        }
        
        revised.move(fromOffsets: source, toOffset: destination)
        for (index, cat) in revised.enumerated() { cat.order = index }
        try? context.save()
    }

    // 左滑刪除觸發的方法
    private func deleteCategory(_ category: Category) {
        // 檢查是否為預設分類
        if category.isDefault {
            // 顯示提示，唔准刪除
            showCannotDeleteAlert = true
            return
        }
        categoryToDelete = category
        showDeleteAlert = true
    }

    // 實際執行刪除的方法
    private func safeDelete(_ category: Category) {
        // 再次檢查是否為預設分類
        guard !category.isDefault else { return }
        
        let subs = allSubcategories.filter { $0.parentID == category.id }
        for sub in subs {
            for tx in transactions where tx.subcategoryID == sub.id {
                tx.subcategoryID = nil
            }
            context.delete(sub)
        }
        context.delete(category)
        do {
            try context.save()
            reorderCategories()
        } catch {
            print("刪除分類失敗：\(error.localizedDescription)")
        }
    }

    private func reorderCategories() {
        let topCategories = allCategories.sorted(by: { $0.order < $1.order })
        for (index, cat) in topCategories.enumerated() {
            cat.order = index
        }
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
