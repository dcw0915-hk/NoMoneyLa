// PayerListView.swift
import SwiftUI
import SwiftData

struct PayerListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Payer.order) private var allPayers: [Payer]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @State private var newName: String = ""
    @State private var newColorHex: String = "#3498db"
    @State private var showDeleteAlert = false
    @State private var payerToDelete: Payer?

    @State private var editingPayerID: UUID?
    @State private var inlineEditedName: String = ""
    @FocusState private var isInlineFocused: Bool

    private var payers: [Payer] {
        allPayers.sorted(by: { $0.order < $1.order })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("新增付款人") {
                    HStack(spacing: 12) {
                        TextField("輸入名稱", text: $newName)
                            .submitLabel(.done)
                            .onSubmit { addPayer() }
                        
                        // Color picker moved to just before (left of) the add button
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: newColorHex) },
                            set: { newColorHex = $0.toHex() ?? "#3498db" }
                        ))
                        .labelsHidden()
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                        
                        Button("新增") { addPayer() }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .frame(height: 44)
                }

                Section("已建立的付款人") {
                    ForEach(payers) { payer in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                                .frame(width: 18, height: 18)

                            if editingPayerID == payer.id {
                                TextField("名稱", text: $inlineEditedName)
                                    .focused($isInlineFocused)
                                    .submitLabel(.done)
                                    .onSubmit { commitInlineEdit(for: payer) }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
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
                                Text(payer.name)
                                    .font(.body)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }

                            Spacer()

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

                            Button {
                                startInlineEdit(for: payer)
                            } label: {
                                Image(systemName: "pencil")
                                    .imageScale(.medium)
                                    .foregroundColor(.primary)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .frame(width: 32, height: 32)

                            Button(role: .destructive) {
                                payerToDelete = payer
                                showDeleteAlert = true
                            } label: {
                                Image(systemName: "trash")
                                    .imageScale(.medium)
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .frame(width: 32, height: 32)
                        }
                        .frame(height: 44)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onMove(perform: movePayer)
                }
            }
            .navigationTitle("管理付款人")
            .alert("刪除付款人", isPresented: $showDeleteAlert, presenting: payerToDelete) { payer in
                Button("取消", role: .cancel) {}
                Button("刪除", role: .destructive) { safeDelete(payer) }
            } message: { payer in
                Text("刪除付款人「\(payer.name)」會同時刪除其在所有交易中的分攤記錄，確定要刪除嗎？")
            }
        }
    }

    private func startInlineEdit(for payer: Payer) {
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

    private func safeDelete(_ payer: Payer) {
        for tx in transactions {
            tx.contributions.removeAll { $0.payer.id == payer.id }
        }
        context.delete(payer)
        try? context.save()
    }

    private func reorderPayers() {
        let sortedPayers = allPayers.sorted(by: { $0.order < $1.order })
        for (index, payer) in sortedPayers.enumerated() {
            payer.order = index
        }
        try? context.save()
    }
    
    // MARK: - 重複名稱處理
    
    /// 生成唯一名稱，如果基礎名稱已存在，則自動添加 "- 2", "- 3" 等後綴
    /// - Parameters:
    ///   - baseName: 使用者輸入的原始名稱
    ///   - excluding: 可選的UUID，用於排除檢查（編輯現有付款人時使用）
    /// - Returns: 當前付款人列表中不存在的唯一名稱
    private func generateUniqueName(baseName: String, excluding payerID: UUID? = nil) -> String {
        var candidate = baseName
        var counter = 2
        
        // 持續嘗試直到找到唯一名稱
        while payerNameExists(candidate, excluding: payerID) {
            candidate = "\(baseName) - \(counter)"
            counter += 1
        }
        
        return candidate
    }
    
    /// 檢查付款人名稱是否已存在
    /// - Parameters:
    ///   - name: 要檢查的名稱
    ///   - excluding: 可選的UUID，用於排除檢查（編輯現有付款人時使用）
    /// - Returns: 如果名稱已存在則返回true
    private func payerNameExists(_ name: String, excluding payerID: UUID? = nil) -> Bool {
        if let excludingID = payerID {
            // 編輯時：檢查是否有"其他"付款人使用此名稱
            return payers.contains { $0.id != excludingID && $0.name == name }
        } else {
            // 新增時：檢查是否有"任何"付款人使用此名稱
            return payers.contains { $0.name == name }
        }
    }
}
