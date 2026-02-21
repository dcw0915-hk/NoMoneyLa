import SwiftUI
import SwiftData
import WidgetKit   // 新增

struct PayerListView: View {
    @EnvironmentObject var langManager: LanguageManager
    @Environment(\.modelContext) private var context
    @Query(sort: \Payer.order) private var allPayers: [Payer]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @State private var newName: String = ""
    @State private var newColorHex: String = "#3498db"
    @State private var showDeleteAlert = false
    @State private var payerToDelete: Payer?
    @State private var showCannotDeleteAlert = false
    @State private var cannotDeletePayerName = ""

    @State private var editingPayerID: UUID?
    @State private var inlineEditedName: String = ""
    @FocusState private var isInlineFocused: Bool

    private var payers: [Payer] {
        allPayers.sorted(by: { $0.order < $1.order })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(langManager.localized("add_payer_section")) {
                    HStack(spacing: 12) {
                        TextField(langManager.localized("enter_name_placeholder"), text: $newName)
                            .submitLabel(.done)
                            .onSubmit { addPayer() }
                        
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: newColorHex) },
                            set: { newColorHex = $0.toHex() ?? "#3498db" }
                        ))
                        .labelsHidden()
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                        
                        Button(langManager.localized("add_button")) { addPayer() }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .frame(height: 44)
                }

                Section(langManager.localized("existing_payers_section")) {
                    ForEach(payers) { payer in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                                .frame(width: 18, height: 18)

                            if editingPayerID == payer.id {
                                inlineEditView(for: payer)
                            } else {
                                Text(payer.isDefault ? langManager.localized("default_payer_name") : payer.name)
                                    .font(.body)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }

                            Spacer()

                            // 編輯模式時隱藏顏色選擇器和編輯按鈕
                            if editingPayerID != payer.id {
                                ColorPicker("", selection: Binding(
                                    get: { Color(hex: payer.colorHex ?? "#A8A8A8") },
                                    set: { newColor in
                                        payer.colorHex = newColor.toHex() ?? "#A8A8A8"
                                        try? context.save()
                                    }
                                ))
                                .labelsHidden()
                                .frame(width: 30, height: 30)
                                .clipShape(Circle())

                                if !payer.isDefault {
                                    Button {
                                        startInlineEdit(for: payer)
                                    } label: {
                                        Image(systemName: "pencil")
                                            .imageScale(.medium)
                                            .foregroundColor(.primary)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                    .frame(width: 32, height: 32)
                                } else {
                                    Spacer()
                                        .frame(width: 32)
                                }
                            }
                        }
                        .frame(height: 44)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        // 添加左滑刪除功能（預設付款人除外）
                        .swipeActions(edge: .trailing, allowsFullSwipe: !payer.isDefault) {
                            if !payer.isDefault {
                                Button(role: .destructive) {
                                    deletePayer(payer)
                                } label: {
                                    Label(langManager.localized("delete_button"), systemImage: "trash")
                                }
                            }
                        }
                    }
                    .onMove(perform: movePayer)
                }
            }
            .navigationTitle(langManager.localized("manage_payers_title"))
            .alert(langManager.localized("delete_payer_title"), isPresented: $showDeleteAlert, presenting: payerToDelete) { payer in
                Button(langManager.localized("cancel_button"), role: .cancel) {}
                Button(langManager.localized("delete_button"), role: .destructive) { safeDelete(payer) }
            } message: { payer in
                Text(String(format: langManager.localized("delete_payer_confirmation"), payer.isDefault ? langManager.localized("default_payer_name") : payer.name))
            }
            .alert(langManager.localized("cannot_delete_title"), isPresented: $showCannotDeleteAlert) {
                Button(langManager.localized("understand_button"), role: .cancel) { }
            } message: {
                Text(String(format: langManager.localized("default_payer_cannot_delete"), cannotDeletePayerName))
            }
        }
    }

    // MARK: - 子視圖
    private func inlineEditView(for payer: Payer) -> some View {
        HStack(spacing: 8) {
            TextField(langManager.localized("name_label"), text: $inlineEditedName)
                .focused($isInlineFocused)
                .submitLabel(.done)
                .onSubmit { commitInlineEdit(for: payer) }
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
                commitInlineEdit(for: payer)
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
    private func startInlineEdit(for payer: Payer) {
        guard !payer.isDefault else { return }
        editingPayerID = payer.id
        inlineEditedName = payer.name
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isInlineFocused = true
        }
    }

    private func commitInlineEdit(for payer: Payer) {
        let trimmed = inlineEditedName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            // 編輯時檢查重複名稱
            let finalName = generateUniqueName(baseName: trimmed, excluding: payer.id)
            payer.name = finalName
            do {
                try context.save()
                reorderPayers()
            } catch {
                print("儲存付款人名稱失敗：\(error.localizedDescription)")
            }
        }
        editingPayerID = nil
        inlineEditedName = ""
        isInlineFocused = false
    }

    private func cancelInlineEdit() {
        editingPayerID = nil
        inlineEditedName = ""
        isInlineFocused = false
    }

    private func addPayer() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        
        // 生成唯一名稱
        let uniqueName = generateUniqueName(baseName: trimmed)
        
        let maxOrder = payers.map { $0.order }.max() ?? 0
        let newPayer = Payer(name: uniqueName,
                            order: maxOrder + 1,
                            colorHex: newColorHex)
        context.insert(newPayer)
        try? context.save()
        newName = ""
        newColorHex = "#3498db"
    }

    private func movePayer(from source: IndexSet, to destination: Int) {
        var revised = payers
        revised.move(fromOffsets: source, toOffset: destination)
        for (index, payer) in revised.enumerated() { payer.order = index }
        try? context.save()
    }

    // 左滑刪除觸發的方法
    private func deletePayer(_ payer: Payer) {
        if payer.isDefault {
            cannotDeletePayerName = langManager.localized("default_payer_name")
            showCannotDeleteAlert = true
            return
        }
        payerToDelete = payer
        showDeleteAlert = true
    }

    // 實際執行刪除的方法
    private func safeDelete(_ payer: Payer) {
        guard !payer.isDefault else { return } // 最後一道防線
        
        for tx in transactions {
            tx.contributions.removeAll { $0.payer.id == payer.id }
        }
        context.delete(payer)
        do {
            try context.save()
            WidgetCenter.shared.reloadTimelines(ofKind: "NoMoneyLaWidget") // 新增
        } catch {
            print("刪除付款人失敗：\(error)")
        }
    }

    private func reorderPayers() {
        let sortedPayers = allPayers.sorted(by: { $0.order < $1.order })
        for (index, payer) in sortedPayers.enumerated() {
            payer.order = index
        }
        try? context.save()
    }
    
    // MARK: - 重複名稱處理
    private func generateUniqueName(baseName: String, excluding payerID: UUID? = nil) -> String {
        var candidate = baseName
        var counter = 2
        
        while payerNameExists(candidate, excluding: payerID) {
            candidate = "\(baseName) - \(counter)"
            counter += 1
        }
        
        return candidate
    }
    
    private func payerNameExists(_ name: String, excluding payerID: UUID? = nil) -> Bool {
        if let excludingID = payerID {
            return payers.contains { $0.id != excludingID && $0.name == name }
        } else {
            return payers.contains { $0.name == name }
        }
    }
}
