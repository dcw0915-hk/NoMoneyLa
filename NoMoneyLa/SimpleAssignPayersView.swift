// SimpleAssignPayersView.swift 完整更新版本

import SwiftUI
import SwiftData

struct SimpleAssignPayersView: View {
    @EnvironmentObject var langManager: LanguageManager
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    let category: Category
    @State private var selectedPayerIDs: Set<UUID> = []
    @State private var allPayers: [Payer] = []
    
    var body: some View {
        NavigationView {
            VStack {
                Text(String(format: langManager.localized("assign_payers_to_category"), category.name))
                    .font(.headline)
                    .padding()
                
                Text("\(langManager.localized("category_id_label")): \(String(category.id.uuidString.prefix(8)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("\(langManager.localized("assigned_payers_count")): \(category.assignedPayerIDs.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                List {
                    ForEach(allPayers) { payer in
                        HStack {
                            Circle()
                                .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                                .frame(width: 20, height: 20)
                            
                            Text(payer.name)
                            
                            Spacer()
                            
                            if selectedPayerIDs.contains(payer.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .onTapGesture {
                            if selectedPayerIDs.contains(payer.id) {
                                selectedPayerIDs.remove(payer.id)
                            } else {
                                selectedPayerIDs.insert(payer.id)
                            }
                        }
                    }
                }
                
                Button(langManager.localized("save_button")) {
                    category.assignedPayerIDs = Array(selectedPayerIDs)
                    try? context.save()
                    dismiss()
                }
                .padding()
            }
            .onAppear {
                loadPayers()
            }
        }
    }
    
    private func loadPayers() {
        do {
            let fetchDescriptor = FetchDescriptor<Payer>(
                sortBy: [SortDescriptor(\.order)]
            )
            let payers = try context.fetch(fetchDescriptor)
            self.allPayers = payers
            self.selectedPayerIDs = Set(category.assignedPayerIDs)
            
            print("DEBUG: 載入 \(payers.count) 個付款人")
            print("DEBUG: 分類 assignedPayerIDs: \(category.assignedPayerIDs)")
            print("DEBUG: 設定 selectedPayerIDs: \(selectedPayerIDs)")
        } catch {
            print("載入付款人錯誤: \(error)")
        }
    }
}
