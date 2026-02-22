import SwiftUI
import SwiftData
import WidgetKit

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

                                    Text(payer.isDefault ? langManager.localized("default_payer_name") : payer.name)
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
            .navigationTitle(categoryDisplayName(for: managedCategory))
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

    private func categoryDisplayName(for category: Category?) -> String {
        guard let cat = category else { return langManager.localized("assign_payers_title") }
        if cat.isDefault {
            return langManager.localized("uncategorized_label")
        } else {
            return cat.name
        }
    }

    // MARK: - Data
    private func loadData() {
        isLoading = true

        DispatchQueue.main.async {
            do {
                let payersFetch = FetchDescriptor<Payer>(sortBy: [SortDescriptor(\.order)])
                let payers = try context.fetch(payersFetch)
                self.allPayers = payers
                
                let categoriesFetch = FetchDescriptor<Category>()
                let categories = try context.fetch(categoriesFetch)
                if let found = categories.first(where: { $0.id == self.categoryID }) {
                    self.managedCategory = found
                    self.selectedPayerIDs = Set(found.assignedPayerIDs)
                } else {
                    self.managedCategory = nil
                    self.selectedPayerIDs = []
                }
            } catch {
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
            dismiss()
            return
        }

        let newAssignedIDs = Array(Set(selectedPayerIDs))
        category.assignedPayerIDs = newAssignedIDs
        
        do {
            try context.save()
        } catch {
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

                            if editingCategoryID != category.id {
                                actionButtons(for: category)
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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
                let displayName = category.isDefault ? langManager.localized("uncategorized_label") : category.name
                Text(String(format: langManager.localized("delete_category_confirmation"), displayName))
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
        let displayName = category.isDefault ? langManager.localized("uncategorized_label") : category.name
        return Text(displayName)
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

            if !category.isDefault {
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
            } else {
                Spacer().frame(width: 36)
            }

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
        if category.isDefault { return }
        editingCategoryID = category.id
        inlineEditedName = category.name
    }

    private func commitInlineEdit(for category: Category) {
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
        }
        newName = ""
    }

    private func moveCategory(from source: IndexSet, to destination: Int) {
        var revised = categories
        
        let defaultCategoryIndex = revised.firstIndex(where: { $0.isDefault })
        if let defaultIndex = defaultCategoryIndex {
            if source.contains(defaultIndex) {
                return
            }
        }
        
        revised.move(fromOffsets: source, toOffset: destination)
        for (index, cat) in revised.enumerated() { cat.order = index }
        try? context.save()
    }

    private func deleteCategory(_ category: Category) {
        if category.isDefault {
            showCannotDeleteAlert = true
            return
        }
        categoryToDelete = category
        showDeleteAlert = true
    }

    private func safeDelete(_ category: Category) {
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
            WidgetCenter.shared.reloadTimelines(ofKind: "NoMoneyLaWidget")
            reorderCategories()
        } catch {
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
