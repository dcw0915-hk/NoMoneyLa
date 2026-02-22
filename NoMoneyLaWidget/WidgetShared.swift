import SwiftData
import Foundation

let appGroupID = "group.Ricky.NoMoneyLa"
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
